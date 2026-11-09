"""K-Means-assisted HSV segmentation for green and dry leaf regions.

K-Means groups pixel colors; HSV thresholds decide which groups count as green
or dry. Together they produce area ratios and a three-color PNG mask.
"""

from __future__ import annotations

import threading

import cv2
import numpy as np
from fastapi import HTTPException

_KMEANS_LOCK = threading.Lock()
_MAX_WORKING_EDGE = 640
_MAX_KMEANS_SAMPLES = 20_000
_LABEL_CHUNK_SIZE = 65_536


def _cluster_labels(pixels_lab: np.ndarray, centers: np.ndarray) -> np.ndarray:
    labels = np.empty(pixels_lab.shape[0], dtype=np.uint8)
    centers = centers.astype(np.float32, copy=False)
    for start in range(0, len(pixels_lab), _LABEL_CHUNK_SIZE):
        end = min(start + _LABEL_CHUNK_SIZE, len(pixels_lab))
        chunk = pixels_lab[start:end]
        distances = np.sum(
            (chunk[:, None, :] - centers[None, :, :]) ** 2,
            axis=2,
        )
        labels[start:end] = np.argmin(distances, axis=1)
    return labels


def _remove_small_components(mask: np.ndarray, minimum_area: int) -> np.ndarray:
    component_count, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask, connectivity=8
    )
    if component_count <= 1:
        return mask
    areas = stats[:, cv2.CC_STAT_AREA]
    keep = areas >= minimum_area
    keep[0] = False
    return (keep[labels].astype(np.uint8) * 255)


def segment_leaf(
    image_bgr: np.ndarray,
    hue_min: int,
    hue_max: int,
    saturation_min: int,
    value_min: int,
    kernel_size: int,
) -> tuple[float, float, bytes]:
    if image_bgr.ndim != 3 or image_bgr.shape[2] != 3 or image_bgr.size == 0:
        raise HTTPException(status_code=422, detail="Expected a non-empty BGR image.")
    if hue_min > hue_max or kernel_size < 1 or kernel_size % 2 == 0:
        raise HTTPException(status_code=422, detail="Invalid HSV or morphology parameters.")

    height, width = image_bgr.shape[:2]
    scale = min(1.0, _MAX_WORKING_EDGE / max(height, width))
    working = cv2.resize(
        image_bgr,
        (max(1, round(width * scale)), max(1, round(height * scale))),
        interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_LINEAR,
    )
    hsv = cv2.cvtColor(working, cv2.COLOR_BGR2HSV)
    lab = cv2.cvtColor(working, cv2.COLOR_BGR2LAB)
    pixels_lab = lab.reshape((-1, 3)).astype(np.float32)
    # Sample colors to keep K-Means bounded even for large uploaded photos.
    sample_stride = max(
        1, (len(pixels_lab) + _MAX_KMEANS_SAMPLES - 1) // _MAX_KMEANS_SAMPLES
    )
    samples = pixels_lab[::sample_stride]
    cluster_count = min(3, len(samples))
    criteria = (
        cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER,
        25,
        0.8,
    )
    with _KMEANS_LOCK:
        cv2.setRNGSeed(7)
        _, _, centers = cv2.kmeans(
            samples,
            cluster_count,
            None,
            criteria,
            2,
            cv2.KMEANS_PP_CENTERS,
        )

    # Map each pixel to its nearest learned color center, in chunks to limit memory.
    center_lab = np.clip(np.rint(centers), 0, 255).astype(np.uint8)
    center_bgr = cv2.cvtColor(
        center_lab.reshape((1, -1, 3)), cv2.COLOR_LAB2BGR
    )
    center_hsv = cv2.cvtColor(center_bgr, cv2.COLOR_BGR2HSV).reshape((-1, 3))
    labels = _cluster_labels(pixels_lab, centers).reshape(working.shape[:2])
    cluster_green = np.zeros(working.shape[:2], dtype=np.uint8)
    cluster_dry = np.zeros(working.shape[:2], dtype=np.uint8)
    for index, (hue, saturation, value) in enumerate(center_hsv):
        cluster = (labels == index).astype(np.uint8) * 255
        # A cluster is eligible only when its representative color meets the
        # relevant HSV thresholds; raw HSV masks below then retain pixel detail.
        if (
            hue_min <= hue <= hue_max
            and saturation >= saturation_min
            and value >= value_min
        ):
            cluster_green = cv2.bitwise_or(cluster_green, cluster)
        if 15 <= hue <= 30 and saturation >= 40 and value >= 40:
            cluster_dry = cv2.bitwise_or(cluster_dry, cluster)

    green_mask = cv2.inRange(
        hsv,
        np.array([hue_min, saturation_min, value_min], dtype=np.uint8),
        np.array([hue_max, 255, 255], dtype=np.uint8),
    )
    dry_mask = cv2.inRange(
        hsv,
        np.array([15, 40, 40], dtype=np.uint8),
        np.array([30, 255, 255], dtype=np.uint8),
    )
    green_mask = cv2.bitwise_and(green_mask, cluster_green)
    dry_mask = cv2.bitwise_and(dry_mask, cluster_dry)
    kernel = np.ones((kernel_size, kernel_size), dtype=np.uint8)
    # Opening removes small noise; closing fills small gaps inside each mask.
    for mask in (green_mask, dry_mask):
        cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, dst=mask)
        cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, dst=mask)

    total_pixels = working.shape[0] * working.shape[1]
    minimum_component_area = max(3, round(total_pixels * 0.00002))
    green_mask = _remove_small_components(green_mask, minimum_component_area)
    dry_mask = _remove_small_components(dry_mask, minimum_component_area)
    green_mask[dry_mask > 0] = 0

    # Ratios use the processed working image; mask values encode black / dry / green.
    green_ratio = cv2.countNonZero(green_mask) * 100.0 / total_pixels
    dry_ratio = cv2.countNonZero(dry_mask) * 100.0 / total_pixels
    combined_mask = np.zeros(working.shape[:2], dtype=np.uint8)
    combined_mask[dry_mask > 0] = 150
    combined_mask[green_mask > 0] = 255
    if scale < 1:
        combined_mask = cv2.resize(
            combined_mask, (width, height), interpolation=cv2.INTER_NEAREST
        )
    success, encoded = cv2.imencode(".png", combined_mask)
    if not success:
        raise HTTPException(
            status_code=500, detail="Could not encode the segmentation mask."
        )
    return round(green_ratio, 2), round(dry_ratio, 2), encoded.tobytes()


def numeric_image_features(image_bgr: np.ndarray) -> dict[str, float]:
    """Extract compact numeric image features used by the optional ANN."""
    resized = cv2.resize(
        image_bgr,
        (min(128, image_bgr.shape[1]), min(128, image_bgr.shape[0])),
        interpolation=cv2.INTER_AREA,
    )
    hsv = cv2.cvtColor(resized, cv2.COLOR_BGR2HSV)
    means = cv2.mean(hsv)
    return {
        "mean_hue": round(float(means[0]), 3),
        "mean_saturation": round(float(means[1]), 3),
        "mean_value": round(float(means[2]), 3),
    }
