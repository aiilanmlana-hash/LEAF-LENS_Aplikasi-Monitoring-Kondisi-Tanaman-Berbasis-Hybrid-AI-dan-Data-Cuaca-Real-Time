"""FastAPI service for LEAF LENS plant condition monitoring."""

from __future__ import annotations

import base64
import csv
import io
import logging
import math
import os
import re
import sqlite3
import threading
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Any, Optional

import cv2
import numpy as np
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from PIL import Image, UnidentifiedImageError
from starlette.concurrency import run_in_threadpool

from backend.auth import verified_user
from backend.care_recommendations import recommend_care
from backend.compact_context import build_compact_ai_context
from backend.fuzzy_logic import sugeno_health_score
from backend.numeric_ann import NumericFeatureANN
from backend.segmentation import numeric_image_features, segment_leaf
from backend.weather import resolve_weather

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "outputsApp"
MASK_DIR = DATA_DIR / "masks"
DATABASE_PATH = DATA_DIR / "monitoring_api.sqlite3"
CSV_PATH = DATA_DIR / "monitoring_api.csv"
MODEL_PATH = Path(
    os.getenv(
        "PLANT_MODEL_PATH",
        str(PROJECT_ROOT / "backend" / "model_daun_plantvillage_full_train.pth"),
    )
)
FALLBACK_MODEL_PATHS = (
    PROJECT_ROOT / "model_daun_plantvillage_full_train.pth",
    PROJECT_ROOT / "model_daun.pth",
)
CLASS_DIR = PROJECT_ROOT / "PlantVillage" / "train"
NUMERIC_ANN_PATH = PROJECT_ROOT / "backend" / "numeric_ann_weights.json"
SUPPORTED_CLASS_PREFIXES = (
    "Corn_(maize)___",
    "Potato___",
    "Tomato___",
)
OOD_CLASS_NAME = "Background_or_Invalid"
OOD_CONFIDENCE_THRESHOLD = 0.70
OOD_MESSAGE = (
    "Objek tidak terverifikasi sebagai daun tanaman hidup. "
    "Pastikan posisi daun tanaman asli berada di dalam bingkai dengan pencahayaan terang."
)
UNSUPPORTED_PLANT_MESSAGE = (
    "Gambar terdeteksi sebagai daun, namun bukan dari jenis Jagung, Kentang, "
    "atau Tomat yang didukung oleh sistem."
)
LOW_CONFIDENCE_MESSAGE = (
    f"Keyakinan model belum mencapai {OOD_CONFIDENCE_THRESHOLD:.0%}. "
    "Pastikan posisi daun terlihat jelas dan pencahayaan cukup, lalu coba lagi."
)
MAX_IMAGE_BYTES = 10 * 1024 * 1024
MAX_IMAGE_PIXELS = 25_000_000
CSV_FIELDS = (
    "id",
    "user_id",
    "timestamp",
    "plant_id",
    "location",
    "green_ratio",
    "yellow_ratio",
    "prediction",
    "confidence",
    "health_score",
    "severity",
    "mask_path",
)

_model_lock = threading.Lock()
_storage_lock = threading.Lock()
_model_bundle: tuple[Any, list[str], Any, Any] | None = None
_numeric_ann: tuple[str, NumericFeatureANN] | None = None
_numeric_ann_lock = threading.Lock()
_logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    MASK_DIR.mkdir(parents=True, exist_ok=True)
    initialize_database()
    # Load the checkpoint while the local server starts instead of making the
    # first person who presses "Analisis daun" wait for model deserialization.
    # Keep the API available with a clear 503 response if assets are missing.
    try:
        await run_in_threadpool(_model_resources)
        _logger.info("MobileNetV2 model preloaded.")
    except HTTPException as error:
        _logger.warning("MobileNetV2 preload skipped: %s", error.detail)
    yield


app = FastAPI(
    title="LEAF LENS - Monitoring Kondisi Tanaman",
    version="1.2.0",
    description="Authenticated Corn/Potato/Tomato leaf analysis with OOD rejection, weather-aware fuzzy scoring, and optional numeric ANN.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in os.getenv(
            "PLANT_ALLOWED_ORIGINS",
            "http://localhost:5000,http://127.0.0.1:5000,"
            "http://localhost:8080,http://127.0.0.1:8080",
        ).split(",")
        if origin.strip()
    ],
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


def initialize_database() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS monitoring_records (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL DEFAULT 'legacy',
                timestamp TEXT NOT NULL,
                plant_id TEXT NOT NULL,
                location TEXT NOT NULL,
                green_ratio REAL NOT NULL,
                yellow_ratio REAL NOT NULL,
                prediction TEXT NOT NULL,
                confidence REAL NOT NULL,
                health_score REAL NOT NULL,
                severity TEXT NOT NULL,
                mask_path TEXT NOT NULL
            )
            """
        )
        columns = {
            row[1] for row in connection.execute("PRAGMA table_info(monitoring_records)")
        }
        # Preserve pre-authentication local records while ensuring new rows are
        # always associated with the Firebase user that made the request.
        if "user_id" not in columns:
            connection.execute(
                "ALTER TABLE monitoring_records ADD COLUMN user_id TEXT NOT NULL DEFAULT 'legacy'"
            )


def _model_resources() -> tuple[Any, list[str], Any, Any]:
    global _model_bundle
    with _model_lock:
        if _model_bundle is not None:
            return _model_bundle
        model_path = MODEL_PATH
        if not model_path.is_file() and "PLANT_MODEL_PATH" not in os.environ:
            model_path = next(
                (path for path in FALLBACK_MODEL_PATHS if path.is_file()),
                MODEL_PATH,
            )
        if not model_path.is_file() or not CLASS_DIR.is_dir():
            _logger.error(
                "Model assets are unavailable: model=%s classes_dir=%s",
                model_path,
                CLASS_DIR,
            )
            raise HTTPException(
                status_code=503,
                detail="Layanan analisis gambar sedang tidak tersedia. Silakan coba lagi nanti.",
            )
        class_names = sorted(
            path.name
            for path in CLASS_DIR.iterdir()
            if path.is_dir()
            and (
                path.name == OOD_CLASS_NAME
                or path.name.startswith(SUPPORTED_CLASS_PREFIXES)
            )
        )
        if not class_names:
            _logger.error("No supported PlantVillage class directories were found")
            raise HTTPException(
                status_code=503,
                detail="Layanan analisis gambar sedang tidak tersedia. Silakan coba lagi nanti.",
            )

        try:
            import torch
            import torch.nn as nn
            from torchvision import models, transforms

            model = models.mobilenet_v2(weights=None)
            model.classifier[1] = nn.Linear(model.last_channel, len(class_names))
            checkpoint = torch.load(model_path, map_location="cpu", weights_only=True)
            if not isinstance(checkpoint, dict):
                raise ValueError("Model checkpoint format is invalid")
            checkpoint_names = checkpoint.get("classes")
            state_dict = checkpoint.get("state_dict", checkpoint)
            if checkpoint_names is None:
                raise ValueError("Model checkpoint has no class-name metadata")
            if checkpoint_names != class_names:
                raise ValueError("Model checkpoint classes do not match dataset folders")
            checkpoint_classes = state_dict.get("classifier.1.weight")
            if (
                checkpoint_classes is None
                or checkpoint_classes.shape[0] != len(class_names)
            ):
                output_count = (
                    checkpoint_classes.shape[0]
                    if checkpoint_classes is not None
                    else "unknown"
                )
                raise ValueError(
                    f"Checkpoint has {output_count} classes; dataset has {len(class_names)}"
                )
            model.load_state_dict(state_dict)
            model.eval()
        except (ImportError, OSError, RuntimeError, ValueError) as error:
            _logger.exception("Could not load the MobileNetV2 model")
            raise HTTPException(
                status_code=503,
                detail="Layanan analisis gambar sedang tidak tersedia. Silakan coba lagi nanti.",
            ) from error

        transform = transforms.Compose(
            [
                transforms.Resize((256, 256)),
                transforms.ToTensor(),
                transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
            ]
        )
        _model_bundle = (model, class_names, transform, torch)
        return _model_bundle


def fuzzy_health_score(green_ratio: float, yellow_ratio: float) -> tuple[float, str]:
    """Compatibility wrapper for the zero-order Sugeno health model."""
    return sugeno_health_score(green_ratio, yellow_ratio)


def _validate_prediction(prediction: str, confidence_percent: float) -> None:
    """Reject OOD classes and confidence below the softmax probability threshold."""
    rejection_reason = ""
    message = OOD_MESSAGE
    if prediction == OOD_CLASS_NAME:
        rejection_reason = f"the reserved OOD class {OOD_CLASS_NAME!r} was predicted"
    elif not prediction.startswith(SUPPORTED_CLASS_PREFIXES):
        rejection_reason = f"predicted class {prediction!r} is outside supported crops"
        plant, separator, _ = prediction.partition("___")
        if separator and plant != OOD_CLASS_NAME:
            message = UNSUPPORTED_PLANT_MESSAGE
    elif not math.isfinite(confidence_percent) or (
        confidence_percent / 100 < OOD_CONFIDENCE_THRESHOLD
    ):
        message = LOW_CONFIDENCE_MESSAGE
        rejection_reason = (
            f"confidence is not finite ({confidence_percent!r})"
            if not math.isfinite(confidence_percent)
            else (
                f"MobileNetV2 confidence {confidence_percent:.2f}% is below the "
                f"{OOD_CONFIDENCE_THRESHOLD:.2%} threshold for class {prediction!r}"
            )
        )
    else:
        return

    _logger.warning(
        "OOD rejection: %s | Top Prediction: %s with %.2f%% confidence",
        rejection_reason,
        prediction,
        confidence_percent,
    )
    raise HTTPException(
        status_code=422,
        detail={
            "status": "error",
            "code": "ood_image",
            "message": message,
        },
    )


def _decode_image(image_bytes: bytes) -> np.ndarray:
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Image file is empty.")
    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image exceeds the 10 MB upload limit.")
    try:
        with Image.open(io.BytesIO(image_bytes)) as image:
            image.verify()
        with Image.open(io.BytesIO(image_bytes)) as image:
            if image.width * image.height > MAX_IMAGE_PIXELS:
                raise HTTPException(status_code=413, detail="Image dimensions exceed the supported pixel limit.")
            image = image.convert("RGB")
            image_rgb = np.asarray(image)
    except (UnidentifiedImageError, OSError, ValueError) as error:
        raise HTTPException(status_code=400, detail="Upload must be a valid JPEG, PNG, or WebP image.") from error
    return cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR)


def _classify(image_bgr: np.ndarray) -> tuple[str, float]:
    model, class_names, transform, torch = _model_resources()
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    tensor = transform(Image.fromarray(image_rgb)).unsqueeze(0)
    try:
        with torch.inference_mode():
            probabilities = torch.nn.functional.softmax(model(tensor)[0], dim=0)
        confidence, index = torch.max(probabilities, dim=0)
    except (RuntimeError, ValueError) as error:
        _logger.exception("MobileNetV2 inference failed")
        raise HTTPException(
            status_code=503,
            detail="Layanan analisis gambar sedang tidak tersedia. Silakan coba lagi nanti.",
        ) from error
    prediction = class_names[index.item()]
    raw_confidence = float(confidence.item())
    _logger.info(
        "MobileNetV2 prediction: class=%s confidence=%.6f (%.4f%%)",
        prediction,
        raw_confidence,
        raw_confidence * 100,
    )
    return prediction, raw_confidence * 100


def _plant_village_details(class_name: str) -> tuple[str, str, bool]:
    plant, separator, disease = class_name.partition("___")
    if not separator:
        plant, disease = "Tanaman", class_name
    plant_name = plant.replace("_", " ").strip()
    disease_name = disease.replace("_", " ").strip()
    is_healthy = re.search(r"\bhealthy\b", disease_name, re.IGNORECASE) is not None
    return plant_name, disease_name, is_healthy


_segment = segment_leaf


def _numeric_ann_model() -> tuple[NumericFeatureANN | None, str | None]:
    global _numeric_ann
    checkpoint = os.getenv("PLANT_NUMERIC_ANN_WEIGHTS", "").strip()
    checkpoint = checkpoint or str(NUMERIC_ANN_PATH)
    if not Path(checkpoint).is_file():
        return None, "Analisis kesehatan lanjutan belum tersedia."
    with _numeric_ann_lock:
        if _numeric_ann is not None and _numeric_ann[0] == checkpoint:
            return _numeric_ann[1], None
        try:
            model = NumericFeatureANN.load(checkpoint)
        except (OSError, ValueError, KeyError, TypeError) as error:
            _logger.exception("Could not load numeric ANN checkpoint")
            return None, "Analisis kesehatan lanjutan belum tersedia."
        _numeric_ann = (checkpoint, model)
        return model, None


def _safe_plant_id(plant_id: str) -> str:
    normalized = plant_id.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", normalized):
        raise HTTPException(
            status_code=422,
            detail="plant_id must be 1-40 characters using letters, numbers, '_' or '-'.",
        )
    return normalized


def _save_record(record: dict[str, Any], mask_bytes: bytes) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    MASK_DIR.mkdir(parents=True, exist_ok=True)
    mask_file = MASK_DIR / record["mask_path"]
    with _storage_lock:
        try:
            mask_file.write_bytes(mask_bytes)
            with sqlite3.connect(DATABASE_PATH) as connection:
                connection.execute(
                    """
                    INSERT INTO monitoring_records
                    (id, timestamp, plant_id, location, green_ratio, yellow_ratio, prediction,
                     confidence, health_score, severity, mask_path)
                    VALUES (:id, :timestamp, :plant_id, :location, :green_ratio, :yellow_ratio,
                            :prediction, :confidence, :health_score, :severity, :mask_path)
                    """,
                    record,
                )
            with CSV_PATH.open("a", newline="", encoding="utf-8-sig") as file:
                writer = csv.DictWriter(file, fieldnames=CSV_FIELDS)
                if file.tell() == 0:
                    writer.writeheader()
                writer.writerow({field: record[field] for field in CSV_FIELDS})
        except (OSError, sqlite3.Error, csv.Error):
            mask_file.unlink(missing_ok=True)
            raise


def _analyze(
    image_bytes: bytes,
    user_id: str,
    plant_id: str,
    location: str,
    flip_horizontal: bool,
    hue_min: int,
    hue_max: int,
    saturation_min: int,
    value_min: int,
    kernel_size: int,
    latitude: float | None = None,
    longitude: float | None = None,
) -> dict[str, Any]:
    image_bgr = _decode_image(image_bytes)
    if flip_horizontal:
        image_bgr = cv2.flip(image_bgr, 1)

    prediction, confidence = _classify(image_bgr)
    print(f"Hasil Prediksi: {prediction}, Confidence: {confidence}", flush=True)
    _validate_prediction(prediction, confidence)

    # The ratios from segmentation feed fuzzy scoring and the optional ANN.
    green_ratio, yellow_ratio, mask_bytes = _segment(
        image_bgr, hue_min, hue_max, saturation_min, value_min, kernel_size
    )
    _logger.info(
        "HSV/K-Means segmentation results (not OOD validation): "
        "green=%.2f%% dry=%.2f%%",
        green_ratio,
        yellow_ratio,
    )
    plant_name, disease_name, is_healthy = _plant_village_details(prediction)
    weather, weather_error = resolve_weather(latitude, longitude)
    health_score, severity = sugeno_health_score(
        green_ratio,
        yellow_ratio,
        temperature_c=weather["temperature_c"] if weather else None,
        humidity_pct=weather["humidity_pct"] if weather else None,
        precipitation_mm=weather["precipitation_mm"] if weather else None,
        disease_name=disease_name,
    )
    image_features = numeric_image_features(image_bgr)
    numeric_features = [
        green_ratio,
        yellow_ratio,
        confidence,
        health_score,
        image_features["mean_hue"],
        image_features["mean_saturation"],
        image_features["mean_value"],
    ]
    ann_model, ann_error = _numeric_ann_model()
    ann_result = None
    # No ANN prediction is claimed unless a trained checkpoint was configured.
    if ann_model is not None and weather is None:
        ann_error = "Tambahkan lokasi untuk melengkapi analisis kesehatan."
    elif ann_model is not None and ann_model.input_size != 10:
        ann_error = "Analisis kesehatan lanjutan belum tersedia."
    elif ann_model is not None and weather is not None:
        numeric_features.extend(
            [
                weather["temperature_c"],
                weather["humidity_pct"],
                weather["precipitation_mm"],
            ]
        )
        try:
            ann_result = ann_model.predict(np.asarray(numeric_features))[0]
        except (ValueError, RuntimeError) as error:
            _logger.exception("Numeric ANN inference failed")
            ann_error = "Analisis kesehatan lanjutan belum tersedia."
    record_id = str(uuid.uuid4())
    mask_filename = f"{plant_id}_{record_id[:8]}_mask.png"
    record = {
        "id": record_id,
        "user_id": user_id,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "plant_id": plant_id,
        "location": location,
        "green_ratio": green_ratio,
        "yellow_ratio": yellow_ratio,
        "prediction": f"{plant_name} - {disease_name}",
        "class_name": prediction,
        "plant_name": plant_name,
        "disease_name": disease_name,
        "is_healthy": is_healthy,
        "healthy_area_pct": green_ratio,
        "affected_area_pct": yellow_ratio,
        "confidence": confidence,
        "health_score": health_score,
        "severity": severity,
        "weather": weather,
        "weather_error": weather_error,
        "mask_path": mask_filename,
        "ann_prediction": ann_result,
        "numeric_features": {
            "green_ratio": green_ratio,
            "dry_ratio": yellow_ratio,
            "mobilenet_confidence": confidence,
            "fuzzy_health_score": health_score,
            **image_features,
            **(
                {
                    "temperature_c": weather["temperature_c"],
                    "humidity_pct": weather["humidity_pct"],
                    "precipitation_mm": weather["precipitation_mm"],
                }
                if weather
                else {}
            ),
        },
        "ann_error": ann_error,
    }
    record["care_recommendation"] = recommend_care(
        plant_name=plant_name,
        disease_name=disease_name,
        is_healthy=is_healthy,
        confidence=confidence,
        health_score=health_score,
        dry_ratio=yellow_ratio,
        temperature_c=weather["temperature_c"] if weather else None,
        humidity_pct=weather["humidity_pct"] if weather else None,
        precipitation_mm=weather["precipitation_mm"] if weather else None,
    )
    _save_record(record, mask_bytes)
    ai_context_json = build_compact_ai_context(record)
    return {
        **record,
        "mask_base64": base64.b64encode(mask_bytes).decode("ascii"),
        "ai_context_json": ai_context_json,
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/v1/analyze-plant")
async def analyze_plant(
    image: Annotated[UploadFile, File(description="JPEG, PNG, or WebP plant photo")],
    plant_id: Annotated[str, Form()] = "P001",
    location: Annotated[str, Form()] = "",
    flip_horizontal: Annotated[bool, Form()] = False,
    hue_min: Annotated[int, Form(ge=0, le=179)] = 25,
    hue_max: Annotated[int, Form(ge=0, le=179)] = 95,
    saturation_min: Annotated[int, Form(ge=0, le=255)] = 35,
    value_min: Annotated[int, Form(ge=0, le=255)] = 30,
    kernel_size: Annotated[int, Form(ge=1, le=15)] = 5,
    latitude: Annotated[Optional[float], Form(ge=-90, le=90)] = None,
    longitude: Annotated[Optional[float], Form(ge=-180, le=180)] = None,
    user_id: Annotated[str, Depends(verified_user)] = "",
) -> dict[str, Any]:
    normalized_id = _safe_plant_id(plant_id)
    normalized_location = location.strip()
    if len(normalized_location) > 160:
        raise HTTPException(status_code=422, detail="location must be at most 160 characters.")
    if hue_min > hue_max:
        raise HTTPException(status_code=422, detail="hue_min must not exceed hue_max.")
    if kernel_size % 2 == 0:
        raise HTTPException(status_code=422, detail="kernel_size must be odd.")
    if (latitude is None) != (longitude is None):
        raise HTTPException(
            status_code=422,
            detail="latitude and longitude must be provided together.",
        )
    image_bytes = await image.read(MAX_IMAGE_BYTES + 1)
    return await run_in_threadpool(
        _analyze,
        image_bytes,
        user_id,
        normalized_id,
        normalized_location,
        flip_horizontal,
        hue_min,
        hue_max,
        saturation_min,
        value_min,
        kernel_size,
        latitude,
        longitude,
    )


@app.get("/api/v1/history")
def history(
    user_id: Annotated[str, Depends(verified_user)], limit: int = 100
) -> list[dict[str, Any]]:
    if not 1 <= limit <= 500:
        raise HTTPException(status_code=422, detail="limit must be between 1 and 500.")
    initialize_database()
    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(
            "SELECT * FROM monitoring_records WHERE user_id = ? ORDER BY timestamp DESC LIMIT ?",
            (user_id, limit),
        ).fetchall()
    return [dict(row) for row in rows]


@app.get("/api/v1/history/export.csv")
def export_history(user_id: Annotated[str, Depends(verified_user)]) -> StreamingResponse:
    initialize_database()
    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(
            "SELECT * FROM monitoring_records WHERE user_id = ? ORDER BY timestamp DESC",
            (user_id,),
        ).fetchall()
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=CSV_FIELDS)
    writer.writeheader()
    writer.writerows({field: row[field] for field in CSV_FIELDS} for row in rows)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": 'attachment; filename="smart_plant_history.csv"'},
    )
