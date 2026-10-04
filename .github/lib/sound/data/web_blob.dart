// lib/sound/data/web_blob.dart
//
// Punte minimă către API-urile browserului (dart:js_interop), fără dependență de
// versiunea package:web: Blob + URL.createObjectURL, navigator.storage.persist /
// estimate. Aplicația rulează pe Web, deci acestea sunt disponibile.

import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _JsBlob._(JSObject _) implements JSObject {
  external factory _JsBlob(JSArray parts, _JsBlobOptions options);
}

extension type _JsBlobOptions._(JSObject _) implements JSObject {
  external factory _JsBlobOptions({String type});
}

@JS('URL.createObjectURL')
external String _createObjectUrl(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

@JS('navigator.storage.persist')
external JSPromise<JSBoolean> _persist();

extension type _Estimate._(JSObject _) implements JSObject {
  external double? get usage;
  external double? get quota;
}

@JS('navigator.storage.estimate')
external JSPromise<_Estimate> _estimate();

/// Creează un URL `blob:` redabil de <audio>/<video> dintr-un fișier din memorie.
String createBlobUrl(Uint8List bytes, String mime) {
  final blob = _JsBlob(
    <JSAny>[bytes.toJS].toJS,
    _JsBlobOptions(type: mime),
  );
  return _createObjectUrl(blob);
}

void revokeBlobUrl(String url) {
  try {
    _revokeObjectUrl(url);
  } catch (_) {}
}

/// Cere browserului stocare persistentă (să nu fie ștearsă sub presiune de spațiu).
Future<bool> requestPersistentStorage() async {
  try {
    return (await _persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}

class StorageEstimate {
  final double usageBytes;
  final double quotaBytes;
  const StorageEstimate(this.usageBytes, this.quotaBytes);
  double get freeBytes => quotaBytes - usageBytes;
}

Future<StorageEstimate?> storageEstimate() async {
  try {
    final e = await _estimate().toDart;
    final usage = e.usage;
    final quota = e.quota;
    if (usage == null || quota == null) return null;
    return StorageEstimate(usage, quota);
  } catch (_) {
    return null;
  }
}
