// lib/sound/data/media_uploader.dart
//
// Distribuie video-urile către display prin Firebase Storage (același proiect
// Firebase ca baza de date). Se salvează URL-ul de descărcare în `mediaUrl`.
// Reguli necesare în consola Firebase: Storage → Rules → permite citire/scriere
// pe calea `<proiect>/sound/**` (la fel cum e deschisă baza de date).

import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../core/firebase_service.dart';
import '../core/ports.dart';

class MediaUploader implements MediaUploaderPort {
  final FirebaseStorage _storage;

  MediaUploader({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  Reference _ref(String key) => _storage
      .ref()
      .child(FirebaseService.instance.currentProject)
      .child('sound')
      .child(key);

  /// Urcă fișierul și întoarce URL-ul de descărcare. [onProgress] primește 0..1.
  @override
  Future<String> upload({
    required String key,
    required Uint8List bytes,
    required String mime,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _ref(key);
    final task = ref.putData(bytes, SettableMetadata(contentType: mime));
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    return ref.getDownloadURL();
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _ref(key).delete();
    } catch (_) {/* poate nu a fost niciodată urcat */}
  }
}
