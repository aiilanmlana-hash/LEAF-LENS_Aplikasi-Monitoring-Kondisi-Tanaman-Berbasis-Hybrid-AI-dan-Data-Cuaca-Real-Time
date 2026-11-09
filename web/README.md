# LEAF LENS — Web

**Aplikasi Monitoring Kondisi Tanaman Berbasis Hybrid AI dan Data Cuaca Real-Time**

Klien Flutter Web LEAF LENS untuk monitoring kondisi tanaman. Aplikasi menggunakan Firebase Email/Password Authentication, Firestore realtime history, browser camera capture, gallery/file upload, local green/dry HSV preview, dan endpoint klasifikasi MobileNetV2 FastAPI dengan EfficientNet-B0 opsional. Domain Erytheia tetap sama.

The shared web shell uses `assets/landscape.jpg` as a softly blurred, lightly veiled full-screen background. Login, dashboard, scan, and history use optimized, locally bundled artwork supplied for this project; checkerboard backgrounds are removed from decorative cutouts. The latest artwork set includes a forest tree, deer, stump bird, lanterns, stones, a fairy, driftwood, mossy branch, swallow, and reading statue. The project owner confirmed rights to use the supplied Rawpixel artwork. The authentication panel, sidebar, dashboard cards, inputs, navigation, and confirmation dialogs use a layered, earthy macOS Tahoe-inspired glass treatment; no external image host is required.

Typography pairs a restrained Georgia display face with a familiar system sans-serif for controls and body copy. Artwork is kept decorative and pointer-inert, and the interface retains its responsive layouts and reduced-motion behavior.

Subtle fade-and-rise entrances and hover lifts are used on key content cards. They use short transform/opacity animations, do not animate continuously, and honor the operating system's reduced-motion preference.

The scan path bounds uploaded images to 1600 px, yields a frame before starting
network work, and avoids a synchronous full-image processing pass during normal
backend analysis. The Glassmorphism surfaces use the existing restrained,
non-continuous motion; no continuously repainting glow effect is used. These
choices target responsive interaction, but a 60–120 Hz experience depends on
the browser, device, image, and network and must be measured on target hardware.

## Source map

The web project is a Flutter/Dart frontend. Its main code is grouped by purpose:

| Path | Responsibility |
|---|---|
| `lib/main.dart` | Firebase startup, sign-in state, page navigation, and shared app shell |
| `lib/screens/` | Authentication, dashboard, scan, and history screens |
| `lib/services/image_processing_service.dart` | Browser-side HSV mask, local fallback ratios, and image helpers |
| `lib/services/plant_api_service.dart` | Multipart request to the Python API |
| `lib/services/monitoring_repository.dart` | User-scoped Firestore history and saved analysis |
| `lib/models/plant_analysis.dart` | Data model passed between the scan screen and UI |
| `lib/theme/`, `lib/widgets/` | Shared visual theme and reusable widgets |
| `assets/` | Bundled backgrounds and decorative artwork |
| `test/` | Flutter widget and image-processing tests |

## Tutorial menjalankan web secara lokal

Tutorial ini menjalankan LEAF LENS secara lokal dengan dua bagian terpisah:
FastAPI sebagai backend analisis dan Flutter Web sebagai frontend. Buka dua
jendela Terminal dan biarkan keduanya tetap berjalan selama aplikasi digunakan.
Geolokasi browser diminta saat analisis dimulai. Jika izin ditolak, lokasi tidak
tersedia, atau permintaan melewati batas waktu, aplikasi mengirim koordinat
default Sidoarjo `(-7.4478, 112.7183)` agar backend tetap mencoba mengambil
cuaca Open-Meteo dan fallback historis BMKG. Ketersediaan cuaca tetap bergantung
pada jaringan dan ketersediaan sumber data.

### 1. Persiapan (sekali saja)

Pastikan Python 3.13 dan Flutter sudah terpasang. Jalankan perintah berikut dari
folder utama repository untuk menyiapkan backend:

```sh
python3.13 -m venv .venv-api313
source .venv-api313/bin/activate
python -m pip install -r backend/requirements.txt
```

Aktifkan kembali virtual environment ini di Terminal 1 sebelum menjalankan API.
Pasang dependensi Flutter sekali dari folder `web/`:

```sh
cd web
flutter pub get
```

Jika virtual environment telah dibuat sebelumnya, lewati langkah pembuatan dan
aktifkan environment yang sudah ada.

### 2. Jalankan backend LEAF LENS (Terminal 1)

Dari folder utama proyek, aktifkan virtual environment lalu jalankan API:

```sh
source .venv-api313/bin/activate
PLANT_REQUIRE_AUTH=false python -m uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```

Biarkan proses ini berjalan. Buka <http://127.0.0.1:8000/docs> untuk memastikan
halaman dokumentasi API muncul. `PLANT_REQUIRE_AUTH=false` hanya untuk demo
lokal; jangan gunakan konfigurasi ini pada server publik.
Health check dapat diverifikasi di <http://127.0.0.1:8000/health>; respons yang
diharapkan adalah `{"status":"ok"}`.

### 3. Jalankan frontend LEAF LENS (Terminal 2)

```sh
cd web
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5001 --dart-define=PLANT_API_URL=http://127.0.0.1:8000
```

Setelah Terminal 2 menampilkan alamat server, buka
<http://127.0.0.1:5001>. Jika port 5001 sedang dipakai, pilih port lain dan
gunakan URL itu di browser. Gunakan `localhost` atau `127.0.0.1` agar browser
menganggap halaman lokal sebagai secure context yang dapat meminta lokasi.
Untuk membuka Chrome secara otomatis, alternatifnya jalankan
`flutter run -d chrome --dart-define=PLANT_API_URL=http://127.0.0.1:8000`.

### 4. Masuk dan mencoba LEAF LENS

1. Buka <http://127.0.0.1:5001>, lalu buat akun atau masuk dengan email dan kata sandi. Akun baru
   harus memverifikasi email terlebih dahulu.
2. Buka menu **Analisis tanaman**, lalu pilih atau unggah foto daun tomat, kentang, atau jagung.
3. Isi informasi tanaman. Saat **Analisis daun** ditekan, izinkan akses lokasi
   jika browser memintanya. Koordinat manual yang diisi akan diprioritaskan;
   jika tidak, aplikasi memakai lokasi browser, lalu koordinat default Sidoarjo
   jika lokasi ditolak atau timeout. Status koordinat yang digunakan tampil di
   formulir scan.
4. Tekan tombol analisis dan lihat hasil, cuaca, serta rekomendasi pada kartu
   hasil. Izin kamera browser diperlukan untuk mengambil foto langsung; gunakan
   **Upload foto** jika kamera tidak tersedia.

Jika izin lokasi sebelumnya ditolak, ubah izin **Location** untuk alamat lokal
LEAF LENS pada pengaturan situs browser, lalu muat ulang halaman. Scan tetap
mengirim koordinat default saat izin tidak diberikan. Jika cuaca tidak muncul,
periksa koneksi backend dan akses jaringan ke Open-Meteo; koordinat yang valid
memungkinkan backend mencoba fallback historis BMKG, tetapi tidak menjamin
sumber cuaca selalu tersedia.

Firebase Web sudah dikonfigurasi di `lib/firebase_options.dart`. Agar login dan
riwayat berfungsi, proyek Firebase terkait harus mengaktifkan Email/Password
Authentication dan Cloud Firestore; rincian pengaturannya ada pada bagian
Firebase di bawah.

### Menghentikan aplikasi

Tekan `Ctrl+C` di masing-masing Terminal untuk menghentikan frontend dan
backend. Saat menjalankan ulang, mulai backend terlebih dahulu, kemudian
frontend. Jika sebuah port masih dipakai, hentikan proses lama atau ubah port
beserta `PLANT_API_URL` yang sesuai.

### Status model dan batasan

Checkpoint model `*.pth` dan dataset `PlantVillage/` sengaja tidak disertakan
dalam Git. Untuk memakai inferensi, tempatkan checkpoint MobileNetV2 yang
kompatibel di `backend/model_daun_plantvillage_full_train.pth` atau set
`PLANT_MODEL_PATH` ke lokasi checkpoint. Checkpoint harus memuat state dict dan
metadata `classes` berurutan yang cocok dengan model. Tanpa checkpoint, API
tetap dapat dimulai tetapi analisis gambar mengembalikan status layanan model
tidak tersedia. Training/evaluasi juga memerlukan dataset terpisah di
`PlantVillage/train/` dan `PlantVillage/val/`.

Checkpoint OOD-aware MobileNetV2 yang dipakai dalam evaluasi sebelumnya
dilatih selama tiga epoch. Evaluasi validation terakhir memakai 7.014 gambar
setelah 10 duplikat byte-identik dikeluarkan:
accuracy 98.66%, macro F1 94.88%, dan validation loss 0.04855 pada 19 kelas.
Angka ini mengukur split validation yang tersedia, bukan jaminan untuk semua
foto lapangan. OOD mencakup cats/dogs serta contoh wajah dan objek COCO128 yang
ditambahkan ke dataset, tetapi kelas tersebut tetap tidak mewakili semua objek,
latar dan kamera. Softmax confidence dapat overconfident pada objek yang tidak
pernah dilatih.

Jika analisis masih menampilkan prediksi tanaman dengan confidence rendah,
pastikan frontend mengarah ke backend terbaru melalui `PLANT_API_URL` dan
restart proses FastAPI setelah mengganti source atau checkpoint. Backend LEAF LENS menolak kelas `Background_or_Invalid`, spesies selain
jagung/kentang/tomat, atau confidence di bawah 70% dengan pesan yang sesuai
untuk pengguna.
Flutter Web tidak menjalankan filter OOD sendiri; untuk hasil yang diterima,
badge status memakai label kelas asli (`class_name`) dari MobileNetV2. Badge
Sehat hanya tampil untuk label penyakit `healthy`, bukan karena rasio warna
hijau.

### Menghentikan aplikasi dan kendala umum

- Tekan `q` atau `Ctrl+C` pada Terminal 2 untuk menghentikan Flutter. Tekan
  `Ctrl+C` pada Terminal 1 untuk menghentikan API LEAF LENS.
- Jika API port 8000 sudah berjalan dan `/docs` dapat dibuka, gunakan server
  tersebut; jangan jalankan salinan kedua pada port yang sama. Jika perlu
  memakai port API lain (misalnya 8001), ubah `--port` backend dan samakan
  alamat `PLANT_API_URL` di perintah Flutter.
- Jika muncul pesan `Address already in use`, port tersebut sedang dipakai.
  Pilih port frontend lain dengan `--web-port` atau gunakan API yang sudah
  berjalan.
- Jika login gagal, cek koneksi internet, konfigurasi Firebase, status
  verifikasi email, dan authorized domain `localhost` di Firebase Authentication.

## Firebase

Firebase Web config is defined in `lib/firebase_options.dart`. In Firebase Console:

1. Enable **Authentication → Email/Password** and set a strong-password policy.
2. Create the Cloud Firestore database.
3. Add `localhost` and your deployed hostname to Authentication's authorized domains.
4. Add `erytheia.id` and `www.erytheia.id` to Authentication's authorized domains before production.
5. Deploy the owner-scoped Firestore rules:

   ```sh
   cd web
   firebase deploy --only firestore:rules
   ```

New accounts receive an email-verification link and must verify before entering the app. The app only queries `monitoring_records` for the current user's UID. Do not put Firebase service-account credentials in the client.

## Processing and API

The scan screen uses a backend-first analysis pipeline. Local HSV segmentation
produces green and dry-color masks followed by Open → Close morphology. This is a preview and offline fallback; the Dart
implementation does **not** run K-Means. When available, the backend mask and
area ratios replace the local ones in the displayed analysis. For a selected front-camera correction, the original image bytes and a mirror
flag are sent; FastAPI applies that flip before classification. The browser
uses a display transform for the preview rather than decoding/re-encoding the
full image on the UI thread. The image is sent to:

```text
POST {PLANT_API_URL}/api/v1/analyze-plant
```

Inside `backend/main.py`, the API decodes the upload and follows this order:

1. MobileNetV2 resizes the photo to 256 × 256. When a trained
   EfficientNet-B0 checkpoint is configured, the API averages MobileNetV2 and
   EfficientNet-B0 softmax probabilities using fixed weights 0.60 and 0.40.
   Otherwise MobileNetV2 is used alone; no secondary checkpoint is currently
   bundled. The backend rejects `Background_or_Invalid`, unsupported classes,
   and supported-class confidence below 70%. The Web client uses only the
   returned `class_name` for the diagnostic status and does not repeat OOD
   checks.
2. `backend/segmentation.py` runs sampled CIE-Lab K-Means (up to three color
   groups), applies separate HSV criteria to green and dry pigment masks,
   cleans the masks, and measures area ratios. This is where K-Means is
   implemented.
3. The API obtains current or historical weather when coordinates are
   available; the response labels the source and risk weight. Sugeno rules
   combine area ratios and blight weather risk. The historical fallback has
   a lower heuristic risk weight than a current observation; these weights
   describe provenance and are not calibrated probabilities.
4. `backend/care_recommendations.py` evaluates the predicted class, green/dry
   ratios, Sugeno score, temperature, and humidity through a deterministic
   decision tree and returns triage actions. It is not a trained model or
   agronomic diagnosis.
5. `backend/numeric_ann.py` can optionally predict from seven image-derived
   numeric features plus temperature, humidity, and rainfall. The numeric ANN
   is separate from MobileNetV2 and needs an independently labeled
   ten-feature dataset.

The API returns the predicted class, plant and disease names, confidence,
K-Means-refined green/dry area ratios and mask, current or historical weather,
Sugeno score/severity, structured `risk_analysis` metrics (fuzzy health, inverse
leaf risk, rule-based weather-risk index and measurements, area ratios, and
priority), and (when a trained checkpoint and weather are available) the
numeric ANN result. The scan screen presents these metrics in responsive
glassmorphism cards, groups emergency/organic/chemical actions separately, and
keeps the screening and product-label disclaimer in a footer alert. The weather
index is a heuristic, not a probability of disease. OOD rejection returns HTTP 422 with
`detail.code = "ood_image"`; malformed or oversized images have separate 4xx
responses.

Enter latitude and longitude in the scan form to request current conditions
from Open-Meteo. If the service is unreachable, the API averages records for
the current month from the nearest station in
`backend/climate_data_idn.csv/climate_data.csv` and
`backend/climate_data_idn.csv/station_detail.csv`. Without coordinates, the
weather-aware fuzzy adjustment and numeric ANN are unavailable. The fuzzy
score applies a modest warm/humid weather-risk adjustment to blight predictions;
it is a risk indicator, not a diagnosis.

The API server must allow the web origin. Configure the FastAPI host with the
exact production origin:

Web history is saved in Firestore at `monitoring_records`, scoped by the signed-in
user. Independently, the API machine saves backend analyses in
`outputsApp/monitoring_api.sqlite3`, `outputsApp/monitoring_api.csv`, and
`outputsApp/masks/`. These are two separate history stores.

```sh
PLANT_ALLOWED_ORIGINS=https://erytheia.id,https://www.erytheia.id \
GOOGLE_APPLICATION_CREDENTIALS=/secure/path/firebase-admin.json \
PLANT_REQUIRE_AUTH=true uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Local `localhost` and `127.0.0.1` origins on arbitrary development ports are allowed by the API middleware. Use HTTPS for the deployed API and web origin.

The API also returns a compact `ai_context_json` with short keys for use by a future narration service. No external LLM provider is currently configured, so the app does not send user data to an LLM. A trained numeric ANN checkpoint at `backend/numeric_ann_weights.json` is loaded automatically; `PLANT_NUMERIC_ANN_WEIGHTS=/path/to/numeric_ann_weights.json` overrides the path. The model is deliberately reported unavailable until actual labeled data has been used to train it.

PlantVillage inference runs locally in the FastAPI process; it does not call a chat LLM or spend LLM tokens. The compact JSON is prepared for optional future narration, but no prompt is sent unless you explicitly add an LLM provider.

First merge the labeled OOD and PlantDoc images from the repository root. The
first command previews changes; `--apply` moves the images and removes
folders outside those crops and `Background_or_Invalid` from the train/val
splits:

```sh
python -m backend.prepare_dataset
python -m backend.prepare_dataset --apply
```

PlantDoc `train/` images go to the training split and `test/` images to
validation. The generic `Tomato_leaf` class is kept as
`Tomato___Unspecified_leaf`, not mislabeled as healthy. The cats-and-dogs
training/test images become the labeled `Background_or_Invalid` class.

To fine-tune the filtered MobileNetV2 checkpoint from the repository root, run:

```sh
python -m backend.train_plant_model \
  --dataset-root PlantVillage \
  --epochs 5 \
  --patience 0 \
  --output backend/model_daun_plantvillage_full_train.pth
```

The trainer keeps `Corn_(maize)___*`, `Potato___*`, `Tomato___*`, and
`Background_or_Invalid` folders, and requires images for every selected class
in both `train/` and `val/`. Old MobileNetV2 backbone weights are reused when
available, but the classifier head is reinitialized; the old 38-class
checkpoint cannot be used directly for inference with the filtered classes.
Training augmentation includes horizontal flips, rotations up to 10 degrees,
20% color jitter, and random grayscale (`p=0.1`). The adjacent metrics JSON
includes validation loss/accuracy and confidence distribution using the same
70% OOD rejection threshold as the API.

To train the optional EfficientNet-B0 classifier with the same filtered classes,
use a separate output checkpoint. Torchvision's ImageNet weights may need to be
downloaded on the training machine:

```sh
python -m backend.train_plant_model \
--architecture efficientnet_b0 \
--dataset-root PlantVillage \
--epochs 5 \
--patience 0 \
--output backend/model_efficientnet_b0_plantvillage.pth
```

Only configure `PLANT_SECONDARY_MODEL_PATH` on the API after evaluating the
checkpoint on a held-out dataset and confirming that its class list matches the
MobileNetV2 checkpoint. When configured, inference runs both models
sequentially on the same resized tensor; this improves consensus evidence at
the cost of additional latency and memory. Benchmark on the actual deployment
host before enabling it.

Train the ANN from a labeled CSV (columns:
`green_ratio,dry_ratio,mobilenet_confidence,fuzzy_health_score,mean_hue,mean_saturation,mean_value,temperature_c,humidity_pct,precipitation_mm,label`;
labels `healthy`, `dry`, or `infected`):

```sh
python -m backend.train_numeric_ann observations.csv --output backend/numeric_ann_weights.json
```

The default checkpoint path is loaded automatically; set
`PLANT_NUMERIC_ANN_WEIGHTS` only when the checkpoint is stored elsewhere. A
validation split and representative labels are required before using ANN
predictions in production.

The result card has **Dengarkan Analisis** using the browser's Indonesian (`id-ID`) speech engine, naturalized rate and pitch. Actual voice selection depends on installed browser/OS Indonesian voices.

## Build and Hostinger

```sh
cd web
flutter build web --release --dart-define=PLANT_API_URL=https://api.erytheia.id
```

Upload the **contents** of `web/build/web/` to Hostinger `public_html` for `erytheia.id`. Host the FastAPI/model process separately on a Python-capable service such as a Hostinger VPS at `api.erytheia.id`; static web hosting cannot run the Python inference process. Keep the API and web app on HTTPS.

The repository workflow `.github/workflows/flutter-web-folder.yml` checks the Dart code, runs tests, and produces a downloadable static web artifact. Configure the GitHub Actions variable `PLANT_API_URL` to bake the production API URL into that release build.

## HSV parameter defaults

- H range: 25–95 (OpenCV hue scale 0–179)
- S minimum: 35; V minimum: 30
- Dry leaf range: H 15–30, S ≥ 40, V ≥ 40
- Morphology kernel: 5 × 5 (selectable 3, 5, 7, or 9)

The interface intentionally contains no personal watermark.
