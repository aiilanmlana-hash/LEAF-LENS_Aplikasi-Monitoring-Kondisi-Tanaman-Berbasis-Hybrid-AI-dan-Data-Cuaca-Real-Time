"""Current weather lookup with a nearest-station Indonesian climate fallback."""

from __future__ import annotations

import csv
import json
import logging
import math
from datetime import date, datetime
from functools import lru_cache
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

_LOGGER = logging.getLogger(__name__)
_CLIMATE_DIR = Path(__file__).resolve().parent / "climate_data_idn.csv"
_OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
_CURRENT_WEATHER_RISK_WEIGHT = 1.0
_HISTORICAL_WEATHER_RISK_WEIGHT = 0.35


def _read_number(row: dict[str, str], key: str, minimum: float, maximum: float) -> float | None:
    try:
        value = float(row[key])
    except (KeyError, TypeError, ValueError):
        return None
    if not math.isfinite(value) or not minimum <= value <= maximum:
        return None
    return value


def _fetch_open_meteo(latitude: float, longitude: float) -> dict[str, Any]:
    query = urlencode(
        {
            "latitude": latitude,
            "longitude": longitude,
            "current": "temperature_2m,relative_humidity_2m,precipitation",
            "timezone": "auto",
        }
    )
    request = Request(
        f"{_OPEN_METEO_URL}?{query}",
        headers={"User-Agent": "SmartPlantMonitoring/1.0"},
    )
    with urlopen(request, timeout=4) as response:
        payload = json.load(response)
    current = payload["current"]
    temperature = float(current["temperature_2m"])
    humidity = float(current["relative_humidity_2m"])
    precipitation = float(current["precipitation"])
    if (
        not all(math.isfinite(value) for value in (temperature, humidity, precipitation))
        or not -50 <= temperature <= 60
        or not 0 <= humidity <= 100
        or not 0 <= precipitation <= 1000
    ):
        raise ValueError("Open-Meteo returned out-of-range weather values.")
    return {
        "temperature_c": temperature,
        "humidity_pct": humidity,
        "precipitation_mm": precipitation,
        "source": "Open-Meteo",
        "data_quality": "real_time",
        "risk_weight": _CURRENT_WEATHER_RISK_WEIGHT,
        "station_name": None,
        "observation_date": current.get("time"),
    }


def _haversine_km(
    latitude_a: float, longitude_a: float, latitude_b: float, longitude_b: float
) -> float:
    latitude_a, latitude_b = math.radians(latitude_a), math.radians(latitude_b)
    delta_latitude = latitude_b - latitude_a
    delta_longitude = math.radians(longitude_b - longitude_a)
    value = (
        math.sin(delta_latitude / 2) ** 2
        + math.cos(latitude_a)
        * math.cos(latitude_b)
        * math.sin(delta_longitude / 2) ** 2
    )
    return 6371 * 2 * math.asin(math.sqrt(min(1.0, value)))


@lru_cache(maxsize=1)
def _station_monthly_climate() -> tuple[
    dict[str, tuple[str, float, float]],
    dict[tuple[str, int], tuple[float, float, float]],
]:
    station_path = _CLIMATE_DIR / "station_detail.csv"
    climate_path = _CLIMATE_DIR / "climate_data.csv"
    stations: dict[str, tuple[str, float, float]] = {}
    with station_path.open(newline="", encoding="utf-8-sig") as file:
        for row in csv.DictReader(file):
            latitude = _read_number(row, "latitude", -90, 90)
            longitude = _read_number(row, "longitude", -180, 180)
            if latitude is None or longitude is None:
                continue
            station_id = row.get("station_id", "").strip()
            stations[station_id] = (
                row.get("station_name", station_id).strip(),
                latitude,
                longitude,
            )

    totals: dict[tuple[str, int], list[float]] = {}
    counts: dict[tuple[str, int], list[int]] = {}
    with climate_path.open(newline="", encoding="utf-8-sig") as file:
        for row in csv.DictReader(file):
            try:
                month = datetime.strptime(row["date"], "%d-%m-%Y").month
            except (KeyError, ValueError):
                continue
            station_id = row.get("station_id", "").strip()
            if station_id not in stations:
                continue
            key = (station_id, month)
            sums = totals.setdefault(key, [0.0, 0.0, 0.0])
            valid_counts = counts.setdefault(key, [0, 0, 0])
            temperature = _read_number(row, "Tavg", -50, 60)
            if temperature is None:
                minimum = _read_number(row, "Tn", -50, 60)
                maximum = _read_number(row, "Tx", -50, 60)
                if minimum is not None and maximum is not None:
                    temperature = (minimum + maximum) / 2
            humidity = _read_number(row, "RH_avg", 0, 100)
            precipitation = _read_number(row, "RR", 0, 1000)
            for index, value in enumerate((temperature, humidity, precipitation)):
                if value is not None:
                    sums[index] += value
                    valid_counts[index] += 1

    averages = {
        key: tuple(
            sums[index] / counts[key][index] if counts[key][index] else float("nan")
            for index in range(3)
        )
        for key, sums in totals.items()
    }
    return stations, averages


def _historical_weather(
    latitude: float, longitude: float, month: int
) -> dict[str, Any] | None:
    stations, averages = _station_monthly_climate()
    nearest_station = min(
        stations.items(),
        key=lambda item: _haversine_km(
            latitude, longitude, item[1][1], item[1][2]
        ),
        default=None,
    )
    if nearest_station is None:
        return None
    station_id, (station_name, _, _) = nearest_station
    values = averages.get((station_id, month))
    if values is None or not all(math.isfinite(value) for value in values):
        return None
    return {
        "temperature_c": round(values[0], 1),
        "humidity_pct": round(values[1], 1),
        "precipitation_mm": round(values[2], 1),
        "source": "Rata-rata historis BMKG 2010–2020",
        "data_quality": "historical_fallback",
        "risk_weight": _HISTORICAL_WEATHER_RISK_WEIGHT,
        "station_name": station_name,
        "observation_date": f"bulan-{month:02d}",
    }


def resolve_weather(
    latitude: float | None,
    longitude: float | None,
    *,
    today: date | None = None,
) -> tuple[dict[str, Any] | None, str | None]:
    """Fetch current weather, then use the nearest station's monthly history."""
    if latitude is None and longitude is None:
        return None, "Koordinat lokasi belum diisi; data cuaca tidak tersedia."
    if latitude is None or longitude is None:
        raise ValueError("Latitude dan longitude harus diisi berpasangan.")
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise ValueError("Koordinat berada di luar rentang yang valid.")

    try:
        return _fetch_open_meteo(latitude, longitude), None
    except (URLError, TimeoutError, OSError, ValueError, KeyError, TypeError) as error:
        _LOGGER.warning("Open-Meteo lookup failed; trying BMKG history: %s", error)

    try:
        historical = _historical_weather(latitude, longitude, (today or date.today()).month)
    except (OSError, csv.Error, ValueError) as error:
        _LOGGER.exception("Could not read historical climate data")
        return None, f"Data cuaca real-time dan historis tidak tersedia: {error}"
    if historical is None:
        return None, "Data real-time gagal dan stasiun historis terdekat tidak tersedia."
    return historical, None
