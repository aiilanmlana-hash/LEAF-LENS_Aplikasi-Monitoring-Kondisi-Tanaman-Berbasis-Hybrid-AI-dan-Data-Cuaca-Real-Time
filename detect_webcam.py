# ==============================================================================
# PROJECT    : Smart Plant AI Classifier (Live Camera)
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

# ==========================================
# 1. LOAD NAMA KELAS & MODEL AI
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

# Transformasi Gambar
transform = transforms.Compose([
    transforms.Resize((128, 128)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
])

# ==========================================
# 2. BUKAM KAMERA MACOS BUILT-IN
# ==========================================
cap = None
for idx in [0, 1, 2]:
    temp_cap = cv2.VideoCapture(idx, cv2.CAP_AVFOUNDATION)
    if temp_cap.isOpened():
        ret, test_frame = temp_cap.read()
        if ret and test_frame is not None:
            cap = temp_cap
            print(f"[INFO] Terhubung ke Kamera Index: {idx} (MacBook Camera)")
            break
        temp_cap.release()

if cap is None:
    print("[ERROR] Kamera tidak ditemukan!")
    exit()

print("\n========================================================")
print("  DEVELOPED BY : Ahmad Maulana (NIM: E41241323)")
print("  INSTITUSI    : Teknik Informatika Polije Kampus Sidoarjo")
print("========================================================\n")
print("Kamera Aktif! Tekan 's' untuk Bicarakan Hasil / Tekan 'q' untuk Keluar.\n")

last_speech = ""

while True:
    ret, frame = cap.read()
    if not ret or frame is None:
        break

    # UN-MIRROR KAMERA HORIZONTAL (Agar Tampilan Normal)
    frame = cv2.flip(frame, 1)

    # ==========================================
    # 3. SEGMENTASI WARNA HIJAU DAUN (HSV)
    # ==========================================
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    lower_green = np.array([25, 40, 40], dtype=np.uint8)
    upper_green = np.array([85, 255, 255], dtype=np.uint8)
    mask = cv2.inRange(hsv, lower_green, upper_green)
    
    green_pixels = cv2.countNonZero(mask)
    total_pixels = frame.shape[0] * frame.shape[1]
    green_ratio = (green_pixels / total_pixels) * 100

    # ==========================================
    # 4. PREDIKSI DENGAN MODEL AI
    # ==========================================
    img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(img_rgb)
    input_tensor = transform(pil_img).unsqueeze(0)

    with torch.no_grad():
        output = model(input_tensor)
        probabilities = torch.nn.functional.softmax(output[0], dim=0)
        confidence, predicted_idx = torch.max(probabilities, 0)

    raw_label = class_names[predicted_idx.item()]
    persentase = confidence.item() * 100
    clean_label = raw_label.replace("___", " - ").replace("_", " ")

    if green_ratio < 2.0:
        status_text = "STATUS: Tidak Ada Daun Terdeteksi"
        deteksi_text = "Hasil: Unknown / Bukan Daun"
        bg_color = (0, 0, 255) # Merah
        text_speak = "Tidak ada daun terdeteksi"
    else:
        status_text = f"STATUS: Daun Terdeteksi ({green_ratio:.1f}% Area Hijau)"
        deteksi_text = f"Hasil: {clean_label} ({persentase:.1f}%)"
        bg_color = (0, 180, 0) # Hijau
        text_speak = f"Terdeteksi daun {clean_label}"

    # ==========================================
    # 5. TAMPILKAN UI & WATERMARK OVERLAY
    # ==========================================
    # Header Atas Informasi Deteksi
    cv2.rectangle(frame, (0, 0), (frame.shape[1], 90), (0, 0, 0), -1)
    cv2.putText(frame, status_text, (15, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.65, bg_color, 2)
    cv2.putText(frame, deteksi_text, (15, 65), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (255, 255, 255), 2)

    # WATERMARK VISUAL PERMANEN (Pojok Bawah Layar Video)
    watermark_text = "(c) 2026 Ahmad Maulana (E41241323) - Polije"
    cv2.rectangle(frame, (0, frame.shape[0] - 30), (frame.shape[1], frame.shape[0]), (0, 0, 0), -1)
    cv2.putText(frame, watermark_text, (15, frame.shape[0] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1, cv2.LINE_AA)

    cv2.imshow("Deteksi Daun & Segmentasi Live - MacBook Camera", frame)

    key = cv2.waitKey(1) & 0xFF
    
    # Tekan 's' untuk membunyikan suara Bahasa Indonesia di Mac
    if key == ord('s'):
        print(f"Mengucapkan: {text_speak}")
        os.system(f'killall say 2>/dev/null; say -v Damayanti "{text_speak}" &')

    # Tekan 'q' untuk keluar
    if key == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()