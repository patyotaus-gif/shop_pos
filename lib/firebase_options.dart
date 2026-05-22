// File generated manually from google-services.json
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web platform not configured.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDmY7ZnGfbpB66zb1pJcS2I-NCgUsiu6QA',
    appId: '1:1010156115465:android:873bb66da2217c4da68ad8',
    messagingSenderId: '1010156115465',
    projectId: 'shop-pos-89294',
    storageBucket: 'shop-pos-89294.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCNLzUBCDJz8613VTa9YQnSGUaVlNy_GVo',
    appId: '1:1010156115465:ios:eb6db61eb6305fdca68ad8',
    messagingSenderId: '1010156115465',
    projectId: 'shop-pos-89294',
    storageBucket: 'shop-pos-89294.firebasestorage.app',
    iosBundleId: 'app.pokpok.pos',
  );
}
