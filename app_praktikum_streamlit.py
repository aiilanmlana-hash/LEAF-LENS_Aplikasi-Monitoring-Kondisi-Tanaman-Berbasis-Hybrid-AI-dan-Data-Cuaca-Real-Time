# ==============================================================================
# PROJECT    : Smart Plant Monitoring & AI Detection
# AUTHOR     : Ahmad Maulana (NIM: E41241323)
# INSTITUTION: Teknik Informatika - Politeknik Negeri Jember (Kampus Sidoarjo)
# YEAR       : 2026
# COPYRIGHT  : (c) 2026 Ahmad Maulana. All Rights Reserved.
# ==============================================================================

import streamlit as st
import cv2
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torchvision import models, transforms, datasets
from PIL import Image, ImageOps
from pathlib import Path
from datetime import datetime
import os

# ==========================================
# 1. KONFIGURASI HALAMAN & DIREKTORI
# ==========================================
st.set_page_config(
    page_title="Smart Plant Monitoring & AI",
    page_icon="🌱",
    layout="wide"
)

# TRIK CSS AGAR KAMERA BROWSER STREAMLIT TIDAK MIRROR / TERBALIK
st.markdown(
    """
    <style>
    div[data-testid="stCameraInput"] video {
        transform: scaleX(-1);
    }
    </style>
    """,
    unsafe_allow_html=True
)

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "outputsApp"
MASK_DIR = OUTPUT_DIR / "masks"
CSV_FILE = OUTPUT_DIR / "hasil_monitoring.csv"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
MASK_DIR.mkdir(parents=True, exist_ok=True)

def simpan_hasil(data_baru):
    df_baru = pd.DataFrame([data_baru])
    if CSV_FILE.exists():
        df_lama = pd.read_csv(CSV_FILE)
        df_gabungan = pd.concat([df_lama, df_baru], ignore_index=True)
    else:
        df_gabungan = df_baru
    df_gabungan.to_csv(CSV_FILE, index=False, encoding="utf-8-sig")
    return df_gabungan

# ==========================================
# 2. LOAD MODEL AI PYTORCH
# ==========================================
@st.cache_resource
def load_ai_model():
    TRAIN_DIR = 'PlantVillage/train'
    if os.path.exists(TRAIN_DIR):
        train_dataset = datasets.ImageFolder(TRAIN_DIR)
        class_names = train_dataset.classes
    else:
        class_names = ['Strawberry___Leaf_scorch', 'Tomato___Bacterial_spot', 'Tomato___Early_blight', 'Tomato___healthy']

    num_classes = len(class_names)
    model = models.mobilenet_v2()
    model.classifier[1] = nn.Linear(model.last_channel, num_classes)

    if os.path.exists('model_daun.pth'):
        model.load_state_dict(torch.load('model_daun.pth', map_location=torch.device('cpu')))
    model.eval()
    return model, class_names

model, class_names = load_ai_model()

transform = transforms.Compose([
    transforms.Resize((128, 128)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
])

# ==========================================
# 3. SIDEBAR PARAMETER SEGMENTASI (Sesuai Modul)
# ==========================================
st.sidebar.header("⚙️ Pengaturan Segmentasi")
h_min = st.sidebar.slider("Hue Minimum", 0, 179, 25)
h_max = st.sidebar.slider("Hue Maksimum", 0, 179, 95)
s_min = st.sidebar.slider("Saturation Minimum", 0, 255, 35)
s_max = st.sidebar.slider("Saturation Maksimum", 0, 255, 255)
v_min = st.sidebar.slider("Value Minimum", 0, 255, 30)
v_max = st.sidebar.slider("Value Maksimum", 0, 255, 255)
kernel_size = st.sidebar.select_slider("Ukuran Kernel Morfologi", options=[3, 5, 7, 9], value=5)

# ==========================================
# 4. TAMPILAN UTAMA STREAMLIT & WATERMARK
# ==========================================
st.title("🌱 Smart Plant Monitoring + AI Detection")
st.caption("© 2026 Developed by **Ahmad Maulana (E41241323)** - Teknik Informatika Polije Kampus Sidoarjo")
st.write("Aplikasi monitoring tanaman berbasis **Streamlit, OpenCV HSV, dan PyTorch AI**.")
st.divider()

col_in1, col_in2 = st.columns(2)
with col_in1:
    plant_id = st.text_input("ID Tanaman", value="P001_Daun")
with col_in2:
    lokasi = st.text_input("Lokasi Pengamatan", value="Politeknik Negeri Jember")

sumber_gambar = st.radio("Pilih Sumber Gambar:", ("Ambil dari Kamera MacBook", "Unggah Foto"))

uploaded_file = None
is_webcam = False

if sumber_gambar == "Ambil dari Kamera MacBook":
    uploaded_file = st.camera_input("Ambil foto dari Kamera MacBook")
    is_webcam = True
else:
    uploaded_file = st.file_uploader("Unggah foto daun", type=["jpg", "jpeg", "png"])

if uploaded_file is not None:
    # Membaca gambar & Un-mirror jika dari kamera webcam
    image_pil = Image.open(uploaded_file).convert("RGB")
    if is_webcam:
        image_pil = ImageOps.mirror(image_pil)  # Membalik hasil jepretan webcam agar normal

    image_rgb = np.array(image_pil)
    image_bgr = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR)

    # 1. Segmentasi HSV Hijau & Morfologi (OPEN -> CLOSE)
    hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    lower_hsv = np.array([h_min, s_min, v_min], dtype=np.uint8)
    upper_hsv = np.array([h_max, s_max, v_max], dtype=np.uint8)
    mask_green_raw = cv2.inRange(hsv, lower_hsv, upper_hsv)

    kernel = np.ones((kernel_size, kernel_size), np.uint8)
    mask_green_open = cv2.morphologyEx(mask_green_raw, cv2.MORPH_OPEN, kernel)
    mask_green_clean = cv2.morphologyEx(mask_green_open, cv2.MORPH_CLOSE, kernel)

    # 2. Segmentasi HSV Cokelat/Kuning (Kering/Layu)
    lower_yellow = np.array([15, 40, 40], dtype=np.uint8)
    upper_yellow = np.array([30, 255, 255], dtype=np.uint8)
    mask_yellow_raw = cv2.inRange(hsv, lower_yellow, upper_yellow)
    mask_yellow_clean = cv2.morphologyEx(mask_yellow_raw, cv2.MORPH_OPEN, kernel)

    # 3. Hitung Piksel & Rasio
    green_pixels = cv2.countNonZero(mask_green_clean)
    yellow_pixels = cv2.countNonZero(mask_yellow_clean)
    total_pixels = image_rgb.shape[0] * image_rgb.shape[1]
    
    green_ratio = (green_pixels / total_pixels) * 100 if total_pixels > 0 else 0.0
    yellow_ratio = (yellow_pixels / total_pixels) * 100 if total_pixels > 0 else 0.0

    # Mask Gabungan Tampilan (Putih: Hijau, Abu-abu: Kering/Kuning)
    display_mask = np.zeros_like(mask_green_clean)
    display_mask[mask_yellow_clean > 0] = 150
    display_mask[mask_green_clean > 0] = 255

    # 4. AI Prediction
    input_tensor = transform(image_pil).unsqueeze(0)
    with torch.no_grad():
        output = model(input_tensor)
        probabilities = torch.nn.functional.softmax(output[0], dim=0)
        confidence, predicted_idx = torch.max(probabilities, 0)

    raw_label = class_names[predicted_idx.item()]
    persentase_ai = confidence.item() * 100

    # 5. Logika Status & Suara Bahasa Indonesia
    if green_ratio < 2.0 and yellow_ratio < 3.0:
        kondisi = "Tidak Ada Daun Terdeteksi"
        text_speak = "Tidak ada daun terdeteksi"
        st_color = st.error
    elif yellow_ratio > 5.0 and yellow_ratio > green_ratio:
        kondisi = "DAUN KERING ATAU LAYU"
        text_speak = "Ini terdeteksi daun kering berwarna kuning atau cokelat"
        st_color = st.warning
    elif "healthy" in raw_label.lower() or green_ratio > 8.0:
        kondisi = "DAUN HIJAU SEHAT"
        text_speak = "Ini terdeteksi daun hijau yang sehat"
        st_color = st.success
    else:
        kondisi = "DAUN TIDAK SEHAT / TERINFEKSI"
        text_speak = "Ini terdeteksi daun tidak sehat atau terinfeksi penyakit"
        st_color = st.error

    # Bunyikan suara Bahasa Indonesia secara otomatis di MacBook!
    os.system(f'killall say 2>/dev/null; say -v Damayanti "{text_speak}" &')

    # 6. Tampilkan Visualisasi Bersandingan (2 Output)
    st.subheader("📸 Hasil Pengolahan Citra & Segmentasi")
    st_color(f"🔊 **Status Suara:** \"{text_speak}\" | **Kondisi:** {kondisi} | **Hijau:** {green_ratio:.2f}% | **Kering:** {yellow_ratio:.2f}%")

    col1, col2 = st.columns(2)
    with col1:
        st.image(display_mask, caption="Mask Segmentasi (Putih: Hijau, Abu-abu: Kering/Kuning)", use_container_width=True)
    with col2:
        st.image(image_rgb, caption=f"Foto Hasil Jepretan (AI: {raw_label} - {persentase_ai:.1f}%)", use_container_width=True)

    # Tombol Simpan Hasil Monitoring (Sesuai Praktikum)
    if st.button("💾 Simpan Hasil Monitoring", type="primary"):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        mask_filename = f"{plant_id}_{timestamp}_mask.png"
        mask_path = MASK_DIR / mask_filename
        cv2.imwrite(str(mask_path), display_mask)

        data_monitoring = {
            "waktu_pemrosesan": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "id_tanaman": plant_id,
            "lokasi": lokasi,
            "nama_file": uploaded_file.name if hasattr(uploaded_file, 'name') else f"webcam_{timestamp}.jpg",
            "total_piksel": total_pixels,
            "piksel_hijau": green_pixels,
            "piksel_kering": yellow_pixels,
            "persentase_hijau": round(green_ratio, 2),
            "hsv_bawah": str([h_min, s_min, v_min]),
            "hsv_atas": str([h_max, s_max, v_max]),
            "ukuran_kernel": kernel_size,
            "file_mask": str(mask_path.relative_to(BASE_DIR)),
            "kondisi_daun": kondisi,
            "keyakinan_ai": f"{persentase_ai:.2f}%"
        }
        simpan_hasil(data_monitoring)
        st.success(f"Data tanaman {plant_id} berhasil disimpan ke CSV dan Mask!")

# Tampilkan Riwayat CSV
st.divider()
st.subheader("📊 Riwayat Monitoring CSV")
if CSV_FILE.exists():
    df_hist = pd.read_csv(CSV_FILE)
    st.dataframe(df_hist, use_container_width=True)