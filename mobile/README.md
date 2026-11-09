# Smart Plant Monitoring & AI Detection

Flutter app for Android, iOS, macOS, and responsive Web. Firebase Authentication uses email/password; each signed-in user's scan history and compressed mask thumbnails are stored in that user's Firestore collection.
On native devices, existing SQLite records are imported once into the Firestore account used for the first successful sign-in; the original local database is left untouched.

The mobile screens share the Web app's forest/sage palette, locally bundled landscape backdrop, glass-like surfaces, garden artwork, and display/body typography. The landscape is pre-blurred as a static asset instead of applying a full-screen live blur; this keeps scrolling and camera preview rendering lighter on phones. Entrances are brief and one-shot, and respect reduced-motion preferences.

## Firebase setup

The Web app options are configured in `lib/firebase_options.dart` from the Firebase Web app configuration. Before running:

1. In Firebase Console, enable **Authentication → Email/Password**.
2. Create a **Cloud Firestore** database.
3. Add the deployed Hostinger domain (and `localhost`) to **Authentication → Settings → Authorized domains**.
4. Deploy the included owner-only rules from `mobile/`:

   ```sh
   firebase deploy --only firestore:rules
   ```

The Firebase Web config in the client is public app configuration, not a server credential. Never put a Firebase service-account key in this app or in the web build.

## Run locally

Install Flutter and the tooling for your target platform, then from `mobile/`:

```sh
flutter pub get
```

Start the FastAPI service from the repository root:

```sh
uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

Run the app on Chrome or another supported browser (camera access requires localhost or HTTPS):

```sh
cd mobile
flutter run -d chrome --dart-define=PLANT_API_URL=http://localhost:8000
```

If Chrome is not installed, use Flutter's web-server device and open the printed localhost URL in a browser:

```sh
flutter run -d web-server --web-port 5000 --dart-define=PLANT_API_URL=http://localhost:8000
```

For browser camera permission, grant access when prompted. The Scan page also has an **Upload foto** option if the browser/device has no camera or permission is denied. Use HTTPS on deployed sites.

Configure FastAPI CORS for the browser origin. For local web-server development, for example:

```sh
PLANT_ALLOWED_ORIGINS=http://localhost:5000,http://127.0.0.1:5000 uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

On an Android emulator, use `http://10.0.2.2:8000`; on a physical phone, use the computer's LAN IP. For an iOS simulator use `http://127.0.0.1:8000`. Pass the selected API base URL with `--dart-define=PLANT_API_URL=...`.

## Build and publish to Hostinger

Build the static site from `mobile/`, setting the HTTPS base URL for the deployed FastAPI service:

```sh
flutter build web --release --dart-define=PLANT_API_URL=https://api.example.com
```

The static output is `mobile/build/web/`. In Hostinger File Manager, upload the **contents** of that directory to the domain's `public_html` directory. For a subdirectory deployment, set its base path too, for example `--base-href /plant/`.

Set `PLANT_ALLOWED_ORIGINS` on the FastAPI host to the exact HTTPS website origin (for example `https://plants.example.com`) and keep the API itself on HTTPS. Add both the apex and `www` domain to Firebase Authorized domains if both are used.

The GitHub Actions workflow at `.github/workflows/flutter-web.yml` runs analysis and tests and builds the Web artifact on pushes and pull requests. Add a GitHub Actions repository variable named `PLANT_API_URL` with the production API URL so the artifact points to the deployed backend.

## Desktop and phone cameras

The Scan tab uses Flutter's camera plugin for browser, Android, and iOS cameras and supports file/gallery upload as a fallback. On macOS desktop, use the camera selector to choose the built-in or connected camera. For iPhone Continuity Camera, configure Apple's Continuity Camera, keep the iPhone nearby and locked, then refresh the camera list. Alternatively, run the app directly on the iPhone to use its camera.

For a native macOS build, install full Xcode and CocoaPods first, then run `flutter run -d macos --dart-define=PLANT_API_URL=http://127.0.0.1:8000`. The speech engine requests Indonesian (`id-ID`) and Damayanti when installed, otherwise uses the device's default Indonesian voice.
