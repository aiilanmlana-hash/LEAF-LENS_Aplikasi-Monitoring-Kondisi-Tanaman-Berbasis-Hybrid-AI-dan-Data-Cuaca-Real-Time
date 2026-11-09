"""Bounded zero-order Sugeno rules for leaf health assessment."""

from __future__ import annotations

import math
from typing import Final

import numpy as np

_RULES: Final = (
    ("high", "low", 95.0),
    ("medium", "low", 78.0),
    ("low", "low", 52.0),
    ("high", "medium", 76.0),
    ("medium", "medium", 54.0),
    ("low", "medium", 32.0),
    ("high", "high", 48.0),
    ("medium", "high", 30.0),
    ("low", "high", 12.0),
)


def _left_shoulder(value: float, full_until: float, zero_at: float) -> float:
    if value <= full_until:
        return 1.0
    if value >= zero_at:
        return 0.0
    return (zero_at - value) / (zero_at - full_until)


def _triangle(value: float, left: float, peak: float, right: float) -> float:
    if value <= left or value >= right:
        return float(value == peak)
    if value == peak:
        return 1.0
    if value < peak:
        return (value - left) / (peak - left)
    return (right - value) / (right - peak)


def _right_shoulder(value: float, zero_at: float, full_from: float) -> float:
    if value <= zero_at:
        return 0.0
    if value >= full_from:
        return 1.0
    return (value - zero_at) / (full_from - zero_at)


def sugeno_health_score(
    green_ratio: float,
    dry_ratio: float,
    *,
    temperature_c: float | None = None,
    humidity_pct: float | None = None,
    precipitation_mm: float | None = None,
    disease_name: str | None = None,
    weather_reliability: float = 1.0,
) -> tuple[float, str]:
    """Apply bounded memberships and Sugeno singleton weighted-average rules."""
    if not math.isfinite(green_ratio) or not math.isfinite(dry_ratio):
        raise ValueError("Leaf ratios must be finite numbers.")
    green_ratio = float(np.clip(green_ratio, 0.0, 100.0))
    dry_ratio = float(np.clip(dry_ratio, 0.0, 100.0))
    if green_ratio < 2.0 and dry_ratio < 3.0:
        return 0.0, "Tidak diketahui"

    green = {
        "low": _left_shoulder(green_ratio, 0.0, 20.0),
        "medium": _triangle(green_ratio, 5.0, 30.0, 60.0),
        "high": _right_shoulder(green_ratio, 25.0, 65.0),
    }
    dry = {
        "low": _left_shoulder(dry_ratio, 0.0, 12.0),
        "medium": _triangle(dry_ratio, 3.0, 15.0, 35.0),
        "high": _right_shoulder(dry_ratio, 20.0, 50.0),
    }

    # Each rule fires according to the weaker of its green and dry memberships.
    # Sugeno combines the rule outputs by a weighted average of their strengths.
    weighted_sum = 0.0
    total_weight = 0.0
    for green_level, dry_level, consequent in _RULES:
        strength = min(green[green_level], dry[dry_level])
        weighted_sum += strength * consequent
        total_weight += strength
    if total_weight == 0:
        raise RuntimeError("Sugeno rule base did not cover the supplied leaf ratios.")

    score = weighted_sum / total_weight
    weather_values = (temperature_c, humidity_pct, precipitation_mm)
    if all(value is not None for value in weather_values):
        if not all(math.isfinite(value) for value in weather_values if value is not None):
            raise ValueError("Weather values must be finite numbers.")
        if not math.isfinite(weather_reliability) or not 0 <= weather_reliability <= 1:
            raise ValueError("Weather reliability must be a finite value from 0 to 1.")
        is_blight = "blight" in (disease_name or "").casefold()
        if is_blight:
            # High humidity plus warmth is a disease-risk rule, not a diagnosis.
            humid_membership = _right_shoulder(float(humidity_pct), 75.0, 90.0)
            warm_membership = _right_shoulder(float(temperature_c), 20.0, 30.0)
            rain_membership = _right_shoulder(float(precipitation_mm), 0.0, 10.0)
            combined_risk = max(
                min(humid_membership, warm_membership),
                min(humid_membership, rain_membership),
            )
            score -= 15.0 * combined_risk * weather_reliability

    score = round(float(np.clip(score, 0.0, 100.0)), 1)
    severity = "Sehat" if score >= 75 else "Perlu perhatian" if score >= 50 else "Kritis"
    return score, severity
