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
) -> dict[str, Any]:
    return {
        "priority": priority,
        "summary": summary,
        "emergency_actions": emergency_actions,
        "organic_recommendations": organic,
        "chemical_recommendations": chemical,
        "untreated_impact": untreated_impact,
        "disclaimer": _DISCLAIMER,
        # Keep the older response key for clients that display generic actions.
        "actions": emergency_actions,
    }


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
    )


def recommend_care(
    *,
    plant_name: str,
    disease_name: str,
    is_healthy: bool,
    confidence: float,
    health_score: float,
    dry_ratio: float,
    temperature_c: float | None = None,
    humidity_pct: float | None = None,
    precipitation_mm: float | None = None,
) -> dict[str, Any]:
    """Return crop-aware actions without treating a photo prediction as certainty."""
    plant = plant_name.casefold().strip()
    disease = disease_name.casefold().replace("_", " ")
    if confidence < 65:
        return _verification_advice(
            "Keyakinan model rendah; hasil penyakit tidak cukup kuat untuk menentukan perlakuan."
        )
    if plant not in _SUPPORTED_PLANTS:
        return _verification_advice(
            "Tanaman berada di luar cakupan rekomendasi Corn, Potato, dan Tomato."
        )
    if is_healthy and health_score >= 60:
        return _advice(
            "Rutin",
            f"Daun {plant_name} tampak relatif sehat pada foto ini; fokus pada pencegahan.",
            [
                "Pantau daun baru dan sisi bawah daun setiap minggu.",
                "Siram di area akar dan jaga sirkulasi udara di antara tanaman.",
            ],
            [
                "Gunakan rotasi tanaman dan sanitasi sisa tanaman sesuai praktik setempat.",
                "Pertahankan nutrisi berdasarkan uji tanah, bukan pemupukan spekulatif.",
            ],
            ["Tidak perlu fungisida/bakterisida berdasarkan foto daun yang tampak sehat."],
            "Tanpa pemantauan rutin, gejala awal atau hama yang belum tampak dapat terlewat.",
        )

    is_virus = any(term in disease for term in ("virus", "mosaic", "yellow leaf curl"))
    is_bacterial = any(term in disease for term in ("bacterial", "bacteria"))
    is_blight = "blight" in disease
    is_spider_mite = "spider mite" in disease
    high_blight_weather = (
        is_blight
        and humidity_pct is not None
        and humidity_pct >= 85
        and temperature_c is not None
        and temperature_c >= 22
    )
    priority = "Tinggi" if is_virus or is_blight or health_score < 40 else "Sedang"

    emergency = [
        "Tandai dan foto gejala; periksa beberapa tanaman untuk memastikan pola penyebarannya.",
        "Buang daun yang sangat rusak dengan alat bersih dan jangan memindahkan sisa sakit ke kompos.",
    ]
    if high_blight_weather:
        emergency.insert(
            0,
            "Kelembapan tinggi dan suhu hangat meningkatkan risiko hawar; periksa tanaman dan daun sekitarnya hari ini.",
        )
    if is_virus:
        emergency = [
            "Pisahkan tanaman bergejala berat dan bersihkan alat sebelum berpindah ke tanaman lain.",
            "Periksa vektor seperti kutu kebul atau aphid; konfirmasi virus sebelum mencabut tanaman.",
        ]
    elif is_spider_mite:
        emergency = [
            "Periksa sisi bawah daun dengan kaca pembesar untuk memastikan tungau atau jaring halus.",
            "Cegah perpindahan tungau dengan membersihkan alat dan memantau tanaman di sekitarnya.",
        ]

    organic = [
        "Kurangi sumber inokulum dengan sanitasi, rotasi tanaman, dan penyiraman di area akar.",
        "Produk hayati berbasis Bacillus subtilis dapat dipertimbangkan sebagai pendukung pencegahan bila terdaftar untuk komoditas setempat.",
    ]
    chemical = [
        "Bahan aktif fungisida yang dapat ditanyakan kepada penyuluh: azoxystrobin atau mancozeb; kecocokan tanaman/penyakit dan registrasi harus diperiksa pada label lokal.",
        "Jangan mencampur produk atau menentukan dosis dari aplikasi ini; ikuti label, interval panen, APD, dan rotasi kelompok FRAC.",
    ]
    impact = (
        "Bercak atau hawar dapat meluas pada kondisi mendukung, mengurangi luas daun sehat, dan menurunkan hasil."
    )
    if is_bacterial:
        organic = [
            "Gunakan benih sehat, sanitasi alat, rotasi, dan hindari memercikkan air dari tanaman sakit.",
            "Pengendalian hayati berbasis Bacillus subtilis hanya sebagai tindakan pencegahan pendukung bila produk lokal terdaftar.",
        ]
        chemical = [
            "Bahan aktif berbasis tembaga (misalnya copper hydroxide) hanya dapat dipertimbangkan setelah dugaan bakteri dikonfirmasi dan label mengizinkannya; efektivitas dapat terbatas.",
            "Hindari pemakaian berulang tanpa arahan penyuluh karena resistansi dan fitotoksisitas mungkin terjadi.",
        ]
        impact = "Jika penyebab bakteri benar, bercak dapat menyebar lewat percikan air dan sisa tanaman terinfeksi."
    elif is_virus:
        organic = [
            "Cabut dan musnahkan tanaman terinfeksi berat sesuai aturan setempat; jangan gunakan sebagai bahan tanam.",
            "Kendalikan vektor secara terpadu dan pertahankan kebersihan alat serta area tanam.",
        ]
        chemical = [
            "Tidak ada fungisida/bakterisida yang menyembuhkan virus pada tanaman terinfeksi.",
            "Jangan memakai insektisida hanya untuk mengobati virus; pengendalian vektor harus berdasarkan identifikasi dan label produk.",
        ]
        impact = "Virus dapat menetap dan menyebar melalui vektor atau bahan tanam, sehingga tanaman lain berisiko terinfeksi."
    elif is_spider_mite:
        organic = [
            "Pertahankan predator alami dan hindari penggunaan insektisida spektrum luas tanpa identifikasi hama.",
            "Bilas sisi bawah daun dengan air bila sesuai sistem budidaya dan tidak memperparah penyakit jamur.",
        ]
        chemical = [
            "Tidak ada akarisida yang direkomendasikan dari foto saja; identifikasi tungau dan cek produk terdaftar untuk tanaman tersebut.",
        ]
        impact = "Populasi tungau yang meningkat dapat menyebabkan daun berbintik, menguning, lalu mengering."
    elif is_blight and plant in {"potato", "kentang", "tomato", "tomat"}:
        if "late blight" in disease:
            chemical[0] = (
                "Untuk hawar daun, tanyakan kepada penyuluh tentang bahan aktif protektan seperti mancozeb; produk sistemik (misalnya metalaxyl-M) hanya bila diagnosis, rotasi FRAC, dan label lokal sesuai."
            )
        else:
            chemical[0] = (
                "Untuk bercak/hawar dini, tanyakan kepada penyuluh apakah azoxystrobin atau difenoconazole sesuai diagnosis serta terdaftar pada tanaman ini."
            )
        if high_blight_weather:
            priority = "Sangat tinggi"
    elif plant in {"corn", "corn (maize)", "jagung"}:
        chemical[0] = (
            "Untuk penyakit daun jagung, tanyakan apakah azoxystrobin atau propiconazole terdaftar dan sesuai diagnosis; jangan gunakan tanpa label tanaman yang tepat."
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
    return _advice(
        priority,
        summary,
        emergency,
        organic,
        chemical,
        impact,
    )
