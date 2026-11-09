"""Compact, deterministic JSON summaries for optional LLM narration."""

from __future__ import annotations

import json
from typing import Any


def build_compact_ai_context(record: dict[str, Any]) -> str:
    numeric = record.get("numeric_features") or {}
    ann = record.get("ann_prediction")
    compact = {
        "g": round(float(record["green_ratio"]), 1),
        "d": round(float(record["yellow_ratio"]), 1),
        "p": str(record.get("plant_name", ""))[:24],
        "x": str(record.get("disease_name", record["prediction"]))[:32],
        "c": round(float(record["confidence"]), 1),
        "h": round(float(record["health_score"]), 1),
        "s": str(record["severity"])[:32],
        "a": ann[0].get("label") if isinstance(ann, list) and ann else None,
        "v": [
            round(float(numeric[key]), 1)
            for key in ("mean_hue", "mean_saturation", "mean_value")
            if key in numeric
        ],
    }
    return json.dumps(compact, separators=(",", ":"), ensure_ascii=False)
