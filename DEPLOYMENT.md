# Deployment LEAF LENS pada domain Erytheia

Panduan ini memisahkan Flutter Web statis dari API FastAPI. File Firebase Web di aplikasi adalah konfigurasi publik; kredensial Firebase Admin dan secret lain hanya boleh berada di server API.

## 1. Pemeriksaan sebelum rilis

Dari direktori `web/`:

```sh
flutter pub get
flutter analyze
flutter test
flutter build web --release --base-href / \
  --dart-define=PLANT_API_URL=https://api.erytheia.id
```

Build statis tersedia di `web/build/web/`. Jangan mengunggah source Dart sebagai pengganti folder hasil build. Untuk preview lokal, URL API dapat diarahkan ke API development menggunakan `--dart-define`; jangan menggunakan konfigurasi development saat build produksi.

## 2. Konfigurasi Firebase

1. Di Firebase Authentication, aktifkan Email/Password dan Google sebagai provider sign-in.
2. Tambahkan `erytheia.id` dan `www.erytheia.id` ke Authorized domains. Tambahkan domain preview Hostinger jika dipakai untuk pengujian OAuth.
3. Deploy Firestore rules dari direktori Web:

   ```sh
   cd web
   firebase deploy --only firestore:rules
   ```

4. Pastikan Google sign-in dan geolokasi diuji melalui HTTPS. Browser umumnya hanya mengizinkan popup OAuth dan lokasi di secure context (localhost juga diizinkan untuk development).

## 3. Deploy frontend ke Hostinger

1. Hubungkan repository GitHub melalui Git Deployment di hPanel jika fitur itu tersedia pada paket hosting. Pilih branch rilis dan jangan arahkan document root ke source `web/lib/`.
2. Build Flutter Web pada mesin/CI yang memiliki Flutter SDK, lalu unggah **isi** `web/build/web/` ke `public_html/` (atau document root domain `erytheia.id`).
3. Aktifkan SSL untuk domain utama dan `www`; aktifkan redirect HTTP ke HTTPS.
4. Untuk Flutter navigation berbasis path, tambahkan `.htaccess` berikut di document root. File statis yang ada akan tetap disajikan langsung; route lain kembali ke `index.html`.

   ```apache
   <IfModule mod_rewrite.c>
     RewriteEngine On
     RewriteCond %{REQUEST_FILENAME} !-f
     RewriteCond %{REQUEST_FILENAME} !-d
     RewriteRule ^ index.html [L]
   </IfModule>

   <IfModule mod_headers.c>
     <FilesMatch "^(index\.html|flutter_bootstrap\.js|main\.dart\.js|flutter_service_worker\.js|version\.json)$">
       Header set Cache-Control "no-cache, no-store, must-revalidate"
     </FilesMatch>
     <FilesMatch "\.(wasm|png|jpe?g|webp|svg|glb|ttf|woff2)$">
       Header set Cache-Control "public, max-age=2592000"
     </FilesMatch>
   </IfModule>
   ```

5. Setelah upload, buka `https://erytheia.id`, cek DevTools Network untuk memastikan asset tidak 404, lalu uji login Google, unggah foto, akses lokasi (opsional), dashboard, serta refresh pada route non-root.

Hostinger Git deployment biasanya mengambil source, bukan otomatis menjalankan Flutter build. Jika tidak ada build hook Flutter, gunakan GitHub Actions atau build lokal lalu unggah hasil `web/build/web/`. Jangan commit cache `.dart_tool/` sebagai artefak deployment.

## 4. Deploy FastAPI

Flutter Web membutuhkan API terpisah untuk inferensi MobileNetV2. Gunakan Hostinger VPS atau layanan Python ASGI yang mendukung proses FastAPI terus berjalan; shared hosting statis saja tidak cukup untuk menjalankan model PyTorch.

1. Arahkan `api.erytheia.id` ke VPS/API host dan pasang TLS.
2. Pasang dependency dari `backend/requirements.txt`, checkpoint yang sesuai, dan data cuaca BMKG fallback.
3. Simpan Firebase Admin service-account JSON di luar repository. Atur `GOOGLE_APPLICATION_CREDENTIALS` ke path file tersebut.
4. Jalankan dengan `PLANT_REQUIRE_AUTH=true`, `PLANT_ALLOWED_ORIGINS=https://erytheia.id,https://www.erytheia.id`, dan `PLANT_MODEL_PATH` yang menunjuk checkpoint produksi. Gunakan reverse proxy HTTPS ke proses Uvicorn yang bind ke loopback.
5. Jangan pernah mengatur `PLANT_REQUIRE_AUTH=false` pada server publik. Jangan memasukkan service-account JSON, password, token, atau secret ke GitHub, Flutter `--dart-define`, maupun bundle browser.
6. Verifikasi `https://api.erytheia.id/health`, CORS dari origin Erytheia, Firebase bearer-token verification, penolakan OOD, dan akses Firestore hanya untuk UID pemilik.

Contoh konfigurasi Nginx untuk `api.erytheia.id` (sesuaikan lokasi sertifikat TLS
setelah memasangnya, misalnya dengan Certbot):

```nginx
server {
    listen 80;
    server_name api.erytheia.id;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name api.erytheia.id;

    ssl_certificate /etc/letsencrypt/live/api.erytheia.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.erytheia.id/privkey.pem;
    client_max_body_size 11m;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
}
```

Jalankan Uvicorn hanya pada `127.0.0.1:8000`; jangan membuka port backend
langsung ke internet. Setelah menyimpan konfigurasi, uji dengan
`sudo nginx -t`, lalu reload Nginx.

`PLANT_API_URL` bukan secret; nilainya tertanam dalam bundle Web. Endpoint API tetap wajib memverifikasi Firebase ID token di server.

## 5. Rilis dan rollback

Simpan commit/tag dari source yang dirilis. Untuk rollback, unggah kembali artefak `web/build/web/` dari build sebelumnya dan pulihkan konfigurasi API/checkpoint yang cocok. Setelah mengganti checkpoint, restart FastAPI dan jalankan smoke test scan sebelum membuka trafik.
