# LEAF LENS

**Aplikasi Monitoring Kondisi Tanaman Berbasis Hybrid AI dan Data Cuaca Real-Time**

LEAF LENS tersedia melalui domain Erytheia yang tetap digunakan untuk aplikasi
ini. Repository berisi aplikasi Flutter Web (`web/`), API analisis gambar
FastAPI (`backend/`), aplikasi Flutter mobile terpisah (`mobile/`), dan
eksperimen OpenCV desktop. Aplikasi Web menggunakan API untuk analisis AI;
aplikasi Web bukan server Python atau machine-learning.

Panduan menjalankan aplikasi Web secara lokal ada di
[tutorial LEAF LENS](web/README.md#tutorial-menjalankan-web-secara-lokal).

## Project map

```text
Project_Klasifikasi_Daun/
├── backend/                 # FastAPI API and Python image/AI logic
│   ├── main.py              # HTTP endpoints, pipeline, persistence
│   ├── segmentation.py      # HSV + Lab K-Means segmentation
│   ├── fuzzy_logic.py       # Sugeno health score and severity
│   ├── numeric_ann.py      # Optional ANN for numeric measurements
│   ├── train_plant_model.py  # Train/evaluate image classifier
│   └── train_numeric_ann.py # Train optional numeric ANN from labeled CSV
├── web/                     # Flutter Web frontend (Dart)
│   └── lib/
│       ├── main.dart        # Firebase startup, sign-in gate, app navigation
│       ├── screens/         # Login, dashboard, scan, and history UI
│       ├── services/        # Local image processing, API, Firestore
│       ├── models/          # Analysis data model
│       ├── theme/           # Colors and app theme
│       └── widgets/         # Shared interface components
├── mobile/                  # Separate Flutter mobile application
├── PlantVillage/
│   ├── train/<class>/       # Training images, grouped by class
│   └── val/<class>/         # Validation images, same class folders
├── outputsApp/              # Generated analysis data and evaluation reports
├── model_daun*.pth          # Trained MobileNetV2 checkpoints
├── app_praktikum_streamlit.py, train.py, detect_webcam*.py
│                            # Earlier/standalone desktop experiments
└── README.md                # Main project and processing guide
```

### Where to look when explaining the web app

| Question | File(s) |
|---|---|
| How does the web app start, check sign-in, and open pages? | [`web/lib/main.dart`](web/lib/main.dart) |
| How do I upload/capture a leaf and show the result? | [`web/lib/screens/scan_screen.dart`](web/lib/screens/scan_screen.dart) |
| Where does the browser's HSV preview/mask come from? | [`web/lib/services/image_processing_service.dart`](web/lib/services/image_processing_service.dart) |
| How does the browser send a photo to Python? | [`web/lib/services/plant_api_service.dart`](web/lib/services/plant_api_service.dart) |
| Where are user-specific web records saved? | [`web/lib/services/monitoring_repository.dart`](web/lib/services/monitoring_repository.dart) |
| Where is the API request received and results assembled? | [`backend/main.py`](backend/main.py), `POST /api/v1/analyze-plant` |
| Where are the algorithms? | [`backend/segmentation.py`](backend/segmentation.py), [`backend/fuzzy_logic.py`](backend/fuzzy_logic.py), [`backend/numeric_ann.py`](backend/numeric_ann.py) |

## Analysis flow: photo to result

1. The user captures or selects an image in `web/lib/screens/scan_screen.dart`.
   The front-camera orientation preference is sent with the image; the backend
   applies the flip before classification, avoiding a synchronous browser
   decode/re-encode in the normal scan path.
2. `PlantApiService` asynchronously sends the image, plant ID, location,
   optional latitude/longitude, and HSV/morphology settings as a multipart
   request to `POST /api/v1/analyze-plant`.
3. `backend/main.py` classifies the image with MobileNetV2 first. The OOD guard
   rejects `Background_or_Invalid`, unsupported classes, and supported-class
   confidence below 70% before segmentation or persistence. Flutter Web uses
   the raw `class_name` to show status: only a `healthy` model label is healthy.
4. For accepted predictions, the backend runs:
   - `backend/segmentation.py`: converts pixels to Lab, groups sampled colors
     into up to three K-Means clusters, intersects cluster colors with HSV
     thresholds, cleans the masks, and measures green/dry pixel percentages.
   - `backend/fuzzy_logic.py`: Sugeno fuzzy rules turn the green and dry
     percentages into a 0–100 health score and a severity label, with a modest
     weather-risk adjustment for blight when weather is available.
   - `backend/numeric_ann.py`: when a trained checkpoint and weather are
     available, an optional numeric ANN predicts `healthy`, `dry`, or `infected`
     from seven image measurements plus temperature, humidity, and rainfall.
5. The browser presents the backend mask and ratios. If the API is unavailable,
   the local HSV fallback can still show a color mask, but it does not provide
   MobileNetV2 classification or the backend fuzzy result; **this Dart code
   does not run K-Means**.
6. The browser presents the result and saves a user-scoped record to Firestore.
   Separately, a successful API analysis also saves a record, CSV row, and mask
   on the backend computer (see the output map below).

### What K-Means, ANN, and fuzzy logic mean in this project

- **K-Means** is an unsupervised color grouping step inside
  `backend/segmentation.py`; it has no training dataset or saved model file.
  The code groups Lab pixel colors, then checks each cluster against the green
  and dry HSV ranges to refine the masks.
- **ANN (numeric)** is the optional, supervised model in
  `backend/numeric_ann.py`. It needs a labeled CSV of seven image features,
  temperature, humidity, rainfall, and a `healthy`/`dry`/`infected`
  ground-truth label. Train it with `backend/train_numeric_ann.py`. It is
  loaded automatically from `backend/numeric_ann_weights.json` when a trained
  ten-feature checkpoint exists; `PLANT_NUMERIC_ANN_WEIGHTS` can override that
  path. Weather must also be available for inference.
- **Fuzzy logic** is the deterministic rule system in
  `backend/fuzzy_logic.py`; it does not learn from a dataset. It uses
  membership levels for green and dry area and a weather-risk rule for blight
  to produce a score and severity when weather is available.
- **MobileNetV2** is the trained image classifier. It is a different model from
  the optional numeric ANN; training code and checkpoints are identified below.

### Input and output locations

| Data | Location / format | Purpose |
|---|---|---|
| Web photo input | JPEG, PNG, or WebP selected/captured in the scan page | Sent to the API as multipart field `image` |
| Image-model training input | `PlantVillage/train/<class>/` and `PlantVillage/val/<class>/` | Folder names define MobileNetV2's image classes |
| Numeric-ANN training input | CSV with seven image features, three weather features, plus `label` | Independently labeled numeric health measurements |
| Web history output | Firestore collection `monitoring_records`, field `user_id` | Web history is isolated to the signed-in user |
| API history output | `outputsApp/monitoring_api.sqlite3` and `outputsApp/monitoring_api.csv` | Local backend history; also exposed through API history endpoints |
| API segmentation output | `outputsApp/masks/` | PNG masks from successful backend analyses |
| Model evaluation output | `outputsApp/*metrics.json` (when using `--report`) | Training/evaluation metrics, not individual web scans |
| Numeric ANN model output | `backend/numeric_ann_weights.json` by default | Loaded automatically if a trained checkpoint exists |
| Historical weather input | `backend/climate_data_idn.csv/` | BMKG station records used when Open-Meteo is unavailable |

The web result, including its care summary, is saved to Firestore by the Flutter app. Backend CSV/SQLite/mask
files are on the machine running FastAPI and are separate from Firestore. The
`outputsApp/` directory is retained as the common output root; generated files
are grouped there by purpose without moving existing project data.

## Backend

Python 3.13 is supported. Install dependencies and launch the API from the repository root:

```sh
python -m pip install -r backend/requirements.txt
PLANT_REQUIRE_AUTH=false uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

`POST /api/v1/analyze-plant` accepts a multipart `image` plus optional `plant_id`, `location`, latitude/longitude, HSV minima/range, and odd morphology `kernel_size`. The API returns HTTP 422 with `code: "ood_image"` when the prediction is `Background_or_Invalid`, is outside the Corn/Potato/Tomato classes, or has confidence below 70%. The softmax threshold is `OOD_CONFIDENCE_THRESHOLD = 0.70`; inference confidence is serialized as a percentage. The response for accepted predictions includes segmentation ratios, prediction/confidence, weather-aware fuzzy score, structured care recommendations, and a base64 mask.

Monitoring records are stored in SQLite at `outputsApp/monitoring_api.sqlite3`, appended to `outputsApp/monitoring_api.csv`, and their masks are saved in `outputsApp/masks/`. `GET /api/v1/history` returns records and `GET /api/v1/history/export.csv` downloads a CSV export. Interactive API docs are available at `/docs`.

Run backend logic tests from the repository root with `python -m unittest backend.tests.test_logic`.

For the complete local web tutorial—including starting both services, signing in,
trying a scan, and troubleshooting model prerequisites—see
[`web/README.md`](web/README.md#tutorial-menjalankan-web-secara-lokal).

### PlantVillage training and PBL metrics

Prepare the combined dataset from the repository root. First inspect the plan;
the default command is a dry run. Passing `--apply` moves labeled images from
`DataSet/Background_or_Invalid` and `DataSet/PlantDoc Classification` into the
matching `PlantVillage/train/` and `PlantVillage/val/` class folders, then
removes folders outside those crop classes and the OOD class:

```sh
python -m backend.prepare_dataset
python -m backend.prepare_dataset --apply
```

PlantDoc's `train/` goes into `PlantVillage/train/`, and its `test/` goes into
`PlantVillage/val/`. Its generic `Tomato_leaf` class is labeled
`Tomato___Unspecified_leaf` rather than incorrectly marking it healthy. The
background cat/dog training and test sets become the corresponding OOD class.

The MobileNetV2 trainer filters `PlantVillage/train/` and `PlantVillage/val/`
to the three supported crops and the required OOD/background class. The two
directories must contain the same selected class folders, with images for each
class. Before evaluation, the trainer uses SHA-256 to
exclude validation files whose exact content also exists in `train/`; it does
not delete or modify the original dataset. By default, the trainer detects
CUDA, Apple Silicon MPS, or CPU, applies class-balanced loss, and saves the
best checkpoint by validation macro F1:

```sh
python -m backend.train_plant_model \
  --dataset-root PlantVillage \
  --epochs 5 \
  --patience 0 \
  --output backend/model_daun_plantvillage_full_train.pth \
  --report outputsApp/pbl_plantvillage_metrics.json \
  --save-best-each-epoch
```

Training keeps only `Corn_(maize)___*`, `Potato___*`, `Tomato___*`, and
`Background_or_Invalid`. The background class must have labeled images in both
`PlantVillage/train/Background_or_Invalid/` and
`PlantVillage/val/Background_or_Invalid/`; training stops if they are missing.
An earlier checkpoint's MobileNetV2 backbone is reused when present, but its
old classifier head is reset because its output classes do not match. The
prepared dataset includes a labeled background/OOD class. The existing
38-class checkpoint is not compatible with this new class set; the API refuses
to load it rather than serving mismatched labels.

The command writes a neighboring `*.metrics.json` report with pre/post-filter
validation sizes, number of exact duplicates excluded, per-class
support/precision/recall/F1, aggregate metrics, confusion matrix, validation
loss and accuracy, validation confidence distribution around the configured
90% OOD threshold, device, and epoch history when training occurs. Re-evaluate an
existing checkpoint without training with the `--evaluate-only` flag. For an interrupted training run,
`--save-best-each-epoch` keeps the best completed-epoch checkpoint so it can
still be evaluated without restarting:

```sh
python -m backend.train_plant_model \
  --dataset-root PlantVillage \
  --evaluate-only \
  --output backend/model_daun_plantvillage_full_train.pth
```

#### Current 19-class checkpoint result

The current OOD-aware MobileNetV2 was fine-tuned for three epochs from the
compatible feature backbone in the previous checkpoint, with a newly initialized
19-class head and the latest OOD examples. After excluding 10 byte-identical
validation files that also occur in train, the selected checkpoint evaluated
7,014 images. It recorded 98.66% accuracy, 94.26% macro precision, 95.86%
macro recall, 94.88% macro F1, and 0.04855 validation loss. The stored 60%
confidence distribution is historical: 58/7,014 (0.83%) predictions were below
that threshold. The trainer's confidence distribution is historical; backend
inference uses a separate 70% OOD threshold.
The best checkpoint is `backend/model_daun_plantvillage_full_train.pth`;
`outputsApp/pbl_plantvillage_metrics.json` contains its metrics, per-class
results, and confidence distribution. The separate
`outputsApp/pbl_baseline_metrics.json` is an earlier baseline report and is
not the active model's performance report.

These are results on the available validation split, not a substitute for a
separate field-photo test set. Exact SHA-256 filtering does not detect
near-duplicate images. The OOD class currently consists mainly of cats/dogs,
so performance on faces and other unrepresented non-leaf inputs needs its own
held-out evaluation. Segmentation and Sugeno outputs are rule-based
measurements, not supervised disease-classification metrics; the numeric ANN
has no valid performance score until an independently labeled
numeric-feature dataset is supplied.

The optional numeric ANN is trained separately from a CSV with seven image
features plus `temperature_c`, `humidity_pct`, `precipitation_mm`, and a
ground-truth `healthy`, `dry`, or `infected` label. Its trainer
uses a stratified holdout, training-only feature normalization, mini-batches,
Adam, L2 regularization, and validation early stopping:

```sh
python -m backend.train_numeric_ann labeled_features.csv \
  --output backend/numeric_ann_weights.json
```

PlantVillage disease-folder names alone are not labels for numeric health
features; do not generate or report ANN metrics without independently labeled
feature rows. When a trained checkpoint exists at
`backend/numeric_ann_weights.json`, the API loads it automatically; use
`PLANT_NUMERIC_ANN_WEIGHTS` only to select a different path. The image segmentation combines HSV thresholds with deterministic,
sampled CIE-Lab K-Means and bounded-memory cluster assignment. Sugeno scoring
uses bounded ratios and explicit left/right shoulder membership functions.

## Security and production deployment

The API is protected by Firebase ID tokens by default (`PLANT_REQUIRE_AUTH=true`).
The Flutter client attaches the signed-in user's token to each analysis request;
the API verifies it with Firebase Admin, stores its local history by user ID, and
does not expose another user's backend history. Keep the Firebase Admin service
account **only** on the API server, preferably through `GOOGLE_APPLICATION_CREDENTIALS`.
`PLANT_REQUIRE_AUTH=false` is for a local demo only and must never be used on a
public server. The Firestore rules permit only owner-scoped, immutable history
records and impose a smaller mask limit to stay below Firestore's document limit.

To publish the web app at `https://erytheia.id`:

1. In Firebase Authentication, enable Email/Password, require/monitor verified
   email accounts, and add `erytheia.id` plus `www.erytheia.id` to Authorized
   domains. Deploy `web/firestore.rules` before going live.
2. Deploy FastAPI on a Python-capable server (for example a Hostinger VPS) as
   `https://api.erytheia.id`. Set `PLANT_ALLOWED_ORIGINS=https://erytheia.id,https://www.erytheia.id`, keep `PLANT_REQUIRE_AUTH=true`, and configure the server-only Firebase Admin credentials.
3. Build the static Flutter site with:

   ```sh
   cd web
   flutter build web --release --dart-define=PLANT_API_URL=https://api.erytheia.id
   ```

   Upload the **contents** of `web/build/web/` to the `public_html` directory
   for `erytheia.id`, then enable HTTPS. If DNS is managed at Hostinger, create
   the `api` subdomain there; otherwise create its A/CNAME record at the DNS
   provider. Hostinger documents that external subdomains can be pointed using
   an A record (IP) or CNAME (hostname), and DNS propagation can take up to 24
   hours.

The existing model recognises PlantVillage classes and gives care guidance only
for tomato and potato. Its output is a photo-based screening result, not a
nutrient assay: do not claim that a leaf needs “protein” or a specific vitamin
solely from this image. A low-confidence image intentionally receives a
verification-first recommendation. For reliable field use, collect balanced
tomato/potato photos in your own growing conditions, label them with agronomy
ground truth, reserve an unseen field test set, and retrain/evaluate before
making treatment decisions.

## Intellectual-property readiness

The project now avoids personal watermark text in its UI and source. This does
not by itself guarantee HKI registration or legal clearance. Before filing,
prepare a dated source archive, a list of model/dataset/asset licences, evidence
of permission for third-party assets, and a clear statement of what is original.
PlantVillage and pretrained model components must be attributed and used under
their respective licences; consult an Indonesian HKI professional for the filing
requirements and ownership decision.

## Flutter mobile app

See [`mobile/README.md`](mobile/README.md) for Flutter setup, API URL configuration, and device permission notes. The mobile app uses Provider for state, SQLite for on-device monitoring history, and provides camera/gallery capture, adjustable segmentation parameters, mask previews, speech feedback, dashboard metrics/chart, and CSV/PDF sharing.
