# Atribusi dan Pernyataan Hak

Dokumen ini adalah inventaris awal untuk pemeriksaan internal pengajuan HKI,
bukan pendapat hukum atau pengganti pemeriksaan lisensi pada salinan sumber
masing-masing.

## Dataset dan model

| Komponen | Atribusi / status yang diketahui | Tindakan sebelum pengajuan |
|---|---|---|
| PlantVillage | Dataset daun yang digunakan sebagai sumber data klasifikasi. Repository ini tidak memuat bukti lisensi dari salinan atau URL asal dataset. | Catat URL unduhan, pengelola dataset, publikasi/sitasi, versi, dan berkas lisensi yang menyertai salinan yang benar-benar digunakan. Jangan menyatakan CC BY-SA 4.0 atau public domain tanpa bukti yang berlaku untuk salinan tersebut. |
| PlantDoc, contoh OOD, dan data cuaca BMKG | Beberapa sumber data eksternal dipakai/dirujuk oleh pipeline. Hak penggunaan dan kondisi redistribusi harus diperiksa pada sumber masing-masing. | Buat daftar sumber, tanggal akses, ketentuan penggunaan, atribusi yang diminta, dan bukti izin jika diperlukan. |
| Bobot MobileNetV2 / EfficientNet-B0 | Bobot checkpoint dapat berasal dari pelatihan proyek, inisialisasi ImageNet, atau sumber pihak ketiga bergantung pada proses training. Checkpoint yang aktif harus diidentifikasi satu per satu. | Arsipkan konfigurasi training, sumber bobot awal, lisensi model pra-latih, checkpoint akhir, dan laporan evaluasi. Jangan menyamakan lisensi arsitektur dengan lisensi bobot. |
| Ilustrasi dan font | Aplikasi memuat aset visual pihak ketiga serta aset yang dibuat/diberikan untuk proyek. | Simpan bukti lisensi atau izin penggunaan tiap aset dan atribusi yang diwajibkan. |

## Framework dan library utama

Lisensi dapat berbeda menurut versi, distribusi, serta komponen dependensi.
Tabel ini adalah titik awal pemeriksaan, bukan pengganti berkas lisensi pada
rilis perangkat lunak yang dipakai.

| Komponen | Lisensi yang umum dinyatakan proyek upstream | Verifikasi |
|---|---|---|
| PyTorch | BSD-style | [Upstream LICENSE](https://github.com/pytorch/pytorch/blob/main/LICENSE); cocokkan dengan versi paket yang dipakai. |
| FastAPI | MIT | [Upstream LICENSE](https://github.com/fastapi/fastapi/blob/master/LICENSE); cocokkan dengan versi paket yang dipakai. |
| Flutter | BSD-3-Clause | [Upstream LICENSE](https://github.com/flutter/flutter/blob/master/LICENSE); cocokkan dengan versi SDK yang dipakai. |
| OpenCV, Pillow, NumPy, torchvision, Firebase SDK, dan paket Dart lainnya | Lisensi beragam | Inventarisasi versi langsung dan transitif dari lockfile/manifest; simpan notice yang diwajibkan. |

## Ruang lingkup klaim kepemilikan

Pernyataan yang dapat diajukan untuk diperiksa:

> Pencipta mengklaim kepengarangan atas bagian kode sumber program yang
> dikembangkan sendiri untuk LEAF LENS, termasuk implementasi integrasi API,
> pengaturan alur pemrosesan, antarmuka yang dibuat untuk proyek, dan logika
> orkestrasi yang tercantum pada berkas sumber yang diserahkan. Klaim ini tidak
> mencakup framework, library, dataset, bobot/model pra-latih, font, ilustrasi,
> atau materi pihak ketiga. Status kepemilikan institusi, kontribusi pihak lain,
> serta hak penggunaan setiap komponen eksternal harus diperiksa sebelum
> pernyataan ditandatangani.

Hindari klaim “seluruh proyek 100% milik pencipta” sebelum kontribusi,
perjanjian pembimbing/institusi, aset pihak ketiga, data, dan model ditelaah.
Cantumkan seluruh kontributor manusia yang memenuhi kriteria pencipta dan
pastikan pengajuan sesuai kebijakan prodi/kampus.

## Arsip bukti yang disarankan

- Arsip source code bertanggal dan hash SHA-256, termasuk nomor versi/commit.
- Daftar pencipta, kontribusi, tanggal pengembangan, dan bukti proses
  penciptaan yang tersedia.
- Snapshot dependensi dan inventaris lisensi seluruh aset/data/model.
- Pernyataan sumber dataset dan izin redistribusi (jika berkas data disertakan).
- Laporan pengujian, dokumentasi pengguna, diagram arsitektur, dan tangkapan
  layar yang sesuai dengan versi source yang diajukan.
