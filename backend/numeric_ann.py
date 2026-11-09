"""Small trainable NumPy ANN for labeled numeric plant features.

The API loads a trained JSON checkpoint from its default or configured path. It
never silently substitutes random weights for a real prediction.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np


class NumericFeatureANN:
    _FEATURE_SCALE = np.asarray(
        [
            100.0,
            100.0,
            100.0,
            100.0,
            180.0,
            255.0,
            255.0,
            60.0,
            100.0,
            200.0,
        ],
        dtype=np.float64,
    )

    def __init__(
        self,
        input_size: int = 7,
        hidden_size: int = 8,
        labels: tuple[str, ...] = ("healthy", "dry", "infected"),
        *,
        seed: int = 17,
    ) -> None:
        if input_size < 1 or hidden_size < 1 or not labels:
            raise ValueError("ANN layer sizes and class labels must be non-empty.")
        self.input_size = input_size
        self.hidden_size = hidden_size
        self.labels = labels
        self._rng = np.random.default_rng(seed)
        self._weights_1: np.ndarray | None = None
        self._bias_1: np.ndarray | None = None
        self._weights_2: np.ndarray | None = None
        self._bias_2: np.ndarray | None = None
        self._feature_mean: np.ndarray | None = None
        self._feature_scale: np.ndarray | None = None

    @property
    def is_fitted(self) -> bool:
        return self._weights_1 is not None

    def fit(
        self,
        features: np.ndarray,
        labels: np.ndarray,
        *,
        epochs: int = 500,
        learning_rate: float = 0.01,
        batch_size: int = 32,
        validation_data: tuple[np.ndarray, np.ndarray] | None = None,
        patience: int = 40,
        weight_decay: float = 1e-4,
    ) -> "NumericFeatureANN":
        features, labels = self._validated_data(features, labels, "training")
        if epochs < 1 or learning_rate <= 0 or batch_size < 1 or patience < 0:
            raise ValueError("epochs, learning_rate, and batch_size must be positive.")
        if weight_decay < 0:
            raise ValueError("weight_decay must be nonnegative.")

        validation_features: np.ndarray | None = None
        validation_labels: np.ndarray | None = None
        if validation_data is not None:
            validation_features, validation_labels = self._validated_data(
                validation_data[0], validation_data[1], "validation"
            )
            if not len(validation_features):
                raise ValueError("validation_data must contain at least one row.")

        self._feature_mean = np.mean(features, axis=0, keepdims=True)
        self._feature_scale = np.std(features, axis=0, keepdims=True)
        self._feature_scale[self._feature_scale < 1e-8] = 1.0
        # Fit normalization on training rows only, then reuse it for validation
        # and later predictions to avoid leaking validation information.
        normalized = self._normalize(features)
        normalized_validation = (
            self._normalize(validation_features)
            if validation_features is not None
            else None
        )

        self._weights_1 = self._rng.normal(
            0, np.sqrt(2 / self.input_size), (self.input_size, self.hidden_size)
        )
        self._bias_1 = np.zeros((1, self.hidden_size))
        self._weights_2 = self._rng.normal(
            0, np.sqrt(2 / self.hidden_size), (self.hidden_size, len(self.labels))
        )
        self._bias_2 = np.zeros((1, len(self.labels)))
        targets = np.eye(len(self.labels), dtype=np.float64)[labels]
        parameters = (self._weights_1, self._bias_1, self._weights_2, self._bias_2)
        first_moments = [np.zeros_like(parameter) for parameter in parameters]
        second_moments = [np.zeros_like(parameter) for parameter in parameters]
        best_state: tuple[np.ndarray, ...] | None = None
        best_loss = float("inf")
        stale_epochs = 0
        step = 0

        for _ in range(epochs):
            permutation = self._rng.permutation(len(normalized))
            for batch_start in range(0, len(normalized), batch_size):
                indexes = permutation[batch_start : batch_start + batch_size]
                batch_features = normalized[indexes]
                batch_targets = targets[indexes]
                hidden, probabilities = self._forward(batch_features)
                # Backpropagate cross-entropy gradients from output to hidden layer.
                output_gradient = (probabilities - batch_targets) / len(indexes)
                weights_2_gradient = (
                    hidden.T @ output_gradient + weight_decay * self._weights_2
                )
                bias_2_gradient = np.sum(output_gradient, axis=0, keepdims=True)
                hidden_gradient = np.einsum(
                    "bc,hc->bh", output_gradient, self._weights_2
                ) * (1 - hidden**2)
                weights_1_gradient = (
                    batch_features.T @ hidden_gradient
                    + weight_decay * self._weights_1
                )
                bias_1_gradient = np.sum(hidden_gradient, axis=0, keepdims=True)
                gradients = (
                    weights_1_gradient,
                    bias_1_gradient,
                    weights_2_gradient,
                    bias_2_gradient,
                )
                if any(not np.all(np.isfinite(gradient)) for gradient in gradients):
                    raise FloatingPointError("ANN training produced non-finite gradients.")
                largest_gradient = max(
                    float(np.max(np.abs(gradient))) for gradient in gradients
                )
                if largest_gradient > 5.0:
                    gradients = tuple(
                        gradient * (5.0 / largest_gradient) for gradient in gradients
                    )
                step += 1
                for index, (parameter, gradient) in enumerate(
                    zip(parameters, gradients)
                ):
                    first_moments[index] = (
                        0.9 * first_moments[index] + 0.1 * gradient
                    )
                    second_moments[index] = (
                        0.999 * second_moments[index] + 0.001 * gradient**2
                    )
                    corrected_first = first_moments[index] / (1 - 0.9**step)
                    corrected_second = second_moments[index] / (1 - 0.999**step)
                    parameter -= learning_rate * corrected_first / (
                        np.sqrt(corrected_second) + 1e-8
                    )
                    if not np.all(np.isfinite(parameter)):
                        raise FloatingPointError(
                            "ANN training produced non-finite model parameters."
                        )

            if normalized_validation is not None and validation_labels is not None:
                validation_targets = np.eye(len(self.labels), dtype=np.float64)[
                    validation_labels
                ]
                _, validation_probabilities = self._forward(normalized_validation)
                validation_loss = self._cross_entropy(
                    validation_probabilities, validation_targets
                )
                if validation_loss < best_loss - 1e-6:
                    best_loss = validation_loss
                    best_state = tuple(parameter.copy() for parameter in parameters)
                    stale_epochs = 0
                else:
                    stale_epochs += 1
                    if patience and stale_epochs >= patience:
                        break

        if best_state is not None:
            self._weights_1, self._bias_1, self._weights_2, self._bias_2 = best_state
        return self

    def predict(self, features: np.ndarray) -> list[dict[str, Any]]:
        if not self.is_fitted:
            raise RuntimeError("ANN has no trained weights. Train it or load a checkpoint.")
        values = np.asarray(features, dtype=np.float64)
        if values.ndim == 1:
            values = values.reshape(1, -1)
        if values.ndim != 2 or values.shape[1] != self.input_size:
            raise ValueError(f"features must have shape (n, {self.input_size}).")
        if not np.all(np.isfinite(values)):
            raise ValueError("features must contain only finite numbers.")
        _, probabilities = self._forward(self._normalize(values))
        return [
            {
                "label": self.labels[int(index)],
                "confidence": round(float(row[index] * 100), 2),
            }
            for row in probabilities
            for index in [int(np.argmax(row))]
        ]

    def save(self, path: str | Path) -> None:
        if not self.is_fitted:
            raise RuntimeError("Cannot save an ANN without trained weights.")
        assert self._weights_1 is not None
        assert self._bias_1 is not None
        assert self._weights_2 is not None
        assert self._bias_2 is not None
        payload = {
            "version": 3,
            "input_size": self.input_size,
            "hidden_size": self.hidden_size,
            "labels": list(self.labels),
            "weights_1": self._weights_1.tolist(),
            "bias_1": self._bias_1.tolist(),
            "weights_2": self._weights_2.tolist(),
            "bias_2": self._bias_2.tolist(),
            "feature_mean": (
                self._feature_mean.tolist() if self._feature_mean is not None else None
            ),
            "feature_scale": (
                self._feature_scale.tolist()
                if self._feature_scale is not None
                else None
            ),
        }
        output_path = Path(path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(payload), encoding="utf-8")

    @classmethod
    def load(cls, path: str | Path) -> "NumericFeatureANN":
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        model = cls(
            input_size=int(payload["input_size"]),
            hidden_size=int(payload["hidden_size"]),
            labels=tuple(payload["labels"]),
        )
        model._weights_1 = np.asarray(payload["weights_1"], dtype=np.float64)
        model._bias_1 = np.asarray(payload["bias_1"], dtype=np.float64)
        model._weights_2 = np.asarray(payload["weights_2"], dtype=np.float64)
        model._bias_2 = np.asarray(payload["bias_2"], dtype=np.float64)
        if payload.get("feature_mean") is not None:
            model._feature_mean = np.asarray(
                payload["feature_mean"], dtype=np.float64
            )
            model._feature_scale = np.asarray(
                payload["feature_scale"], dtype=np.float64
            )
        if (
            model._weights_1.shape != (model.input_size, model.hidden_size)
            or model._bias_1.shape != (1, model.hidden_size)
            or model._weights_2.shape != (model.hidden_size, len(model.labels))
            or model._bias_2.shape != (1, len(model.labels))
            or (
                model._feature_mean is not None
                and model._feature_mean.shape != (1, model.input_size)
            )
            or (
                model._feature_scale is not None
                and model._feature_scale.shape != (1, model.input_size)
            )
        ):
            raise ValueError("ANN checkpoint has incompatible layer dimensions.")
        parameters = (
            model._weights_1,
            model._bias_1,
            model._weights_2,
            model._bias_2,
        )
        if any(not np.all(np.isfinite(parameter)) for parameter in parameters):
            raise ValueError("ANN checkpoint contains non-finite parameters.")
        if model._feature_scale is not None and (
            not np.all(np.isfinite(model._feature_scale))
            or np.any(model._feature_scale <= 0)
        ):
            raise ValueError("ANN checkpoint has invalid feature normalization.")
        return model

    @staticmethod
    def _softmax(logits: np.ndarray) -> np.ndarray:
        shifted = logits - np.max(logits, axis=1, keepdims=True)
        exponentials = np.exp(np.clip(shifted, -700.0, 0.0))
        return exponentials / np.sum(exponentials, axis=1, keepdims=True)

    @staticmethod
    def _cross_entropy(probabilities: np.ndarray, targets: np.ndarray) -> float:
        return float(
            -np.sum(targets * np.log(np.clip(probabilities, 1e-12, 1.0)))
            / len(targets)
        )

    def _forward(self, values: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        assert self._weights_1 is not None
        assert self._bias_1 is not None
        assert self._weights_2 is not None
        assert self._bias_2 is not None
        hidden = np.tanh(values @ self._weights_1 + self._bias_1)
        # Softmax converts the output-layer scores into class probabilities.
        return hidden, self._softmax(hidden @ self._weights_2 + self._bias_2)

    def _validated_data(
        self, features: np.ndarray, labels: np.ndarray, name: str
    ) -> tuple[np.ndarray, np.ndarray]:
        values = np.asarray(features, dtype=np.float64)
        indexes = np.asarray(labels, dtype=np.int64)
        if values.ndim != 2 or values.shape[1] != self.input_size:
            raise ValueError(f"{name} features must have shape (n, {self.input_size}).")
        if indexes.shape != (values.shape[0],):
            raise ValueError(f"{name} labels must have one class index per feature row.")
        if values.shape[0] == 0:
            raise ValueError(f"{name} data is empty.")
        if np.any(indexes < 0) or np.any(indexes >= len(self.labels)):
            raise ValueError(f"{name} data contains an invalid class index.")
        if not np.all(np.isfinite(values)):
            raise ValueError(f"{name} features must contain only finite numbers.")
        return values, indexes

    def _normalize(self, values: np.ndarray) -> np.ndarray:
        if self._feature_mean is not None and self._feature_scale is not None:
            return (values - self._feature_mean) / self._feature_scale
        if self.input_size in (7, len(self._FEATURE_SCALE)):
            return values / self._FEATURE_SCALE[: self.input_size]
        scale = np.maximum(np.max(np.abs(values), axis=0, keepdims=True), 1.0)
        return values / scale
