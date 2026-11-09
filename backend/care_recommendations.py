"""Structured, cautious follow-up guidance for supported crop leaf classes."""

from __future__ import annotations

from typing import Any

_DISCLAIMER = (
    "Hasil foto adalah skrining awal, bukan diagnosis laboratorium atau resep "
    "pestisida. Bahan aktif hanya contoh untuk dikonfirmasi; gunakan hanya "
    "produk yang terdaftar untuk tanaman dan penyakit tersebut, ikuti label "
    "dan APD, serta konsultasikan dengan penyuluh setempat."
)
_SUPPORTED_PLANTS = {
    "corn",
    "corn (maize)",
    "jagung",
    "potato",
    "kentang",
    "tomato",
    "tomat",
}


def _advice(
    priority: str,
    summary: str,
    emergency_actions: list[str],
    organic: list[str],
    chemical: list[str],
    untreated_impact: str,
    decision_tree_node: str = "monitor",
) -> dict[str, Any]:
    return {
        "priority": priority,
        "decision_tree_node": decision_tree_node,
        "summary": summary,
        "emergency_actions": emergency_actions,
        "organic_recommendations": organic,
        "chemical_recommendations": chemical,
        "untreated_impact": untreated_impact,
        "disclaimer": _DISCLAIMER,
        # Keep the older response key for clients that display generic actions.
        "actions": emergency_actions,
    }


def _risk_level(score: float) -> str:
    if score >= 70:
        return "Tinggi"
    if score >= 35:
        return "Sedang"
    return "Rendah"


def _weather_risk(
    temperature_c: float | None,
    humidity_pct: float | None,
    precipitation_mm: float | None,
) -> tuple[float | None, str, str]:
    if temperature_c is None and humidity_pct is None and precipitation_mm is None:
        return None, "Tidak tersedia", "Data cuaca tidak tersedia."

    risk_components = []
    if humidity_pct is not None:
        risk_components.append(max(0.0, min(100.0, (humidity_pct - 65.0) / 25.0 * 100)))
        if humidity_pct >= 75 and temperature_c is not None:
            risk_components.append(
                max(0.0, min(100.0, (temperature_c - 20.0) / 10.0 * 100))
            )
    if precipitation_mm is not None:
        risk_components.append(max(0.0, min(100.0, precipitation_mm / 15.0 * 100)))
    score = max(risk_components, default=0.0)
    level = _risk_level(score)

    conditions = []
    if humidity_pct is not None:
        conditions.append(f"kelembapan {humidity_pct:.0f}%")
    if temperature_c is not None:
        conditions.append(f"suhu {temperature_c:.1f} °C")
    if precipitation_mm is not None:
        conditions.append(f"hujan {precipitation_mm:.1f} mm")
    return score, level, f"Risiko {level} — {', '.join(conditions)}."


def _verification_advice(reason: str) -> dict[str, Any]:
    return _advice(
        "Perlu verifikasi",
        reason,
        [
            "Ambil ulang foto satu daun dengan fokus tajam dan cahaya merata.",
            "Periksa sisi atas/bawah beberapa daun serta kondisi batang dan tanah.",
            "Jangan menyemprot atau mencabut tanaman sebelum identifikasi dikonfirmasi.",
        ],
        ["Utamakan sanitasi alat dan pemantauan; belum ada perlakuan hayati spesifik."],
        ["Belum ada bahan aktif yang direkomendasikan sebelum diagnosis dikonfirmasi."],
        "Jika penyebabnya penyakit menular, penundaan konfirmasi dapat memberi waktu gejala menyebar.",
        decision_tree_node="verification_required",
    )


def recommend_care(
    *,
    plant_name: str,
    disease_name: str,
    is_healthy: bool,
    confidence: float,
    health_score: float,
    dry_ratio: float,
    class_name: str | None = None,
    green_ratio: float = 0.0,
    temperature_c: float | None = None,
    humidity_pct: float | None = None,
    precipitation_mm: float | None = None,
    severity: str | None = None,
) -> dict[str, Any]:
    """Apply a deterministic decision tree before returning cautious crop advice."""
    plant = plant_name.casefold().strip()
    disease = disease_name.casefold().replace("_", " ")
    classification = (class_name or f"{plant_name}___{disease_name}").casefold()

    def with_metrics(advice: dict[str, Any]) -> dict[str, Any]:
        leaf_risk_score = max(0.0, min(100.0, 100.0 - health_score))
        weather_risk_score, weather_risk_level, weather_summary = _weather_risk(
            temperature_c, humidity_pct, precipitation_mm
        )
        priority_level = {
            "Rutin": "Rendah",
            "Pantau": "Rendah",
            "Sedang": "Sedang",
            "Tinggi": "Tinggi",
            "Sangat tinggi": "Tinggi",
            "Perlu verifikasi": "Perlu verifikasi",
        }.get(advice["priority"], "Sedang")
        advice["analysis_metrics"] = {
            "priority_level": priority_level,
            "severity": severity or ("Sehat" if health_score >= 70 else "Perlu perhatian"),
            "fuzzy_health_score": round(health_score, 1),
            "leaf_risk_score": round(leaf_risk_score, 1),
            "leaf_risk_level": _risk_level(leaf_risk_score),
            "weather_risk_score": weather_risk_score,
            "weather_risk_level": weather_risk_level,
            "weather_summary": weather_summary,
            "weather_risk_method": (
                "Indeks heuristik 0–100: RH 65–90%, suhu 20–30 °C saat RH ≥75%, "
                "dan hujan 0–15 mm; bukan probabilitas penyakit."
            ),
            "green_area_pct": round(max(0.0, min(100.0, green_ratio)), 2),
            "affected_area_pct": round(max(0.0, min(100.0, dry_ratio)), 2),
            "temperature_c": temperature_c,
            "humidity_pct": humidity_pct,
            "precipitation_mm": precipitation_mm,
        }
        return advice

    if confidence < 70:
        return with_metrics(
            _verification_advice(
                "Keyakinan model rendah; hasil penyakit tidak cukup kuat untuk menentukan perlakuan."
            )
        )
    if plant not in _SUPPORTED_PLANTS:
        return with_metrics(
            _verification_advice(
                "Tanaman berada di luar cakupan rekomendasi Corn, Potato, dan Tomato."
            )
        )
    if green_ratio < 2 and dry_ratio < 3:
        return with_metrics(
            _verification_advice(
                "Area daun yang terukur terlalu kecil; ambil foto ulang sebelum menentukan tindakan."
            )
        )

    is_virus = any(
        term in f"{classification} {disease}"
        for term in ("virus", "mosaic", "yellow leaf curl")
    )
    is_bacterial = any(term in disease for term in ("bacterial", "bacteria"))
    is_blight = "blight" in f"{classification} {disease}"
    is_spider_mite = "spider mite" in f"{classification} {disease}"
    high_blight_weather = (
        is_blight
        and humidity_pct is not None
        and humidity_pct >= 85
        and temperature_c is not None
        and temperature_c >= 22
    )

    if health_score < 40 or dry_ratio >= 35:
        decision_tree_node = "urgent_severe_symptoms"
    elif is_virus:
        decision_tree_node = "high_priority_virus"
    elif high_blight_weather:
        decision_tree_node = "urgent_weather_blight"
    elif (
        is_blight
        or is_bacterial
        or is_spider_mite
        or health_score < 55
        or dry_ratio >= 20
    ):
        decision_tree_node = "high_priority_symptoms"
    else:
        decision_tree_node = "monitor_and_verify"

    if is_healthy and health_score >= 60:
        return with_metrics(
            _advice(
                "Rutin",
                f"Daun {plant_name} tampak relatif sehat pada foto ini; fokus pada pencegahan.",
                [
                    "Periksa daun baru dan sisi bawah daun setiap minggu.",
                    "Siram di pangkal tanaman dan jaga sirkulasi udara.",
                ],
                [
                    "Sanitasi alat dan sisa tanaman; lakukan rotasi sesuai pola tanam.",
                    "Atur pemupukan berdasarkan uji tanah.",
                ],
                ["Tidak perlu fungisida/bakterisida berdasarkan foto daun yang tampak sehat."],
                "Tanpa pemantauan rutin, gejala awal atau hama yang belum tampak dapat terlewat.",
                decision_tree_node="monitor_healthy",
            )
        )

    priority = "Tinggi" if is_virus or is_blight or health_score < 40 else "Sedang"

    emergency = [
        "Tandai gejala dan periksa 3–5 tanaman di sekitarnya hari ini.",
        "Buang daun yang sangat rusak dengan alat bersih; pisahkan dari kompos.",
    ]
    if high_blight_weather:
        emergency.insert(
            0,
            "Cuaca lembap dan hangat meningkatkan risiko hawar; cek daun sekitar dan hindari membasahi tajuk.",
        )
    if is_virus:
        emergency = [
            "Pisahkan tanaman bergejala dan bersihkan alat sebelum berpindah.",
            "Periksa kutu kebul/aphid; konfirmasi virus sebelum mencabut tanaman.",
        ]
    elif is_spider_mite:
        emergency = [
            "Periksa bawah daun dengan kaca pembesar untuk mencari tungau/jaring halus.",
            "Pantau tanaman sekitar dan bersihkan alat sebelum berpindah.",
        ]

    organic = [
        "Sanitasi alat dan sisa tanaman; atur rotasi sesuai pola tanam.",
        "Siram di pangkal dan jaga sirkulasi udara; gunakan produk hayati hanya jika terdaftar.",
    ]
    chemical = [
        "Minta penyuluh memastikan diagnosis serta bahan aktif terdaftar untuk tanaman ini.",
        "Ikuti label, APD, interval panen, dan rotasi FRAC; jangan mencampur produk.",
    ]
    impact = (
        "Bercak atau hawar dapat meluas pada kondisi mendukung, mengurangi luas daun sehat, dan menurunkan hasil."
    )
    if is_bacterial:
        organic = [
            "Gunakan benih sehat; sanitasi alat dan hindari percikan dari tanaman sakit.",
            "Pertimbangkan pengendalian hayati hanya jika produk terdaftar untuk tanaman.",
        ]
        chemical = [
            "Pertimbangkan produk tembaga hanya setelah dugaan bakteri dan label dikonfirmasi.",
            "Minta arahan penyuluh; pemakaian berulang berisiko resistansi/fitotoksisitas.",
        ]
        impact = "Jika penyebab bakteri benar, bercak dapat menyebar lewat percikan air dan sisa tanaman terinfeksi."
    elif is_virus:
        organic = [
            "Pisahkan tanaman; musnahkan yang terinfeksi berat sesuai aturan setempat.",
            "Kelola vektor terpadu dan bersihkan alat serta area tanam.",
        ]
        chemical = [
            "Fungisida/bakterisida tidak menyembuhkan tanaman yang terinfeksi virus.",
            "Kendalikan vektor hanya setelah identifikasi dan ikuti label produk.",
        ]
        impact = "Virus dapat menetap dan menyebar melalui vektor atau bahan tanam, sehingga tanaman lain berisiko terinfeksi."
    elif is_spider_mite:
        organic = [
            "Pertahankan predator alami; hindari insektisida spektrum luas tanpa identifikasi.",
            "Bilas bawah daun bila sesuai budidaya dan tidak meningkatkan risiko jamur.",
        ]
        chemical = [
            "Jangan gunakan akarisida sebelum tungau teridentifikasi dan label tanaman diperiksa.",
        ]
        impact = "Populasi tungau yang meningkat dapat menyebabkan daun berbintik, menguning, lalu mengering."
    elif is_blight and plant in {"potato", "kentang", "tomato", "tomat"}:
        if "late blight" in disease:
            chemical[0] = (
                "Untuk hawar daun, minta penyuluh memeriksa fungisida terdaftar, diagnosis, label, dan rotasi FRAC."
            )
        else:
            chemical[0] = (
                "Untuk hawar dini, minta penyuluh menilai azoxystrobin/difenoconazole dan cek label komoditas."
            )
        if high_blight_weather:
            priority = "Sangat tinggi"
    elif plant in {"corn", "corn (maize)", "jagung"}:
        chemical[0] = (
            "Untuk penyakit daun jagung, verifikasi bahan aktif dan label tanaman bersama penyuluh."
        )

    if dry_ratio >= 10 or health_score < 50:
        emergency.append(
            "Periksa kelembapan tanah, akar, dan drainase; koreksi air sebelum mempertimbangkan pupuk."
        )
    summary = (
        "Gejala visual dapat mengarah ke virus; fungisida atau pupuk tidak menyembuhkan virus pada tanaman terinfeksi."
        if is_virus
        else "Saran berikut adalah langkah skrining dan pengelolaan terpadu; foto saja belum memastikan penyebab."
    )
    return with_metrics(
        _advice(
            priority,
            summary,
            emergency,
            organic,
            chemical,
            impact,
            decision_tree_node=decision_tree_node,
        )
    )
