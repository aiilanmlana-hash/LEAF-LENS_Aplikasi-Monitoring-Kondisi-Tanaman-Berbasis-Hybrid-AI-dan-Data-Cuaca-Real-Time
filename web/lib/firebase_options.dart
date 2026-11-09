import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError('This Flutter Web application only supports Web.');
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyBrwsbSv5j38-QzRWLnk6uuZUi6BFt6wN4',
    appId: '1:398093379000:web:b7f40f3ad49be559689b4d',
    messagingSenderId: '398093379000',
    projectId: 'smart-plant-app-dd8bc',
    authDomain: 'smart-plant-app-dd8bc.firebaseapp.com',
    storageBucket: 'smart-plant-app-dd8bc.firebasestorage.app',
    measurementId: 'G-1BSC5VTG3B',
  );
}
