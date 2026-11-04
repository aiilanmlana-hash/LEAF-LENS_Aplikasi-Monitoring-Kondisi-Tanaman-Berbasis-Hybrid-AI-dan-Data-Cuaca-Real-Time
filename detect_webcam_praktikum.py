# ==============================================================================
# PROJECT    : Smart Plant Monitoring & AI Detection (OpenCV Live)
# AUTHOR     : Ahmad Maulana (NIM: E41241323)
# INSTITUTION: Teknik Informatika - Politeknik Negeri Jember (Kampus Sidoarjo)
# YEAR       : 2026
# COPYRIGHT  : (c) 2026 Ahmad Maulana. All Rights Reserved.
# ==============================================================================

import cv2
import torch
import torch.nn as nn
from torchvision import models, transforms, datasets
from PIL import Image
import numpy as np
import os
import pandas as pd
from pathlib import Path
from datetime import datetime

# ==========================================
# 1. KONFIGURASI DIREKTORI & CSV
# ==========================================
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
    print(f"[INFO] Data berhasil disimpan ke: {CSV_FILE}")

# ==========================================
# 2. LOAD MODEL AI & DATASET
# ==========================================
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
    print("[INFO] Model 'model_daun.pth' berhasil dimuat.")
model.eval()

transform = transforms.Compose([
    transforms.Resize((128, 128)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
])

# ==========================================
# 3. INTERFACE TRACKBAR (HSV & MORFOLOGI)
# ==========================================
def nothing(x):
    pass

cv2.namedWindow("Pengaturan Segmentasi (Modul Praktikum)")
cv2.createTrackbar("H Min", "Pengaturan Segmentasi (Modul Praktikum)", 25, 179, nothing)
cv2.createTrackbar("H Max", "Pengaturan Segmentasi (Modul Praktikum)", 95, 179, nothing)
cv2.createTrackbar("S Min", "Pengaturan Segmentasi (Modul Praktikum)", 35, 255, nothing)
cv2.createTrackbar("S Max", "Pengaturan Segmentasi (Modul Praktikum)", 255, 255, nothing)
cv2.createTrackbar("V Min", "Pengaturan Segmentasi (Modul Praktikum)", 30, 255, nothing)
cv2.createTrackbar("V Max", "Pengaturan Segmentasi (Modul Praktikum)", 255, 255, nothing)
cv2.createTrackbar("Kernel", "Pengaturan Segmentasi (Modul Praktikum)", 5, 15, nothing)

# ==========================================
# 4. INISIALISASI KAMERA MACOS BUILT-IN
# ==========================================
cap = None
for idx in [0, 1, 2]:
    temp_cap = cv2.VideoCapture(idx, cv2.CAP_AVFOUNDATION)
    if temp_cap.isOpened():
        ret, test_frame = temp_cap.read()
        if ret and test_frame is not None:
            cap = temp_cap
            print(f"[INFO] Berhasil terhubung ke Kamera Index: {idx} (MacBook Camera)")
            break
        temp_cap.release()

if cap is None:
    print("[ERROR] Kamera tidak ditemukan!")
    exit()

print("\n========================================================")
print("  DEVELOPED BY : Ahmad Maulana (NIM: E41241323)")
print("  INSTITUSI    : Teknik Informatika Polije Kampus Sidoarjo")
print("========================================================\n")
print("Suara Bahasa Indonesia (Damayanti) Otomatis Aktif!")
print("Tekan 's' : Simpan Hasil Monitoring ke CSV & File Mask")
print("Tekan 'q' : Keluar dari Aplikasi\n")

last_speak_status = ""

while True:
    ret, frame = cap.read()
    if not ret or frame is None:
        break

    # UN-MIRROR KAMERA HORIZONTAL
    frame = cv2.flip(frame, 1)

    # 1. Parameter HSV & Kernel dari Trackbar
    h_min = cv2.getTrackbarPos("H Min", "Pengaturan Segmentasi (Modul Praktikum)")
    h_max = cv2.getTrackbarPos("H Max", "Pengaturan Segmentasi (Modul Praktikum)")
    s_min = cv2.getTrackbarPos("S Min", "Pengaturan Segmentasi (Modul Praktikum)")
    s_max = cv2.getTrackbarPos("S Max", "Pengaturan Segmentasi (Modul Praktikum)")
    v_min = cv2.getTrackbarPos("V Min", "Pengaturan Segmentasi (Modul Praktikum)")
    v_max = cv2.getTrackbarPos("V Max", "Pengaturan Segmentasi (Modul Praktikum)")
    k_size = cv2.getTrackbarPos("Kernel", "Pengaturan Segmentasi (Modul Praktikum)")
    
    k_size = max(1, k_size)
    if k_size % 2 == 0:
        k_size += 1

    # 2. Segmentasi HSV & Morfologi HIJAU
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    lower_hsv = np.array([h_min, s_min, v_min], dtype=np.uint8)
    upper_hsv = np.array([h_max, s_max, v_max], dtype=np.uint8)
    mask_green_raw = cv2.inRange(hsv, lower_hsv, upper_hsv)

    kernel = np.ones((k_size, k_size), np.uint8)
    mask_green_open = cv2.morphologyEx(mask_green_raw, cv2.MORPH_OPEN, kernel)
    mask_green_clean = cv2.morphologyEx(mask_green_open, cv2.MORPH_CLOSE, kernel)

    # 3. Segmentasi HSV & Morfologi KUNING / COKELAT (Kering/Layu)
    lower_yellow = np.array([15, 40, 40], dtype=np.uint8)
    upper_yellow = np.array([30, 255, 255], dtype=np.uint8)
    mask_yellow_raw = cv2.inRange(hsv, lower_yellow, upper_yellow)
    mask_yellow_open = cv2.morphologyEx(mask_yellow_raw, cv2.MORPH_OPEN, kernel)
    mask_yellow_clean = cv2.morphologyEx(mask_yellow_open, cv2.MORPH_CLOSE, kernel)

    # 4. Hitung Rasio Piksel
    green_pixels = cv2.countNonZero(mask_green_clean)
    yellow_pixels = cv2.countNonZero(mask_yellow_clean)
    total_pixels = frame.shape[0] * frame.shape[1]
    
    green_ratio = (green_pixels / total_pixels) * 100 if total_pixels > 0 else 0.0
    yellow_ratio = (yellow_pixels / total_pixels) * 100 if total_pixels > 0 else 0.0

    # 5. MEMBUAT MASK GABUNGAN (Hijau: Putih, Kuning/Cokelat: Abu-abu)
    display_mask = np.zeros_like(mask_green_clean)
    display_mask[mask_yellow_clean > 0] = 150  
    display_mask[mask_green_clean > 0] = 255   

    # 6. Prediksi AI (MobileNetV2)
    img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(img_rgb)
    input_tensor = transform(pil_img).unsqueeze(0)

    with torch.no_grad():
        output = model(input_tensor)
        probabilities = torch.nn.functional.softmax(output[0], dim=0)
        confidence, predicted_idx = torch.max(probabilities, 0)

    raw_label = class_names[predicted_idx.item()]
    persentase_ai = confidence.item() * 100

    # ==========================================
    # 7. LOGIKA KONDISI DAUN & SUARA INDONESIA
    # ==========================================
    if green_ratio < 2.0 and yellow_ratio < 3.0:
        status_text = "STATUS: Tidak Ada Daun Terdeteksi"
        kondisi_text = "Kondisi: Objek Tidak Dikenal"
        bg_color = (0, 0, 255) # Merah
        text_speak = "Tidak ada daun terdeteksi"

    elif yellow_ratio > 5.0 and yellow_ratio > green_ratio:
        status_text = f"STATUS: Daun Terdeteksi ({yellow_ratio:.1f}% Kering)"
        kondisi_text = "Kondisi: DAUN KERING ATAU LAYU"
        bg_color = (0, 140, 255) # Oranye
        text_speak = "Ini terdeteksi daun kering berwarna kuning atau cokelat"

    elif "healthy" in raw_label.lower() or green_ratio > 8.0:
        status_text = f"STATUS: Daun Terdeteksi ({green_ratio:.1f}% Hijau)"
        kondisi_text = "Kondisi: DAUN HIJAU SEHAT"
        bg_color = (0, 180, 0) # Hijau
        text_speak = "Ini terdeteksi daun hijau yang sehat"

    else:
        status_text = f"STATUS: Daun Terdeteksi ({green_ratio:.1f}% Hijau)"
        kondisi_text = "Kondisi: DAUN TIDAK SEHAT / TERINFEKSI"
        bg_color = (0, 0, 220) # Merah Tua
        text_speak = "Ini terdeteksi daun tidak sehat atau terinfeksi penyakit"

    # Penyuaran Otomatis
    if text_speak != last_speak_status:
        print(f"[SUARA OTOMATIS]: {text_speak}")
        os.system(f'killall say 2>/dev/null; say -v Damayanti "{text_speak}" &')
        last_speak_status = text_speak

    # ==========================================
    # 8. TAMPILAN UI BERSANDINGAN & WATERMARK OVERLAY
    # ==========================================
    # Header Atas
    cv2.rectangle(frame, (0, 0), (frame.shape[1], 85), (0, 0, 0), -1)
    cv2.putText(frame, status_text, (15, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
    cv2.putText(frame, kondisi_text, (15, 65), cv2.FONT_HERSHEY_SIMPLEX, 0.65, bg_color, 2)

    # WATERMARK VISUAL PERMANEN PADA LAYAR KAMERA (Bawah Kanan)
    watermark_text = "(c) 2026 Ahmad Maulana (E41241323) - Polije"
    cv2.rectangle(frame, (0, frame.shape[0] - 30), (frame.shape[1], frame.shape[0]), (0, 0, 0), -1)
    cv2.putText(frame, watermark_text, (15, frame.shape[0] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1, cv2.LINE_AA)

    mask_bgr = cv2.cvtColor(display_mask, cv2.COLOR_GRAY2BGR)
    cv2.rectangle(mask_bgr, (0, 0), (mask_bgr.shape[1], 40), (0, 0, 0), -1)
    cv2.putText(mask_bgr, "MASK SEGMENTASI (Putih:Hijau, Abu:Kering)", (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 2)

    combined_output = np.hstack((mask_bgr, frame))
    cv2.imshow("Smart Plant Monitoring - MacBook Camera", combined_output)

    key = cv2.waitKey(1) & 0xFF
    
    # Simpan ke CSV
    if key == ord('s'):
        plant_id = "P001_Daun"
        lokasi = "Politeknik Negeri Jember"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        mask_filename = f"{plant_id}_{timestamp}_mask.png"
        mask_path = MASK_DIR / mask_filename
        cv2.imwrite(str(mask_path), display_mask)
        
        data_monitoring = {
            "waktu_pemrosesan": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "id_tanaman": plant_id,
            "lokasi": lokasi,
            "nama_file": f"webcam_frame_{timestamp}.jpg",
            "total_piksel": total_pixels,
            "piksel_hijau": green_pixels,
            "piksel_kering": yellow_pixels,
            "persentase_hijau": round(green_ratio, 2),
            "hsv_bawah": str([h_min, s_min, v_min]),
            "hsv_atas": str([h_max, s_max, v_max]),
            "ukuran_kernel": k_size,
            "file_mask": str(mask_path.relative_to(BASE_DIR)),
            "kondisi_daun": kondisi_text.replace("Kondisi: ", ""),
            "keyakinan_ai": f"{persentase_ai:.2f}%"
        }
        
        simpan_hasil(data_monitoring)
        print(f"[BERHASIL] Data disimpan: {kondisi_text}")

    if key == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()