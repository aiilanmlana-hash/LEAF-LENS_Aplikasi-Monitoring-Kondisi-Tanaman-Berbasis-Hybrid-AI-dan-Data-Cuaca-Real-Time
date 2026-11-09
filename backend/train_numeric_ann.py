"""Train and hold out validation for the optional numeric health ANN.

Expected columns:
green_ratio,dry_ratio,mobilenet_confidence,fuzzy_health_score,mean_hue,
mean_saturation,mean_value,temperature_c,humidity_pct,precipitation_mm,label
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np

from backend.numeric_ann import NumericFeatureANN

FEATURE_COLUMNS = (
    "green_ratio",
    "dry_ratio",
    "mobilenet_confidence",
    "fuzzy_health_score",
    "mean_hue",
    "mean_saturation",
    "mean_value",
    "temperature_c",
    "humidity_pct",
    "precipitation_mm",
)
LABELS = ("healthy", "dry", "infected")


def load_dataset(csv_path: Path) -> tuple[np.ndarray, np.ndarray]:
    features: list[list[float]] = []
    labels: list[str] = []
    with csv_path.open(newline="", encoding="utf-8-sig") as file:
        reader = csv.DictReader(file)
        expected = {*FEATURE_COLUMNS, "label"}
        missing = expected - set(reader.fieldnames or ())
        if missing:
            raise ValueError(f"Dataset is missing columns: {', '.join(sorted(missing))}")
        for line, row in enumerate(reader, start=2):
            try:
                features.append([float(row[column]) for column in FEATURE_COLUMNS])
                labels.append(row["label"].strip().lower())
            except (TypeError, ValueError) as error:
                raise ValueError(f"Invalid numeric data on CSV line {line}.") from error
    unknown = set(labels) - set(LABELS)
    if unknown:
        raise ValueError(f"Unsupported labels: {', '.join(sorted(unknown))}")
    if not features:
        raise ValueError("The training dataset has no rows.")
    class_indexes = np.asarray([LABELS.index(label) for label in labels])
    return np.asarray(features, dtype=np.float64), class_indexes


def _stratified_split(
    labels: np.ndarray, fraction: float, seed: int
) -> tuple[np.ndarray, np.ndarray]:
    generator = np.random.default_rng(seed)
    training: list[int] = []
    validation: list[int] = []
    for class_index in range(len(LABELS)):
        indexes = np.flatnonzero(labels == class_index)
        generator.shuffle(indexes)
        if len(indexes) < 2:
            training.extend(indexes.tolist())
            continue
        validation_count = min(
            len(indexes) - 1, max(1, round(len(indexes) * fraction))
        )
        validation.extend(indexes[:validation_count].tolist())
        training.extend(indexes[validation_count:].tolist())
    if not validation:
        raise ValueError("At least one class must have two or more labeled rows.")
    generator.shuffle(training)
    generator.shuffle(validation)
    return np.asarray(training), np.asarray(validation)


def _classification_metrics(
    truth: np.ndarray, predictions: np.ndarray
) -> dict[str, object]:
    confusion = np.zeros((len(LABELS), len(LABELS)), dtype=np.int64)
    np.add.at(confusion, (truth, predictions), 1)
    true_positive = np.diag(confusion).astype(np.float64)
    support = confusion.sum(axis=1).astype(np.float64)
    predicted = confusion.sum(axis=0).astype(np.float64)
    precision = np.divide(
        true_positive, predicted, out=np.zeros_like(true_positive), where=predicted > 0
    )
    recall = np.divide(
        true_positive, support, out=np.zeros_like(true_positive), where=support > 0
    )
    f1 = np.divide(
        2 * precision * recall,
        precision + recall,
        out=np.zeros_like(precision),
        where=(precision + recall) > 0,
    )
    total = int(confusion.sum())
    return {
        "samples": total,
        "accuracy": float(true_positive.sum() / total) if total else 0.0,
        "precision_macro": float(precision.mean()),
        "recall_macro": float(recall.mean()),
        "f1_macro": float(f1.mean()),
        "f1_weighted": float(np.average(f1, weights=support)) if total else 0.0,
        "per_class": [
            {
                "label": LABELS[index],
                "support": int(support[index]),
                "precision": float(precision[index]),
                "recall": float(recall[index]),
                "f1": float(f1[index]),
            }
            for index in range(len(LABELS))
        ],
        "confusion_matrix": confusion.tolist(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path, help="Labeled CSV dataset")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("backend/numeric_ann_weights.json"),
        help="Output checkpoint path",
    )
    parser.add_argument("--report", type=Path, help="Output metrics JSON path")
    parser.add_argument("--epochs", type=int, default=700)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--patience", type=int, default=40)
    parser.add_argument("--validation-fraction", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=17)
    args = parser.parse_args()
    if args.epochs < 1 or args.batch_size < 1 or args.patience < 0:
        raise SystemExit("epochs and batch-size must be positive; patience nonnegative.")
    if not 0 < args.validation_fraction < 1:
        raise SystemExit("validation-fraction must be between 0 and 1.")

    features, labels = load_dataset(args.dataset)
    training_indexes, validation_indexes = _stratified_split(
        labels, args.validation_fraction, args.seed
    )
    model = NumericFeatureANN(input_size=len(FEATURE_COLUMNS), seed=args.seed).fit(
        features[training_indexes],
        labels[training_indexes],
        epochs=args.epochs,
        batch_size=args.batch_size,
        validation_data=(
            features[validation_indexes],
            labels[validation_indexes],
        ),
        patience=args.patience,
    )
    predictions = np.asarray(
        [LABELS.index(row["label"]) for row in model.predict(features[validation_indexes])]
    )
    report_path = args.report or args.output.with_suffix(".metrics.json")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    model.save(args.output)
    report = {
        "model": "NumericFeatureANN",
        "features": list(FEATURE_COLUMNS),
        "labels": list(LABELS),
        "dataset": str(args.dataset.resolve()),
        "training_samples": int(len(training_indexes)),
        "validation_samples": int(len(validation_indexes)),
        "seed": args.seed,
        "metrics": _classification_metrics(labels[validation_indexes], predictions),
        "checkpoint": str(args.output.resolve()),
        "note": (
            "This ANN requires labeled numeric feature rows. PlantVillage image "
            "classes alone are not labels for the green/dry/infected health target. "
            "Weather values must be paired with the same observation."
        ),
    }
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    metrics = report["metrics"]
    print(
        f"Validation ({len(validation_indexes)} rows): "
        f"accuracy={metrics['accuracy']:.2%}, "
        f"macro_f1={metrics['f1_macro']:.4f}"
    )
    print(f"Saved numeric ANN checkpoint to {args.output}")
    print(f"Saved metrics report to {report_path}")


if __name__ == "__main__":
    main()
