# ==============================================================================
# PROJECT    : Smart Plant AI Model Training (MobileNetV2)
# YEAR       : 2026
# ==============================================================================

import os
import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms, models
from torch.utils.data import DataLoader, Subset
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
import numpy as np

# Print Identitas Pembuat Proyek
print("\n========================================================")
print("  TRAINING MODEL AI - SMART PLANT MONITORING")
print("========================================================\n")

# 1. Konfigurasi
TRAIN_DIR = 'PlantVillage/tomat_kentang/train'
VAL_DIR = 'PlantVillage/tomat_kentang/val'
BATCH_SIZE = 32
EPOCHS = 2
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

print(f"[INFO] Menggunakan device: {DEVICE}")

# 2. Transformasi Gambar
data_transforms = {
    'train': transforms.Compose([
        transforms.Resize((128, 128)),
        transforms.RandomHorizontalFlip(),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
    ]),
}

# 3. Load Dataset Sederhana (Hanya mengambil 1000 data sampel agar cepat)
print("[INFO] Membaca data sampel...")
full_train = datasets.ImageFolder(TRAIN_DIR, transform=data_transforms['train'])

# Ambil 1000 gambar saja dari dataset
subset_indices = list(range(0, min(1000, len(full_train))))
train_dataset = Subset(full_train, subset_indices)

train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True)

num_classes = len(full_train.classes)
print(f"[INFO] Dataset dimuat! Jumlah kategori daun: {num_classes}")

# 4. Model Pretrained MobileNetV2
model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.DEFAULT)
model.classifier[1] = nn.Linear(model.last_channel, num_classes)
model = model.to(DEVICE)

# 5. Loss & Optimizer
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

# 6. Training Loop
print("[INFO] Mulai melatih model (Versi Cepat)...")
for epoch in range(EPOCHS):
    model.train()
    running_loss = 0.0
    for images, labels in train_loader:
        images, labels = images.to(DEVICE), labels.to(DEVICE)
        
        optimizer.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
        
        running_loss += loss.item() * images.size(0)
        
    epoch_loss = running_loss / len(train_dataset)
    print(f"Epoch {epoch+1}/{EPOCHS} Selesai - Loss: {epoch_loss:.4f}")

# 7. Simpan bobot model
model_path = 'model_daun.pth'
torch.save(model.state_dict(), model_path)

print(f"\n[BERHASIL] File '{model_path}' berhasil dibuat!")
print("========================================================\n")
