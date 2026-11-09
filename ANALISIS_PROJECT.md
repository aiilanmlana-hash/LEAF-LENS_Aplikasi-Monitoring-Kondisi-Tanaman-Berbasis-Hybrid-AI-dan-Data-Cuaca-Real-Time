# Analisis Lengkap Smart Plant Monitoring & AI Detection

Dokumen ini merangkum struktur source code FastAPI dan Flutter Web yang
dilacak, alur data, algoritma, parameter training, cara memperoleh dataset,
hasil evaluasi, serta keterbatasan yang perlu dijelaskan saat presentasi.
Dataset, checkpoint model, output runtime, aplikasi mobile terpisah, dan skrip
eksperimen tidak disertakan dalam snapshot Git yang dibersihkan.

## 1. Ringkasan proyek

Proyek ini adalah aplikasi skrining kondisi daun dengan beberapa komponen yang
memiliki tugas berbeda:

1. **Flutter Web** menjadi antarmuka untuk login, memilih/mengambil foto,
   mengisi informasi tanaman/lokasi, melihat mask dan hasil, serta mengelola
   riwayat.
2. **FastAPI** menerima foto dari Flutter, memvalidasi request, menjalankan
   klasifikasi MobileNetV2 dan segmentasi citra, lalu menggabungkan hasil cuaca,
   fuzzy Sugeno, rekomendasi, serta penyimpanan.
3. **MobileNetV2** adalah classifier utama gambar. Backend dapat menggabungkan
   softmax-nya dengan EfficientNet-B0 yang dilatih terpisah; tanpa checkpoint
   sekunder yang valid, runtime tetap memakai MobileNetV2 saja.
4. **K-Means + HSV** adalah segmentasi warna berbasis piksel untuk mengukur
   proporsi area hijau dan kuning/cokelat. K-Means bukan classifier penyakit.
5. **Fuzzy Sugeno** adalah perhitungan berbasis aturan untuk skor kesehatan dan
   tingkat keparahan; ia bukan jaringan yang dilatih.
6. **NumericFeatureANN** adalah ANN kecil opsional untuk memprediksi
   `healthy`, `dry`, atau `infected` dari angka fitur citra dan cuaca. Model
   ini terpisah dari MobileNetV2 dan belum memiliki dataset CSV berlabel yang
   dibutuhkan untuk training.

Jadi saat mempresentasikan kata “AI”, jelaskan bahwa bagian yang mempelajari
label gambar adalah MobileNetV2. K-Means mengelompokkan warna, fuzzy menerapkan
aturan, dan ANN numerik adalah jalur tambahan yang hanya aktif bila checkpoint
ANN tersedia.

## 2. Batas bukti tentang sejarah pembuatan

Repository hanya memiliki satu commit Git, yaitu `Initial commit: Smart Plant
Monitoring System by Ahmad Maulana (E41241323)`. Tidak ada rangkaian commit yang
merekam urutan setiap perubahan, tanggal pengambilan dataset, atau URL dataset
Kaggle. Tidak ditemukan metadata Kaggle atau notebook download pada file yang
dilacak. Maka riwayat persis dan dataset Kaggle yang tepat tidak dapat
ditentukan hanya dari repository.

Yang dapat disimpulkan dari source:

- Ada script eksperimen awal: `train.py`, `detect_webcam.py`,
  `detect_webcam_praktikum.py`, dan `app_praktikum_streamlit.py`.
- Snapshot repository yang dibersihkan melacak backend FastAPI dan Flutter
  Web sebagai aplikasi utama. Versi sebelumnya juga memuat aplikasi mobile
  terpisah, tetapi source mobile tidak termasuk snapshot ini.
- Kebutuhan pengembangan berikutnya menambahkan segmentasi K-Means berbantuan
  HSV, fuzzy Sugeno, cuaca, OOD, rekomendasi, autentikasi, dan riwayat.

Urutan pada daftar ini adalah rekonstruksi arsitektur dari isi file dan
kebutuhan proyek, bukan tanggal kronologis yang dibuktikan oleh Git.

## 3. Peta folder dan tanggung jawab file

### Backend Python

| File | Tanggung jawab |
|---|---|
| `backend/main.py` | FastAPI routes, memuat MobileNetV2, validasi gambar/prediksi, mengorkestrasi segmentasi → OOD guard → cuaca/fuzzy/ANN/rekomendasi, dan menyimpan hasil API. |
| `backend/segmentation.py` | K-Means warna pada ruang Lab, filter HSV, morfologi, penghitungan rasio hijau/kering, serta fitur rata-rata HSV. |
| `backend/fuzzy_logic.py` | Membership functions, sembilan aturan Sugeno, pengurangan skor risiko blight berbasis cuaca, dan severity. |
| `backend/numeric_ann.py` | ANN numerik NumPy: normalisasi, forward pass, backpropagation, Adam, prediksi, save/load checkpoint. |
| `backend/generate_ann_dataset.py` | Membuat CSV 500–1000 baris sintetis dan deterministik untuk smoke test pelatihan ANN; bukan data lapangan. |
| `backend/train_numeric_ann.py` | Membaca CSV berlabel, membagi data stratified, melatih NumericFeatureANN, dan menyimpan metrik. |
| `backend/train_plant_model.py` | Filter kelas, transformasi gambar, fine-tuning/evaluasi MobileNetV2, metrik, dan checkpoint berisi bobot + nama kelas. |
| `backend/prepare_dataset.py` | Dry-run dan pemindahan gambar Background/OOD serta PlantDoc ke split PlantVillage; kelas non-target dapat dihapus saat `--apply`. |
| `backend/weather.py` | Open-Meteo dan fallback rerata bulanan stasiun BMKG terdekat. |
| `backend/care_recommendations.py` | Rekomendasi penanganan berdasarkan tanaman, penyakit, confidence, kondisi, dan cuaca. |
| `backend/auth.py` | Verifikasi Firebase ID token; mode tanpa autentikasi hanya untuk demo lokal. |
| `backend/compact_context.py` | Membuat JSON ringkas deterministik dari hasil, bukan mengirim prompt ke LLM. |
| `backend/tests/test_logic.py` | Tes untuk fuzzy, cuaca, API/OOD, dataset, trainer, ANN, dan validasi lainnya. |
| `backend/requirements.txt` | Dependensi FastAPI, OpenCV, PyTorch, Pillow, Firebase Admin, dan lainnya. |

### Flutter Web

| Area | Tanggung jawab |
|---|---|
| `web/lib/main.dart` | Inisialisasi Firebase, gerbang autentikasi, shell/navigation dashboard-scan-riwayat. |
| `web/lib/screens/auth_screen.dart` | Daftar/masuk/verifikasi email dan autentikasi. |
| `web/lib/screens/dashboard_screen.dart` | Ringkasan monitoring dan pintasan ke analisis. |
| `web/lib/screens/scan_screen.dart` | Kamera/upload, kontrol parameter segmentasi, request API, hasil/mask, rekomendasi, dan penyimpanan. |
| `web/lib/screens/history_screen.dart` | Menampilkan serta mengelola riwayat pengguna. |
| `web/lib/services/plant_api_service.dart` | Request multipart ke FastAPI, token, parsing respons/error. |
| `web/lib/services/image_processing_service.dart` | HSV lokal untuk preview/fallback; kode ini tidak melakukan K-Means. |
| `web/lib/services/monitoring_repository.dart` | Menulis/membaca dokumen Firestore milik pengguna yang sedang login. |
| `web/lib/models/plant_analysis.dart` | Bentuk data hasil analisis yang dipakai UI. |
| `web/lib/theme/`, `web/lib/widgets/` | Tema visual, backdrop, permukaan glass, ilustrasi, animasi. |
| `web/test/` | Tes widget, image processing, dan kontrak request API. |
| `web/firebase.json`, `web/firestore.rules`, `web/firestore.indexes.json` | Konfigurasi Firebase Web, aturan, dan indeks Firestore. |

### Artefak yang tidak dilacak

Skrip eksperimen lama (`train.py`, `detect_webcam*.py`, dan
`app_praktikum_streamlit.py`), aplikasi mobile terpisah, dataset PlantVillage,
checkpoint `.pth`/`.h5`, dan `outputsApp/` runtime sengaja dikeluarkan dari Git.
`backend/train_plant_model.py` tetap menjadi trainer utama. Untuk menggunakan
inference tanpa dataset, backend mengambil urutan label dari metadata `classes`
pada checkpoint; dataset tetap diperlukan jika model hendak dilatih ulang.
Workflow CI yang dipertahankan hanya memeriksa aplikasi di `web/`.

## 4. Dataset dan cara mengambil dataset dari Kaggle

### Yang benar-benar ada pada dataset saat ini

Susunan classifier aktif adalah `PlantVillage/train/<nama-kelas>/` dan
`PlantVillage/val/<nama-kelas>/`. Nama folder kelas menjadi label classifier.
Trainer terakhir melihat:

- 29.028 gambar training dalam 19 kelas.
- 7.024 gambar validation yang dikenali sebagai gambar oleh ImageFolder.
- 10 gambar validation yang byte-nya identik dengan train dikeluarkan dari
  evaluasi, sehingga evaluasi akhir memakai 7.014 gambar.
- 18 kelas daun tanaman: Corn, Potato, Tomato; ditambah
  `Background_or_Invalid`.
- Tanaman selain tiga tersebut tidak dimasukkan pada model ini.

Dataset gabungan saat ini:

| Kelas | Train | Validation (setelah 10 duplikat dikeluarkan) |
|---|---:|---:|
| `Background_or_Invalid` | 8.165 | 2.063 |
| Corn Cercospora/Gray leaf spot | 473 | 106 |
| Corn Common rust | 1.060 | 249 |
| Corn Northern Leaf Blight | 970 | 207 |
| Corn healthy | 929 | 233 |
| Potato Early blight | 957 | 214 |
| Potato Late blight | 1.000 | 207 |
| Potato healthy | 121 | 31 |
| Tomato Bacterial spot | 1.803 | 433 |
| Tomato Early blight | 879 | 209 |
| Tomato Late blight | 1.628 | 389 |
| Tomato Leaf Mold | 846 | 197 |
| Tomato Septoria leaf spot | 1.562 | 366 |
| Tomato Spider mites | 1.343 | 335 |
| Tomato Target Spot | 1.123 | 281 |
| Tomato Yellow Leaf Curl Virus | 4.509 | 1.086 |
| Tomato mosaic virus | 343 | 84 |
| Tomato unspecified leaf | 44 | 8 |
| Tomato healthy | 1.273 | 316 |

Kelas `Background_or_Invalid` berasal dari folder cats/dogs yang dipindahkan
dari `DataSet/Background_or_Invalid/training_set` dan `test_set`. PlantDoc
digabungkan berdasarkan split `train` dan `test` ke target `train` dan `val`.
Contoh wajah dan objek COCO128 yang baru ditambahkan pengguna juga berada di
kelas OOD; 19 kelas yang dipakai tetap 18 kelas tanaman dan satu kelas OOD.
Kelas generic `Tomato_leaf` dipetakan sebagai
`Tomato___Unspecified_leaf`, bukan dianggap sehat. `prepare_dataset.py`
menyimpan gambar ke subfolder `PlantDoc/...` supaya file bernama sama tidak
menimpa file lain.

Perintah persiapan dataset pada dasarnya adalah:

```sh
python -m backend.prepare_dataset          # hanya melihat rencana (dry-run)
python -m backend.prepare_dataset --apply # benar-benar memindahkan/menghapus
```

`--apply` mengubah isi folder data: memindahkan gambar sumber dan menghapus
folder kelas di `PlantVillage/train`/`val` yang tidak diawali prefix Corn,
Potato, atau Tomato dan bukan kelas OOD. Buat salinan/backup data sebelum
mengulang langkah tersebut. Data yang dipindahkan pada eksekusi terakhir
berada di struktur PlantVillage, bukan lagi pada sumber DataSet.

### Panduan mengambil dataset dari Kaggle

Repository ini tidak mencatat URL/slug, pemilik, versi, atau lisensi dataset
Kaggle yang dipakai. Jadi jangan menyebut satu URL tertentu sebagai sumber
historis proyek tanpa bukti. Untuk mengambil ulang dataset secara bertanggung
jawab:

1. Masuk ke Kaggle, cari dataset yang diperlukan (misalnya PlantVillage,
   PlantDoc, atau dataset non-daun untuk kelas OOD), buka halaman dataset, lalu
   periksa pemilik, deskripsi, tanggal/versi, struktur folder, dan lisensi.
2. Unduh ZIP lewat tombol **Download** atau gunakan Kaggle CLI. Untuk CLI,
   pasang tool sesuai petunjuk Kaggle, buat API token dari pengaturan akun,
   lalu simpan token di lokasi konfigurasi pribadi di luar repository.
   Jangan unggah `kaggle.json`, token, atau kredensial ke GitHub.
3. Contoh CLI dengan placeholder—ganti `OWNER/DATASET-SLUG` memakai slug
   persis dari URL halaman Kaggle:

   ```sh
   kaggle datasets download -d OWNER/DATASET-SLUG \
     -p DataSet/download --unzip
   ```

4. Periksa struktur hasil ekstrak sebelum menyalin: kelas harus berada dalam
   folder label, bukan semua gambar bercampur. Pastikan dataset menyediakan
   split train/test yang jelas atau buat split deterministik sebelum training.
5. Jangan menaruh salinan gambar yang sama ke train dan validation. Trainer
   sekarang menghapus dari evaluasi file validation yang memiliki SHA-256 sama
   persis dengan file train, tetapi tidak dapat mengidentifikasi foto yang sama
   setelah resize/crop/kompresi.
6. Pertahankan lisensi/atribusi dataset dan catat URL, pemilik, versi/tanggal
   unduh, jumlah gambar per kelas, serta cara split di catatan eksperimen.
7. Untuk OOD, kumpulkan objek yang benar-benar mewakili input yang akan ditolak:
   wajah, hewan, pemandangan, benda, teks, daun jenis tanaman lain, gambar
   kosong/buram, dan kondisi pencahayaan berbeda. Pastikan kelas itu memang
   berlabel non-daun; jangan menebak label.

Cats/dogs adalah contoh negatif yang tersedia sekarang, tetapi belum tentu
mewakili semua objek di luar distribusi. Kualitas OOD perlu diuji dengan set
foto non-daun yang terpisah dan beragam.

## 5. Alur runtime dari klik pengguna sampai hasil

### Langkah frontend

1. `web/lib/main.dart` menginisialisasi Firebase.
2. Authentication gate memutuskan apakah menampilkan login atau aplikasi.
3. Pengguna membuka halaman analisis lalu mengambil foto dari kamera atau
   memilih file. Foto kamera depan dapat dikoreksi mirror-nya.
4. Flutter mengirim gambar dan parameter melalui
   `PlantApiService.classify()` sebagai multipart ke
   `POST /api/v1/analyze-plant`. Token Firebase disertakan jika pengguna login.
5. Jika API mengembalikan `ood_image`, UI menampilkan peringatan dan tidak
   menjadikan foto itu sebagai hasil analisis yang disimpan.
6. Jika API berhasil, Flutter memakai mask dan rasio dari backend untuk kartu
   hasil, cuaca, rekomendasi dan riwayat Firestore. Jika API gagal karena
   jaringan/kegagalan lain, browser dapat menghitung preview HSV lokal; jalur
   lokal ini bukan prediksi MobileNetV2 dan bukan fuzzy Sugeno backend.

### Langkah backend

1. FastAPI memverifikasi token Firebase kecuali mode demo lokal secara eksplisit
   menonaktifkan autentikasi.
2. Validasi request membatasi ukuran file menjadi 10 MB, memeriksa format gambar
   JPEG/PNG/WebP, dimensi maksimum 25 juta piksel, koordinat, parameter HSV,
   ID, serta ukuran kernel.
3. Gambar dikonversi ke BGR dan optional horizontal flip diterapkan.
4. MobileNetV2 mengeluarkan logits. Jika checkpoint EfficientNet-B0 yang telah
   dilatih tersedia, softmax kedua model dirata-ratakan dengan bobot 0.60 dan
   0.40; jika tidak, sistem secara eksplisit hanya memakai MobileNetV2.
   Confidence maksimum classifier (konsensus bila model kedua aktif) dipakai
   untuk keputusan.
5. Guardrail menolak kelas `Background_or_Invalid`, kelas di luar target,
   confidence non-finite, atau confidence **di bawah 70%**. Penolakan terjadi
   sebelum segmentasi backend, fuzzy, rekomendasi dan penyimpanan.
6. Untuk prediksi yang lolos, backend menjalankan K-Means/HSV segmentation,
   memperoleh rasio hijau/kering, kemudian mencoba mengambil cuaca jika
   koordinat ada.
7. Rasio dan opsional cuaca diberikan ke fuzzy Sugeno. Fitur citra/cuaca juga
   menjadi input ANN numerik hanya bila checkpoint ANN 10-fitur dikonfigurasi.
8. Backend membuat rekomendasi, menyimpan record lokal dan mask, lalu
   mengirim JSON hasil + mask base64 ke Flutter.

### Multi-Stage Hybrid Pipeline Validation dan Orisinalitas Alur

Orisinalitas yang dideskripsikan di sini adalah susunan dan integrasi modul
yang dapat diverifikasi dari source, bukan klaim bahwa setiap algoritma dasar
baru atau bahwa kebaruan paten telah terbukti.

| Tahap pipeline | Aturan alur dalam implementasi | Batas bukti saat ini |
|---|---|---|
| Dual-CNN consensus | MobileNetV2 dan checkpoint EfficientNet-B0 opsional menghasilkan probabilitas softmax yang dirata-ratakan 0.60/0.40. | Belum ada checkpoint EfficientNet-B0 yang disediakan; hasil uji/angka yang ada hanya untuk MobileNetV2. |
| OOD gate | Tolak kelas OOD/non-target dan confidence consensus di bawah 0.70 sebelum segmentasi atau persistensi. | Ambang adalah guardrail softmax, bukan jaminan semua non-daun tertolak. |
| Dual-color mask | K-Means Lab memilih kelompok warna, lalu ambang HSV terpisah membentuk area hijau dan kering. | Ini pengukuran warna piksel, bukan deteksi semantik daun. |
| Weather-weighted Sugeno | Sugeno menggabungkan rasio area; metadata sumber cuaca memodulasi pengaruh risiko penyakit. | Bobot sumber adalah heuristik provenance, bukan probabilitas cuaca yang terkalibrasi. |
| Decision-tree triage | Kelas penyakit, rasio hijau/kering, skor fuzzy, suhu, dan kelembapan memilih cabang verifikasi/risiko/tindakan. | Saran merupakan skrining awal, bukan diagnosis atau resep perlakuan. |

### Bentuk input dan output

- **Input utama:** foto daun; plant ID dan lokasi teks; latitude/longitude
  opsional; parameter HSV dan kernel.
- **Output klasifikasi:** nama kelas, tanaman, penyakit, dan confidence.
- **Output segmentasi:** mask hitam/hijau/kuning-cokelat, rasio hijau dan kering.
- **Output analisis:** health score/severity fuzzy, cuaca bila tersedia,
  rekomendasi prioritas/organik/kimiawi dan dampak penundaan, hasil ANN bila
  tersedia.
- **Output penolakan OOD:** HTTP 422 dengan `detail.status = "error"`,
  `detail.code = "ood_image"`, dan pesan bahwa objek bukan daun Corn, Potato,
  atau Tomato yang valid.

## 6. Classifier CNN dan ensemble bersyarat

MobileNetV2 tetap menjadi model default dan merupakan satu-satunya checkpoint
yang tersedia dalam repository ini. Jika checkpoint EfficientNet-B0 yang telah
ditraining pada daftar kelas sama ditentukan melalui
`PLANT_SECONDARY_MODEL_PATH`, API menjalankan kedua model pada tensor masukan
yang sama dan menghitung rata-rata probabilitas softmax berbobot 0.60 dan
0.40. Checkpoint sekunder yang hilang atau tidak valid tidak menghasilkan
fallback diam-diam: tanpa konfigurasi API memakai MobileNetV2 saja; bila
path dikonfigurasi tetapi checkpoint tidak valid, startup/inferensi model
melaporkan layanan tidak tersedia.

### Cara model mengubah gambar menjadi kelas

MobileNetV2 menerima tensor gambar berukuran 256 × 256 dengan tiga kanal RGB.
Nilai kanal dinormalisasi memakai mean ImageNet `[0.485, 0.456, 0.406]` dan
standard deviation `[0.229, 0.224, 0.225]`.

Secara ringkas:

```text
gambar -> resize/normalize -> MobileNetV2 -> logits per kelas
       -> softmax -> probabilitas -> kelas probabilitas tertinggi + confidence
```

MobileNetV2 adalah CNN berbasis depthwise separable convolution dan inverted
residual blocks. Detail blok internal berasal dari arsitektur torchvision
MobileNetV2; proyek mengubah layer classifier terakhir agar jumlah output
sesuai jumlah kelas dataset.

EfficientNet-B0 dapat dilatih melalui `backend.train_plant_model` dengan
`--architecture efficientnet_b0` dan output checkpoint terpisah. Evaluasi
checkpoint itu dan ensemble harus dilakukan pada data held-out sebelum
mengaktifkannya atau melaporkan metrik ensemble. Bobot ensemble 0.60/0.40
adalah bobot probabilitas yang ditetapkan, bukan hasil optimasi empiris.

### Kenapa memakai bobot awal (transfer learning)

Trainer mengambil bobot backbone `features.*` dari checkpoint MobileNetV2
lama jika tersedia, lalu membuat ulang classifier head 19 kelas. Hal ini
penting karena urutan/daftar kelas checkpoint lama 38 kelas tidak cocok dengan
dataset sekarang. Bobot fitur generik dapat menjadi titik awal, tetapi bobot
head lama tidak boleh dipakai untuk mengartikan kelas baru.

### Pengaturan training yang benar-benar digunakan

| Parameter | Nilai pada training terakhir | Arti |
|---|---:|---|
| Arsitektur | MobileNetV2 | Backbone classifier citra. |
| Input | 256 × 256 RGB | Ukuran seragam batch; transform `Resize((256,256))` merentangkan gambar ke kotak tersebut, jadi aspek rasio tidak dipertahankan. |
| Epoch | 3 | Satu epoch berarti seluruh 29.028 contoh train dikunjungi satu kali. |
| Batch size | 32 | 908 batch/epoch (`ceil(29.028 / 32)`); 2.724 batch untuk 3 epoch. |
| Optimizer | AdamW | Update bobot dengan adaptive moments dan weight decay. |
| Learning rate | 0.0001 | Langkah update relatif kecil untuk fine-tuning backbone. |
| Weight decay | 0.0001 | Regularisasi bobot agar model tidak terlalu menyesuaikan training. |
| Loss | Weighted Cross Entropy | Bobot kelas berbanding terbalik dengan akar jumlah contoh; mengurangi dominasi kelas besar tanpa inverse-frequency ekstrem. |
| Augmentation train | Flip horizontal, rotasi ±10°, brightness/contrast/saturation ±20%, grayscale acak p=0,1 | Memvariasikan pencahayaan, warna, dan saturasi tanpa mengubah label kelas. |
| Validation transform | Resize, tensor, ImageNet normalize | Tanpa augmentasi acak agar evaluasi konsisten. |
| Seed | 42 | Mengendalikan urutan/random generator sejauh backend perangkat mendukung. |
| Device | Apple Silicon MPS | Perangkat training yang tercatat pada report terakhir. |
| Checkpoint selection | Macro F1 validation tertinggi | Menyimpan state terbaik selama epoch. |
| Early stopping | Dinonaktifkan (`patience=0`) | Semua 3 epoch diminta dijalankan. |

**Mengapa resize 256?** Model memerlukan tensor dengan ukuran konsisten.
Ukuran lebih besar mempertahankan lebih banyak detail gejala, tetapi menaikkan
RAM/VRAM dan waktu komputasi. Ukuran 256 adalah pilihan konfigurasi proyek,
bukan angka yang dibuktikan paling optimal melalui eksperimen perbandingan.
Versi eksperimen lama menggunakan 128 × 128; pipeline backend dan classifier
checkpoint baru memakai 256 × 256. Bila mengganti ukuran, evaluasi ulang
validation dan cocokkan transform inference dengan transform training.

**Mengapa 3 epoch?** Ini adalah budget eksperimen fine-tuning yang dipilih,
bukan angka universal atau kesimpulan matematis. Loss training dan metrik
validation harus dipantau; tambah epoch hanya bila metrik pada data yang benar-
benar belum pernah dilihat masih membaik. Epoch yang lebih banyak juga dapat
menyebabkan overfitting. Trainer memilih checkpoint dengan macro F1 tertinggi,
bukan otomatis epoch terakhir.

### Hasil training terakhir

Hasil dicatat di `outputsApp/pbl_plantvillage_metrics.json`:

- Best epoch: **1** (checkpoint dipilih berdasarkan macro F1, bukan loss saja)
- Validation loss: **0.04855**
- Validation accuracy: **98.66%**
- Macro precision: **94.26%**
- Macro recall: **95.86%**
- Macro F1: **94.88%**
- Validation confidence rata-rata: **98.70%**
- Threshold OOD inference saat ini: **70%**.
- Distribusi confidence dalam laporan arsip dihitung pada evaluasi terdahulu;
   angka tersebut bukan hasil pengujian ensemble dan tidak mengubah threshold
   runtime saat ini.
- Hasil kelas `Background_or_Invalid`: precision, recall, dan F1 masing-masing
  **99.95%** pada 2.063 sampel validation.
- Checkpoint: `backend/model_daun_plantvillage_full_train.pth`
- Kelas model tersimpan bersama state dict dalam checkpoint agar loader dapat
  mencocokkan urutan kelas.

Accuracy tinggi tidak membuktikan model aman untuk setiap foto kamera. Ini
adalah evaluasi pada split dataset yang tersedia, bukan hasil test lapangan
mandiri. Confidence 99% juga bukan jaminan probabilitas benar 99%; softmax
neural network dapat overconfident pada objek yang tidak pernah dilatih.

Contoh variasi kinerja per kelas menunjukkan perlunya melihat selain accuracy:

| Kelas | Support validation | Recall | F1 |
|---|---:|---:|---:|
| Background/OOD | 2.063 | 99.95% | 99.95% |
| Corn Cercospora/Gray leaf spot | 106 | 93.40% | 88.39% |
| Potato healthy | 31 | 100% | 100% |
| Tomato unspecified leaf | 8 | 62.50% | 47.62% |
| Tomato healthy | 316 | 100% | 100% |

`Tomato___Unspecified_leaf` hanya memiliki 8 foto validation, sehingga angka
kelas itu sangat tidak pasti. Set OOD kini juga berisi contoh wajah dan objek
COCO128, tetapi masih belum mencakup semua jenis non-daun atau variasi kamera.
Sampel lapangan dan OOD yang terpisah tetap diperlukan sebelum mengklaim
performa generalisasi.

## 7. Segmentasi K-Means + HSV

Implementasi backend ada di `backend/segmentation.py`.

### Tahapan segmentasi

1. Citra BGR di-resize agar sisi terpanjang paling besar 640 piksel. Citra
   kecil tidak diperbesar.
2. Citra diubah menjadi HSV dan CIE-Lab. HSV cocok untuk aturan rentang warna;
   Lab digunakan untuk mengelompokkan warna berdasarkan jarak yang lebih
   mendekati persepsi.
3. Warna piksel Lab diambil sampelnya dengan stride agar tidak lebih dari
   sekitar 20.000 sample untuk K-Means.
4. `cv2.kmeans` mencari paling banyak 3 pusat warna, K-Means++,
   maksimal 25 iterasi, epsilon 0.8, dua percobaan, seed OpenCV 7.
5. Semua piksel (bukan hanya sample) diberi label cluster berdasarkan jarak
   Euclidean kuadrat terdekat ke pusat Lab.
6. Pusat cluster dikonversi kembali ke HSV. Cluster baru layak sebagai hijau
   jika pusat memenuhi H 25–95, S ≥35, V ≥30; dry jika memenuhi H 15–30,
   S ≥40, V ≥40.
7. Mask HSV per piksel di-intersect dengan cluster yang layak. Artinya
   cluster membantu menyingkirkan warna yang tidak relevan, sedangkan mask HSV
   mempertahankan batas warna piksel.
8. Morphological opening membuang bintik kecil; closing mengisi celah kecil.
   Kernel default 5 × 5, parameter harus ganjil.
9. Komponen terhubung di bawah `max(3, 0.00002 × jumlah piksel)` dihapus.
   Area dry diprioritaskan bila tumpang tindih dengan mask green.
10. Rasio dihitung terhadap **semua piksel gambar kerja**, bukan hanya area
    daun: `jumlah piksel mask / total piksel × 100`.
11. Mask output memakai hitam untuk bukan target, abu-abu (150) untuk dry, dan
    putih (255) untuk green.

K-Means di sini **bukan** metode yang memberi nama penyakit. Ia juga tidak
menemukan “daun” secara semantik: kulit, kain hijau, atau objek dengan warna
serupa bisa lolos filter warna. Pengklasifikasi dan OOD guard adalah lapisan
berbeda.

Flutter menjalankan versi HSV sederhana hanya untuk preview/offline fallback.
Ia tidak menjalankan K-Means. Jika API gagal, UI lokal tidak boleh dianggap
sebagai prediksi penyakit oleh MobileNet.

## 8. Fuzzy Sugeno: aturan skor kesehatan

Fuzzy ada di `backend/fuzzy_logic.py`. Masukan utama adalah persentase hijau
dan dry dari segmentasi.

### Fuzzifikasi

Setiap nilai numerik diubah menjadi derajat keanggotaan 0–1:

- **Green low:** left shoulder penuh sampai 0%, turun linear dan menjadi 0 di
  20%.
- **Green medium:** segitiga dengan titik kiri 5%, puncak 30%, kanan 60%.
- **Green high:** right shoulder mulai naik di 25%, penuh pada 65%.
- **Dry low:** penuh sampai 0%, menjadi 0 di 12%.
- **Dry medium:** segitiga 3%–15%–35%.
- **Dry high:** mulai naik di 20%, penuh pada 50%.

Nilai rasio dipotong dulu ke rentang 0–100. Jika hijau <2% dan dry <3%, fungsi
menghasilkan skor 0 / `Tidak diketahui`.

### Sembilan aturan Sugeno zero-order

Kekuatan rule adalah minimum (AND) derajat membership green dan dry.
Konsekuen tiap rule adalah singleton konstan:

| Green | Dry | Nilai konsekuen |
|---|---|---:|
| high | low | 95 |
| medium | low | 78 |
| low | low | 52 |
| high | medium | 76 |
| medium | medium | 54 |
| low | medium | 32 |
| high | high | 48 |
| medium | high | 30 |
| low | high | 12 |

Defuzzifikasi Sugeno adalah rata-rata berbobot:

```text
health = Σ(kekuatan_rule × konsekuen_rule) / Σ(kekuatan_rule)
```

Contoh: bila beberapa aturan aktif bersamaan, aturan dengan membership lebih
kuat memberi pengaruh lebih besar pada skor. Skor dibatasi 0–100 dan dibulatkan
1 desimal. Label: ≥75 `Sehat`; ≥50 `Perlu perhatian`; selain itu `Kritis`.

### Penyesuaian cuaca

Cuaca hanya mengurangi skor jika:

- suhu, kelembapan, dan curah hujan semuanya tersedia; dan
- nama penyakit mengandung kata `blight`.

Membership cuaca: kelembapan naik dari 75% sampai penuh 90%; suhu hangat naik
dari 20°C sampai penuh 30°C; hujan naik dari 0 sampai penuh 10 mm. Kombinasi
risiko adalah maksimum dari `(kelembapan AND hangat)` dan `(kelembapan AND
hujan)`. Maksimum pengurangan 15 poin, proporsional membership risiko.
Ini adalah indikator faktor risiko cuaca, bukan diagnosis penyakit berdasarkan
cuaca.

Weather source utama Open-Meteo memiliki timeout 4 detik. Jika gagal, API
mencari stasiun BMKG terdekat memakai jarak Haversine dan rerata data untuk
bulan berjalan; dataset historis yang tersedia bertahun 2010–2020. Tanpa
koordinat, skor fuzzy berjalan hanya dari rasio citra.

## 9. ANN numerik: jalur opsional, bukan MobileNet

NumericFeatureANN adalah jaringan kecil NumPy, bukan MobileNetV2:

```text
fitur angka -> normalisasi -> Dense tanh (8 unit) -> Dense softmax (3 label)
```

Label output adalah `healthy`, `dry`, dan `infected`. Fitur yang diharapkan
trainer saat ini ada 10:

1. green ratio
2. dry ratio
3. MobileNet confidence
4. fuzzy health score
5. mean hue
6. mean saturation
7. mean value
8. temperature
9. humidity
10. precipitation

Training CSV harus berisi 10 kolom fitur itu dan kolom `label`. Trainer
melakukan stratified holdout default 20% dengan seed 17; normalisasi mean/std
dihitung hanya dari data train untuk menghindari kebocoran validation. Forward
pass memakai tanh dan softmax, loss cross-entropy, backpropagation,
mini-batch Adam (β1=0.9, β2=0.999), learning rate default 0.01, weight decay
0.0001, clipping gradient maksimum 5, maksimal 700 epoch, batch 32, dan
early-stopping patience 40.

Untuk runtime, API otomatis mencari `backend/numeric_ann_weights.json`;
`PLANT_NUMERIC_ANN_WEIGHTS` dapat dipakai untuk memilih file lain. API hanya
memberi prediksi ANN jika checkpoint input-nya cocok 10 fitur **dan** cuaca
tersedia. FastAPI memuat checkpoint saat startup dan mencatat hasil preload di
log. `backend/generate_ann_dataset.py` menyediakan 750 baris sampel sintetis
yang dapat dibuat ulang dengan seed; checkpoint sampel yang disimpan di
repository hanya untuk memverifikasi alur training/loading. Label sintetis
bukan ground truth dan metrik holdout-nya bukan akurasi lapangan. Untuk
evaluasi ilmiah atau penggunaan produksi, ganti CSV sampel dengan observasi
numerik yang dilabeli secara independen.

Jalankan sampel lokal dari root repository:

```sh
python backend/generate_ann_dataset.py --output backend/dataset_numeric.csv --rows 750 --seed 17
python backend/train_numeric_ann.py --dataset backend/dataset_numeric.csv \
  --output backend/numeric_ann_weights.json
```

Setelah trainer selesai, restart API agar bobot baru dimuat pada startup.
Trainer tetap mendukung path dataset sebagai argumen posisi untuk kompatibilitas
dengan perintah lama.

## 10. Mengapa foto wajah bisa salah diprediksi?

Ini sebab teknis yang penting untuk dibahas:

1. MobileNet classifier selalu memilih kelas dengan softmax tertinggi. Pada
   awalnya model hanya memiliki kelas tanaman; foto di luar kelas tetap bisa
   dipaksa menjadi kelas tanaman, misalnya Tomato Early blight.
2. K-Means/HSV tidak memverifikasi bahwa objek adalah daun. Ia hanya
   mengelompokkan dan memfilter warna.
3. Training OOD dengan cats/dogs membantu mengajarkan sebagian contoh negatif,
   tetapi tidak mencakup semua wajah, objek, kondisi cahaya, latar, blur, dan
   kamera.
4. Softmax confidence bukan probabilitas terkalibrasi bahwa objek berasal dari
   kelas yang benar.
5. Kartu hasil dapat berasal dari frontend/backend instance yang berbeda atau
   server lama jika port API tidak sama. Pastikan `PLANT_API_URL` menunjuk ke
   backend terbaru, restart FastAPI sesudah pergantian checkpoint/kode, dan
   lihat response request di browser/network/API log.

Di source backend saat ini, prediksi `Tomato___Early_blight` dengan 29.3%
seharusnya menghasilkan HTTP 422 sebelum segmentasi, fuzzy, rekomendasi dan
penyimpanan. Jadi tampilan hasil 29.3% bukan perilaku yang diharapkan dari
backend yang menjalankan source terbaru; periksa server/port dan versi
frontend. Runtime menolak confidence di bawah 70%; class `Background_or_Invalid`
dan kelas di luar target tetap ditolak tanpa memandang confidence.
Checkpoint terpasang saat analisis ini berhasil dimuat oleh loader backend
dengan 19 nama kelas yang sama dengan folder dataset.

### Batasan pengamanan dan cara membuktikan OOD

Threshold runtime 70% adalah guardrail, bukan jaminan matematis bahwa setiap foto
non-daun pasti ditolak. Confusion matrix dan accuracy validation saja tidak
menjawab pertanyaan “berapa wajah yang lolos sebagai daun?”. Buat OOD test set
terpisah dari training dan validasi berisi contoh dunia nyata, ukur:

- **OOD false acceptance rate:** proporsi foto non-daun yang justru lolos;
- **OOD rejection recall:** proporsi foto non-daun yang ditolak;
- **in-distribution rejection rate:** proporsi foto daun valid yang tertolak;
- confusion matrix khusus OOD vs daun, termasuk confidence histogram.

Validasi operating point 70% pada data terpisah yang mewakili input lapangan;
catat false acceptance dan false rejection sebelum mengubah parameter. Untuk
kebutuhan lebih kuat, pertimbangkan kalibrasi confidence atau detector OOD
terpisah dan validasi lapangan. Jangan menyebut 98.66% validation accuracy
sebagai akurasi OOD universal.

## 11. Penyimpanan dan keamanan data

- Flutter Web menyimpan hasil dan thumbnail mask ke Firestore pada koleksi
  `monitoring_records`, dengan `user_id` dari akun Firebase. Riwayat yang
  diminta dibatasi 100 terbaru.
- FastAPI juga menyimpan record di `outputsApp/monitoring_api.sqlite3`, append
  CSV ke `outputsApp/monitoring_api.csv`, dan mask PNG ke `outputsApp/masks/`.
  Ini penyimpanan di mesin tempat backend berjalan, terpisah dari Firestore.
- API default-nya membutuhkan Firebase bearer token dan memverifikasi email.
  `PLANT_REQUIRE_AUTH=false` hanya untuk demo lokal; jangan membuka mode itu ke
  internet. Firebase Admin credential hanya berada di server.
- Hasil foto/rekomendasi adalah skrining awal, bukan diagnosis lab atau resep
  pestisida. Bahan aktif/rekomendasi harus diverifikasi dengan label resmi,
  aturan setempat, dan ahli tanaman.

## 12. Cara menjalankan ulang dan memeriksa proyek

Dari root repository, aktifkan virtual environment lalu jalankan backend:

```sh
source .venv-api/bin/activate
PLANT_REQUIRE_AUTH=false python -m uvicorn backend.main:app \
  --reload --host 127.0.0.1 --port 8000
```

Terminal kedua:

```sh
cd web
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5001 \
  --dart-define=PLANT_API_URL=http://localhost:8000
```

Untuk validasi kode:

```sh
./.venv-api/bin/python -m unittest backend.tests.test_logic
cd web && flutter analyze && flutter test
```

Untuk evaluasi ulang checkpoint yang ada tanpa training:

```sh
cd <root-project>
source .venv-api/bin/activate
python -m backend.train_plant_model --evaluate-only \
  --output backend/model_daun_plantvillage_full_train.pth
```

## 13. Penjelasan singkat yang bisa disampaikan ke dosen

> “Foto dari Flutter dikirim ke FastAPI. Backend memakai MobileNetV2 dan bila
> checkpoint sekunder yang sudah divalidasi tersedia, EfficientNet-B0 untuk
> memilih penyakit daun dan confidence. Jika kelasnya Background/OOD atau
> confidence di bawah 70%, API menolak sebelum analisis lanjutan. Untuk hasil
> yang lolos, K-Means mengelompokkan warna Lab lalu HSV memfilter piksel hijau
> dan kering; persentase mask menjadi input aturan fuzzy Sugeno untuk skor
> kesehatan. Cuaca Open-Meteo atau fallback BMKG diberi bobot risiko berbeda
> menurut sumbernya. Pohon keputusan memadukan kelas, area segmen, skor, suhu,
> dan kelembapan menjadi prioritas tindakan. ANN numerik terpisah dan opsional; ia memerlukan
> CSV fitur berlabel dan checkpoint sendiri. Hasil ditampilkan di Flutter dan
> disimpan pada Firestore serta storage lokal backend.”

Jika ditanya “K-Means-nya di mana?” jawab `backend/segmentation.py`.
Jika ditanya “Fuzzy-nya di mana?” jawab `backend/fuzzy_logic.py`.
Jika ditanya “ANN-nya di mana?” jelaskan dua bagian: MobileNetV2 classifier
gambar dilatih oleh `backend/train_plant_model.py`, sedangkan ANN angka opsional
ada di `backend/numeric_ann.py` dan dilatih oleh `backend/train_numeric_ann.py`.
