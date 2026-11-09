"""Generate a reproducible synthetic CSV for testing the numeric ANN pipeline.

The generated labels are illustrative, not expert-labeled field observations.
Do not use the resulting checkpoint or validation metrics as evidence of
real-world plant-disease accuracy.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np

if __package__:
    from .train_numeric_ann import FEATURE_COLUMNS, LABELS
else:
    from train_numeric_ann import FEATURE_COLUMNS, LABELS


PROFILES = {
    "healthy": {
        "green_ratio": (78.0, 9.0, 45.0, 98.0),
        "dry_ratio": (7.0, 5.0, 0.0, 35.0),
        "fuzzy_health_score": (83.0, 9.0, 55.0, 100.0),
        "mean_hue": (67.0, 16.0, 25.0, 115.0),
        "mean_saturation": (145.0, 35.0, 50.0, 245.0),
        "mean_value": (151.0, 32.0, 55.0, 245.0),
        "temperature_c": (26.0, 5.0, 15.0, 40.0),
        "humidity_pct": (66.0, 15.0, 30.0, 100.0),
        "precipitation_mm": (12.0, 10.0, 0.0, 50.0),
    },
    "dry": {
        "green_ratio": (34.0, 12.0, 5.0, 62.0),
        "dry_ratio": (49.0, 13.0, 20.0, 90.0),
        "fuzzy_health_score": (31.0, 13.0, 0.0, 58.0),
        "mean_hue": (29.0, 12.0, 0.0, 65.0),
        "mean_saturation": (105.0, 32.0, 25.0, 210.0),
        "mean_value": (111.0, 31.0, 25.0, 215.0),
        "temperature_c": (31.0, 4.5, 15.0, 40.0),
        "humidity_pct": (53.0, 15.0, 30.0, 90.0),
        "precipitation_mm": (4.0, 5.0, 0.0, 30.0),
    },
    "infected": {
        "green_ratio": (49.0, 13.0, 10.0, 76.0),
        "dry_ratio": (20.0, 10.0, 3.0, 60.0),
        "fuzzy_health_score": (48.0, 13.0, 18.0, 76.0),
        "mean_hue": (45.0, 21.0, 0.0, 110.0),
        "mean_saturation": (124.0, 38.0, 30.0, 235.0),
        "mean_value": (126.0, 35.0, 30.0, 230.0),
        "temperature_c": (27.0, 5.0, 15.0, 40.0),
        "humidity_pct": (79.0, 13.0, 40.0, 100.0),
        "precipitation_mm": (21.0, 14.0, 0.0, 50.0),
    },
}


def _sample_feature(
    generator: np.random.Generator,
    profile: tuple[float, float, float, float],
) -> float:
    mean, standard_deviation, minimum, maximum = profile
    value = generator.normal(mean, standard_deviation)
    return round(float(np.clip(value, minimum, maximum)), 3)


def generate_rows(row_count: int = 750, seed: int = 17) -> list[dict[str, float | str]]:
    if not 500 <= row_count <= 1000:
        raise ValueError("row_count must be between 500 and 1000.")

    generator = np.random.default_rng(seed)
    labels = np.resize(np.asarray(LABELS), row_count)
    generator.shuffle(labels)
    rows: list[dict[str, float | str]] = []
    for label_value in labels:
        label = str(label_value)
        profile = PROFILES[label]
        row: dict[str, float | str] = {
            column: _sample_feature(generator, profile[column])
            for column in FEATURE_COLUMNS
            if column != "mobilenet_confidence"
        }
        row["green_ratio"] = min(float(row["green_ratio"]), 100.0)
        row["dry_ratio"] = min(
            float(row["dry_ratio"]), 100.0 - float(row["green_ratio"])
        )
        row["mobilenet_confidence"] = round(
            float(generator.uniform(0.70, 1.00)), 3
        )
        row["label"] = label
        rows.append(row)
    return rows


def write_dataset(
    output_path: Path, row_count: int = 750, seed: int = 17
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(
            file, fieldnames=(*FEATURE_COLUMNS, "label"), lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(generate_rows(row_count, seed))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("backend/dataset_numeric.csv"),
        help="Destination CSV path (default: backend/dataset_numeric.csv)",
    )
    parser.add_argument(
        "--rows",
        type=int,
        default=750,
        help="Number of synthetic observations (500-1000; default: 750)",
    )
    parser.add_argument("--seed", type=int, default=17)
    args = parser.parse_args()
    try:
        write_dataset(args.output, args.rows, args.seed)
    except ValueError as error:
        parser.error(str(error))
    print(f"Wrote {args.rows} synthetic observations to {args.output}")


if __name__ == "__main__":
    main()
