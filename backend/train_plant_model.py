"""Train or evaluate a CNN classifier on the PlantVillage train/val split."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import time
from pathlib import Path
from typing import Any, Sequence

import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TARGET_CLASS_PREFIXES = (
    "Corn_(maize)___",
    "Potato___",
    "Tomato___",
)
OOD_CLASS_NAME = "Background_or_Invalid"
CONFIDENCE_THRESHOLD = 0.70


def _is_target_class(class_name: str) -> bool:
    return class_name == OOD_CLASS_NAME or class_name.startswith(TARGET_CLASS_PREFIXES)


def _filter_target_classes(dataset: Any) -> None:
    """Keep only the three requested crops and an optional labeled OOD folder."""
    original_classes = dataset.classes
    classes = [name for name in original_classes if _is_target_class(name)]
    class_to_idx = {name: index for index, name in enumerate(classes)}
    samples = []
    for path, original_index in dataset.samples:
        class_name = original_classes[original_index]
        if class_name in class_to_idx:
            samples.append((path, class_to_idx[class_name]))
    dataset.classes = classes
    dataset.class_to_idx = class_to_idx
    dataset.samples = samples
    dataset.imgs = samples
    dataset.targets = [label for _, label in samples]


def _checkpoint_features(state_dict: dict[str, Any]) -> dict[str, Any]:
    """Reuse backbone weights only; old classifier indices are not trustworthy."""
    if "state_dict" in state_dict and isinstance(state_dict["state_dict"], dict):
        state_dict = state_dict["state_dict"]
    return {
        key.removeprefix("module."): value
        for key, value in state_dict.items()
        if key.removeprefix("module.").startswith("features.")
    }


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--architecture",
        choices=("mobilenet_v2", "efficientnet_b0"),
        default="mobilenet_v2",
        help="Classifier architecture to train or evaluate.",
    )
    parser.add_argument(
        "--dataset-root",
        type=Path,
        default=PROJECT_ROOT / "PlantVillage",
        help="Folder containing separate train/ and val/ ImageFolder datasets.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output checkpoint path consumed by backend.main.",
    )
    parser.add_argument(
        "--initial-checkpoint",
        type=Path,
        help="Optional checkpoint of the selected architecture; its backbone is reused and its classifier is reset.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Metrics JSON path (default: output filename with .metrics.json).",
    )
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--patience", type=int, default=2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--no-pretrained",
        action="store_true",
        help="Skip ImageNet initialization if no earlier checkpoint is available.",
    )
    parser.add_argument(
        "--evaluate-only",
        action="store_true",
        help="Evaluate --output on val/ without training, excluding exact train/ duplicates.",
    )
    parser.add_argument(
        "--save-best-each-epoch",
        action="store_true",
        help="Persist each improved validation checkpoint while training.",
    )
    args = parser.parse_args()
    if args.output is None:
        filename = (
            "model_daun_plantvillage_full_train.pth"
            if args.architecture == "mobilenet_v2"
            else "model_efficientnet_b0_plantvillage.pth"
        )
        args.output = PROJECT_ROOT / "backend" / filename
    return args


def _create_classifier(
    models: Any,
    nn: Any,
    architecture: str,
    class_count: int,
    pretrained: bool,
) -> Any:
    if architecture == "mobilenet_v2":
        weights = models.MobileNet_V2_Weights.DEFAULT if pretrained else None
        model = models.mobilenet_v2(weights=weights)
        input_features = model.last_channel
    elif architecture == "efficientnet_b0":
        weights = models.EfficientNet_B0_Weights.DEFAULT if pretrained else None
        model = models.efficientnet_b0(weights=weights)
        input_features = model.classifier[1].in_features
    else:
        raise ValueError(f"Unsupported model architecture: {architecture}")
    model.classifier[1] = nn.Linear(input_features, class_count)
    return model


def _metrics(confusion: np.ndarray) -> dict[str, Any]:
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
        "accuracy": float(true_positive.sum() / total) if total else 0.0,
        "precision_macro": float(precision.mean()) if len(precision) else 0.0,
        "recall_macro": float(recall.mean()) if len(recall) else 0.0,
        "f1_macro": float(f1.mean()) if len(f1) else 0.0,
        "precision_weighted": (
            float(np.average(precision, weights=support)) if total else 0.0
        ),
        "recall_weighted": float(np.average(recall, weights=support)) if total else 0.0,
        "f1_weighted": float(np.average(f1, weights=support)) if total else 0.0,
        "per_class": [
            {
                "class": index,
                "support": int(support[index]),
                "precision": float(precision[index]),
                "recall": float(recall[index]),
                "f1": float(f1[index]),
            }
            for index in range(len(support))
        ],
        "confusion_matrix": confusion.astype(int).tolist(),
    }


def _confidence_distribution(confidences: Sequence[float]) -> dict[str, Any]:
    values = np.asarray(confidences, dtype=np.float64)
    if values.ndim != 1 or not values.size or not np.isfinite(values).all():
        raise ValueError("Validation confidences must be a non-empty finite sequence.")
    if np.any((values < 0) | (values > 1)):
        raise ValueError("Validation confidences must be probabilities from 0 to 1.")

    buckets = (
        ("below_70_percent", values < CONFIDENCE_THRESHOLD),
        ("70_to_below_80_percent", (values >= 0.70) & (values < 0.80)),
        ("80_to_below_90_percent", (values >= 0.80) & (values < 0.90)),
        ("90_percent_or_higher", values >= 0.90),
    )
    return {
        "threshold_percent": CONFIDENCE_THRESHOLD * 100,
        "below_threshold_count": int(np.count_nonzero(values < CONFIDENCE_THRESHOLD)),
        "below_threshold_fraction": float(
            np.count_nonzero(values < CONFIDENCE_THRESHOLD) / len(values)
        ),
        "mean_confidence": float(values.mean()),
        "buckets": {
            name: {
                "count": int(np.count_nonzero(mask)),
                "fraction": float(np.count_nonzero(mask) / len(values)),
            }
            for name, mask in buckets
        },
    }


def _validation_duplicate_indexes(
    train_paths: Sequence[str], validation_paths: Sequence[str]
) -> list[int]:
    """Return validation indexes whose exact file content occurs in train/."""

    def digest(path: str) -> bytes:
        hasher = hashlib.sha256()
        with Path(path).open("rb") as file:
            while chunk := file.read(1024 * 1024):
                hasher.update(chunk)
        return hasher.digest()

    training_hashes = {digest(path) for path in train_paths}
    return [
        index
        for index, path in enumerate(validation_paths)
        if digest(path) in training_hashes
    ]


def main() -> None:
    import torch
    import torch.nn as nn
    from torch.utils.data import DataLoader
    from torchvision import datasets, models, transforms

    args = _arguments()
    if args.epochs < 1 or args.batch_size < 1 or args.workers < 0:
        raise SystemExit("epochs/batch-size must be positive and workers nonnegative.")
    if args.patience < 0:
        raise SystemExit("patience must be nonnegative.")

    train_dir = args.dataset_root / "train"
    validation_dir = args.dataset_root / "val"
    if not validation_dir.is_dir():
        raise SystemExit(
            "Expected separate PlantVillage splits at "
            f"{train_dir} and {validation_dir}."
        )
    if not train_dir.is_dir():
        raise SystemExit(f"PlantVillage training folder does not exist: {train_dir}")

    train_transform = transforms.Compose(
        [
            transforms.Resize((256, 256)),
            transforms.RandomHorizontalFlip(),
            transforms.RandomRotation(10),
            transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.2),
            transforms.RandomGrayscale(p=0.1),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        ]
    )
    validation_transform = transforms.Compose(
        [
            transforms.Resize((256, 256)),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        ]
    )
    train_images = datasets.ImageFolder(train_dir, transform=train_transform)
    validation_images = datasets.ImageFolder(
        validation_dir, transform=validation_transform
    )
    _filter_target_classes(train_images)
    _filter_target_classes(validation_images)
    if len(train_images.classes) < 2:
        raise SystemExit("At least two supported crop class folders are required.")
    if not any(name.startswith("Corn_(maize)___") for name in train_images.classes):
        raise SystemExit("No Corn_(maize) classes were found in the training split.")
    if not any(name.startswith("Potato___") for name in train_images.classes):
        raise SystemExit("No Potato classes were found in the training split.")
    if not any(name.startswith("Tomato___") for name in train_images.classes):
        raise SystemExit("No Tomato classes were found in the training split.")
    if OOD_CLASS_NAME not in train_images.classes:
        raise SystemExit(
            "The required Background_or_Invalid class is missing. Add labeled "
            "non-leaf/background images under both train/ and val/ before training."
        )
    if train_images.classes != validation_images.classes:
        missing_validation = sorted(set(train_images.classes) - set(validation_images.classes))
        extra_validation = sorted(set(validation_images.classes) - set(train_images.classes))
        raise SystemExit(
            "train/ and val/ must contain identical class folders and order. "
            f"Missing from val: {missing_validation}; extra in val: {extra_validation}."
        )
    if not train_images or not validation_images:
        raise SystemExit("Both PlantVillage splits must contain images.")
    train_class_counts = np.bincount(
        np.asarray(train_images.targets, dtype=np.int64),
        minlength=len(train_images.classes),
    )
    validation_class_counts = np.bincount(
        np.asarray(validation_images.targets, dtype=np.int64),
        minlength=len(validation_images.classes),
    )
    empty_training_classes = [
        train_images.classes[index]
        for index, count in enumerate(train_class_counts)
        if count == 0
    ]
    empty_validation_classes = [
        validation_images.classes[index]
        for index, count in enumerate(validation_class_counts)
        if count == 0
    ]
    if empty_training_classes or empty_validation_classes:
        raise SystemExit(
            "Every selected class, including Background_or_Invalid, needs images "
            "in both splits. "
            f"Empty train classes: {empty_training_classes}; "
            f"empty val classes: {empty_validation_classes}."
        )

    validation_samples_before_filter = len(validation_images)
    duplicate_validation_indexes = _validation_duplicate_indexes(
        [path for path, _ in train_images.samples],
        [path for path, _ in validation_images.samples],
    )
    if duplicate_validation_indexes:
        duplicate_indexes = set(duplicate_validation_indexes)
        validation_images.samples = [
            sample
            for index, sample in enumerate(validation_images.samples)
            if index not in duplicate_indexes
        ]
        validation_images.imgs = validation_images.samples
        validation_images.targets = [label for _, label in validation_images.samples]
        print(
            "Excluded "
            f"{len(duplicate_validation_indexes)} exact SHA-256 duplicate(s) "
            "from validation because their content also occurs in train/.",
            flush=True,
        )
    if not validation_images:
        raise SystemExit("Validation split is empty after duplicate filtering.")
    filtered_validation_counts = np.bincount(
        np.asarray(validation_images.targets, dtype=np.int64),
        minlength=len(validation_images.classes),
    )
    if np.any(filtered_validation_counts == 0):
        empty_classes = [
            validation_images.classes[index]
            for index, count in enumerate(filtered_validation_counts)
            if count == 0
        ]
        raise SystemExit(
            "Validation has no examples for selected class(es) after exact "
            f"duplicate filtering: {empty_classes}."
        )

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(args.seed)
    device_name = "cuda" if torch.cuda.is_available() else (
        "mps" if torch.backends.mps.is_available() else "cpu"
    )
    device = torch.device(device_name)
    loader_options = {
        "batch_size": args.batch_size,
        "num_workers": args.workers,
        "pin_memory": device_name == "cuda",
        "persistent_workers": args.workers > 0,
    }
    train_loader = DataLoader(
        train_images,
        shuffle=True,
        generator=torch.Generator().manual_seed(args.seed),
        **loader_options,
    )
    validation_loader = DataLoader(
        validation_images, shuffle=False, **loader_options
    )

    if args.evaluate_only:
        if not args.output.is_file():
            raise SystemExit(f"Checkpoint does not exist: {args.output}")
        checkpoint = torch.load(args.output, map_location="cpu", weights_only=True)
        if (
            not isinstance(checkpoint, dict)
            or checkpoint.get("classes") != train_images.classes
            or checkpoint.get("architecture", "mobilenet_v2") != args.architecture
        ):
            raise SystemExit(
                "Checkpoint architecture or class names do not match the selected "
                "model and filtered train/ folders."
            )
        model = _create_classifier(
            models, nn, args.architecture, len(train_images.classes), pretrained=False
        )
        model.load_state_dict(checkpoint["state_dict"])
        initialization = "existing filtered-class checkpoint"
    else:
        checkpoint_path = args.initial_checkpoint
        if checkpoint_path is None and args.architecture == "mobilenet_v2":
            checkpoint_path = next(
                (
                    candidate
                    for candidate in (
                        args.output,
                        PROJECT_ROOT / "model_daun_plantvillage_full_train.pth",
                        PROJECT_ROOT / "model_daun.pth",
                    )
                    if candidate.is_file()
                ),
                None,
            )
        using_pretrained = checkpoint_path is None and not args.no_pretrained
        model = _create_classifier(
            models,
            nn,
            args.architecture,
            len(train_images.classes),
            pretrained=using_pretrained,
        )
        if checkpoint_path is not None:
            if not checkpoint_path.is_file():
                raise SystemExit(
                    f"Initial checkpoint does not exist: {checkpoint_path}"
                )
            previous_state = torch.load(
                checkpoint_path, map_location="cpu", weights_only=True
            )
            previous_architecture = (
                previous_state.get("architecture", "mobilenet_v2")
                if isinstance(previous_state, dict)
                else None
            )
            if previous_architecture != args.architecture:
                raise SystemExit(
                    "Initial checkpoint architecture does not match "
                    f"{args.architecture}."
                )
            feature_state = _checkpoint_features(previous_state)
            current_state = model.state_dict()
            compatible_features = {
                key: value
                for key, value in feature_state.items()
                if key in current_state and current_state[key].shape == value.shape
            }
            if not compatible_features:
                raise SystemExit(
                    f"No compatible {args.architecture} backbone weights in {checkpoint_path}."
                )
            model.load_state_dict(compatible_features, strict=False)
            initialization = f"backbone from {checkpoint_path}; new crop classifier head"
        else:
            initialization = (
                f"ImageNet {args.architecture}"
                if using_pretrained
                else "random"
                if args.no_pretrained
                else f"ImageNet {args.architecture} (checkpoint unavailable)"
            )
    model.to(device)

    class_counts = train_class_counts
    if np.any(class_counts == 0):
        raise SystemExit("Every class must contain at least one training image.")
    class_weights = 1.0 / np.sqrt(class_counts.astype(np.float32))
    class_weights *= len(class_weights) / class_weights.sum()
    loss_function = nn.CrossEntropyLoss(
        weight=torch.tensor(class_weights, dtype=torch.float32, device=device)
    )

    def evaluate() -> tuple[float, dict[str, Any]]:
        model.eval()
        confusion = np.zeros(
            (len(train_images.classes), len(train_images.classes)), dtype=np.int64
        )
        loss_sum = 0.0
        sample_count = 0
        confidence_values: list[np.ndarray] = []
        with torch.inference_mode():
            for images, labels in validation_loader:
                images = images.to(device)
                labels = labels.to(device)
                logits = model(images)
                loss_sum += float(loss_function(logits, labels).item()) * labels.size(0)
                probabilities = torch.softmax(logits, dim=1)
                confidence_values.append(
                    probabilities.max(dim=1).values.cpu().numpy()
                )
                predictions = logits.argmax(dim=1)
                cells = torch.bincount(
                    labels * len(train_images.classes) + predictions,
                    minlength=len(train_images.classes) ** 2,
                )
                confusion += cells.reshape(confusion.shape).cpu().numpy()
                sample_count += labels.size(0)
        validation_metrics = _metrics(confusion)
        validation_metrics["confidence_threshold_distribution"] = (
            _confidence_distribution(np.concatenate(confidence_values))
        )
        return loss_sum / sample_count, validation_metrics

    history: list[dict[str, Any]] = []
    best_state: dict[str, torch.Tensor] | None = None
    best_f1 = -1.0
    best_epoch = 0
    start_time = time.monotonic()
    if not args.evaluate_only:
        optimizer = torch.optim.AdamW(
            model.parameters(), lr=1e-4, weight_decay=1e-4
        )
        scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
            optimizer, mode="max", factor=0.5, patience=1
        )
        epochs_without_improvement = 0
        for epoch in range(args.epochs):
            epoch_start = time.monotonic()
            model.train()
            train_loss_sum = 0.0
            progress_interval = max(1, len(train_loader) // 10)
            for batch_index, (images, labels) in enumerate(train_loader, start=1):
                images = images.to(device)
                labels = labels.to(device)
                optimizer.zero_grad(set_to_none=True)
                loss = loss_function(model(images), labels)
                loss.backward()
                optimizer.step()
                train_loss_sum += float(loss.item()) * labels.size(0)
                if batch_index % progress_interval == 0 or batch_index == len(train_loader):
                    print(
                        f"Epoch {epoch + 1}/{args.epochs}: "
                        f"training batch {batch_index}/{len(train_loader)}",
                        flush=True,
                    )

            validation_loss, validation_metrics = evaluate()
            score = validation_metrics["f1_macro"]
            scheduler.step(score)
            epoch_report = {
                "epoch": epoch + 1,
                "train_loss": train_loss_sum / len(train_images),
                "validation_loss": validation_loss,
                "validation": validation_metrics,
                "seconds": time.monotonic() - epoch_start,
            }
            history.append(epoch_report)
            print(
                f"Epoch {epoch + 1}/{args.epochs}: "
                f"train_loss={epoch_report['train_loss']:.4f}, "
                f"val_accuracy={validation_metrics['accuracy']:.2%}, "
                f"val_macro_f1={score:.4f}, "
                "val_confidence_below_70="
                f"{validation_metrics['confidence_threshold_distribution']['below_threshold_fraction']:.2%}, "
                f"seconds={epoch_report['seconds']:.1f}",
                flush=True,
            )
            if score > best_f1:
                best_f1 = score
                best_epoch = epoch + 1
                best_state = {
                    key: value.detach().cpu().clone()
                    for key, value in model.state_dict().items()
                }
                if args.save_best_each_epoch:
                    args.output.parent.mkdir(parents=True, exist_ok=True)
                    temporary_checkpoint = args.output.with_name(
                        f".{args.output.name}.tmp"
                    )
                    torch.save(
                        {
                            "state_dict": best_state,
                            "classes": train_images.classes,
                            "architecture": args.architecture,
                        },
                        temporary_checkpoint,
                    )
                    temporary_checkpoint.replace(args.output)
                epochs_without_improvement = 0
            else:
                epochs_without_improvement += 1
                if args.patience and epochs_without_improvement >= args.patience:
                    print("Early stopping: validation macro F1 did not improve.")
                    break
        if best_state is None:
            raise RuntimeError("Training completed without a checkpoint candidate.")
        model.load_state_dict(best_state)

    validation_loss, validation_metrics = evaluate()
    if not args.evaluate_only:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        torch.save(
            {
                "state_dict": model.cpu().state_dict(),
                "classes": train_images.classes,
                "architecture": args.architecture,
            },
            args.output,
        )
    report_path = args.report or args.output.with_suffix(".metrics.json")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "model": (
            "MobileNetV2"
            if args.architecture == "mobilenet_v2"
            else "EfficientNet-B0"
        ),
        "architecture": args.architecture,
        "evaluation_mode": (
            "existing_checkpoint" if args.evaluate_only else "train_and_evaluate"
        ),
        "initialization": initialization,
        "dataset_root": str(args.dataset_root.resolve()),
        "training_split": "train/",
        "validation_split": (
            "val/ (not used for gradient updates; exact SHA-256 duplicates "
            "of train/ excluded)"
        ),
        "training_samples": len(train_images),
        "validation_samples_before_duplicate_filter": validation_samples_before_filter,
        "validation_exact_duplicates_excluded": len(duplicate_validation_indexes),
        "validation_samples": len(validation_images),
        "class_count": len(train_images.classes),
        "ood_class_included": OOD_CLASS_NAME in train_images.classes,
        "classes": [
            {
                "name": class_name,
                "training_samples": int(class_counts[index]),
            }
            for index, class_name in enumerate(train_images.classes)
        ],
        "input_size": [256, 256],
        "device": device_name,
        "training_config": {
            "optimizer": "AdamW",
            "learning_rate": 1e-4,
            "weight_decay": 1e-4,
            "loss": "CrossEntropyLoss weighted by inverse square root of class frequency",
            "selection_metric": "validation macro F1",
            "batch_size": args.batch_size,
            "workers": args.workers,
            "seed": args.seed,
            "early_stopping_patience": args.patience,
            "training_augmentation": [
                "horizontal flip",
                "rotation +/- 10 degrees",
                "brightness/contrast/saturation jitter +/- 20%",
                "random grayscale (p=0.1)",
            ],
        },
        "epochs_requested": 0 if args.evaluate_only else args.epochs,
        "best_epoch": None if args.evaluate_only else best_epoch,
        "training_history": history,
        "evaluation": {
            "loss": validation_loss,
            **validation_metrics,
            "per_class": [
                {
                    **metric,
                    "class": train_images.classes[metric["class"]],
                }
                for metric in validation_metrics["per_class"]
            ],
        },
        "elapsed_seconds": time.monotonic() - start_time,
        "checkpoint": str(args.output.resolve()),
    }
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(
        f"Evaluated {len(validation_images)} validation images across "
        f"{len(train_images.classes)} classes: "
        f"accuracy={validation_metrics['accuracy']:.2%}, "
        f"macro_f1={validation_metrics['f1_macro']:.4f}.",
        flush=True,
    )
    if not args.evaluate_only:
        print(f"Saved checkpoint to {args.output}", flush=True)
    print(f"Saved metrics report to {report_path}", flush=True)


if __name__ == "__main__":
    main()
