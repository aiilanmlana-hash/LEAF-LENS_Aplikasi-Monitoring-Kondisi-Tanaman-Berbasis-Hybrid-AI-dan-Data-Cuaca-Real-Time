"""Merge labeled OOD and PlantDoc images into the PlantVillage train/val tree."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path
from typing import Iterable

PROJECT_ROOT = Path(__file__).resolve().parents[1]
IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png", ".webp"}
TARGET_PREFIXES = ("Corn_(maize)___", "Potato___", "Tomato___")
OOD_CLASS_NAME = "Background_or_Invalid"

# Keep PlantDoc labels disease-specific when a matching PlantVillage class
# exists; generic "Tomato leaf" remains explicitly unspecified, not healthy.
PLANTDOC_CLASS_MAP = {
    "Corn_Gray_leaf_spot": "Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot",
    "Corn_leaf_blight": "Corn_(maize)___Northern_Leaf_Blight",
    "Corn_rust_leaf": "Corn_(maize)___Common_rust_",
    "Potato_leaf_early_blight": "Potato___Early_blight",
    "Potato_leaf_late_blight": "Potato___Late_blight",
    "Tomato_Early_blight_leaf": "Tomato___Early_blight",
    "Tomato_Septoria_leaf_spot": "Tomato___Septoria_leaf_spot",
    "Tomato_leaf": "Tomato___Unspecified_leaf",
    "Tomato_leaf_bacterial_spot": "Tomato___Bacterial_spot",
    "Tomato_leaf_late_blight": "Tomato___Late_blight",
    "Tomato_leaf_mosaic_virus": "Tomato___Tomato_mosaic_virus",
    "Tomato_leaf_yellow_virus": "Tomato___Tomato_Yellow_Leaf_Curl_Virus",
    "Tomato_mold_leaf": "Tomato___Leaf_Mold",
    "Tomato_two_spotted_spider_mites_leaf": (
        "Tomato___Spider_mites Two-spotted_spider_mite"
    ),
}


def _is_supported_class(class_name: str) -> bool:
    return class_name == OOD_CLASS_NAME or class_name.startswith(TARGET_PREFIXES)


def _images(directory: Path) -> Iterable[Path]:
    return sorted(
        path
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    )


def _unique_destination(path: Path, reserved: set[Path]) -> Path:
    candidate = path
    counter = 1
    while candidate.exists() or candidate in reserved:
        candidate = path.with_name(f"{path.stem}__{counter}{path.suffix}")
        counter += 1
    reserved.add(candidate)
    return candidate


def build_plan(source_root: Path, dataset_root: Path) -> tuple[list[tuple[Path, Path]], list[Path]]:
    source_root = source_root.resolve()
    dataset_root = dataset_root.resolve()
    if source_root == dataset_root or source_root in dataset_root.parents or dataset_root in source_root.parents:
        raise ValueError("Source and destination dataset roots must not overlap.")

    background_root = source_root / "Background_or_Invalid"
    background_train = background_root / "training_set"
    background_val = background_root / "test_set"
    plantdoc_root = source_root / "PlantDoc Classification"
    plantdoc_train = plantdoc_root / "train"
    plantdoc_val = plantdoc_root / "test"
    required_directories = (
        background_train,
        background_val,
        plantdoc_train,
        plantdoc_val,
        dataset_root / "train",
        dataset_root / "val",
    )
    missing = [str(path) for path in required_directories if not path.is_dir()]
    if missing:
        raise ValueError(f"Required source or destination folder is missing: {missing}")

    moves: list[tuple[Path, Path]] = []
    reserved: set[Path] = set()
    for split, source in (("train", background_train), ("val", background_val)):
        for image in _images(source):
            relative = image.relative_to(source)
            target = dataset_root / split / OOD_CLASS_NAME / source.name / relative
            moves.append((image, _unique_destination(target, reserved)))

    for split, source_split in (("train", plantdoc_train), ("val", plantdoc_val)):
        class_directories = sorted(path for path in source_split.iterdir() if path.is_dir())
        unknown_classes = [
            path.name for path in class_directories if path.name not in PLANTDOC_CLASS_MAP
        ]
        if unknown_classes:
            raise ValueError(
                f"PlantDoc has unmapped class folders in {source_split}: {unknown_classes}"
            )
        for class_directory in class_directories:
            class_name = PLANTDOC_CLASS_MAP[class_directory.name]
            for image in _images(class_directory):
                target = (
                    dataset_root
                    / split
                    / class_name
                    / "PlantDoc"
                    / class_directory.name
                    / image.name
                )
                moves.append((image, _unique_destination(target, reserved)))

    directories_to_remove = [
        class_directory
        for split in ("train", "val")
        for class_directory in sorted((dataset_root / split).iterdir())
        if class_directory.is_dir() and not _is_supported_class(class_directory.name)
    ]
    return moves, directories_to_remove


def prepare_dataset(source_root: Path, dataset_root: Path, apply: bool = False) -> dict[str, int]:
    moves, directories_to_remove = build_plan(source_root, dataset_root)
    print(f"Images to move: {len(moves)}")
    print(f"Unsupported class folders to remove: {len(directories_to_remove)}")
    for directory in directories_to_remove:
        print(f"  remove {directory}")
    if not apply:
        print("Dry run only. Re-run with --apply to modify the dataset.")
        return {
            "images_to_move": len(moves),
            "class_folders_to_remove": len(directories_to_remove),
        }

    for source, destination in moves:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(destination))
    for directory in directories_to_remove:
        shutil.rmtree(directory)
    print("Dataset preparation completed.")
    return {
        "images_moved": len(moves),
        "class_folders_removed": len(directories_to_remove),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-root",
        type=Path,
        default=PROJECT_ROOT / "DataSet",
        help="Folder containing Background_or_Invalid and PlantDoc Classification.",
    )
    parser.add_argument(
        "--dataset-root",
        type=Path,
        default=PROJECT_ROOT / "PlantVillage",
        help="Destination with train/ and val/ folders.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Move images and remove non-target PlantVillage class folders.",
    )
    args = parser.parse_args()
    try:
        prepare_dataset(args.source_root, args.dataset_root, apply=args.apply)
    except (OSError, ValueError) as error:
        raise SystemExit(f"Dataset preparation failed: {error}") from error


if __name__ == "__main__":
    main()
