// lib/sound/data/hive_media_store.dart
//
// MediaStorePort pe web: fișierele rămân în IndexedDB (prin Hive CE, LazyBox —
// valorile se citesc doar la nevoie, nu toate în memorie) și supraviețuiesc
// repornirii. Metadatele (mime, mărime) sunt într-un Box mic, separat.
// Se cere stocare persistentă (navigator.storage.persist) la inițializare.

import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/ports.dart';
import 'web_blob.dart';

class HiveMediaStore implements MediaStorePort {
  final String namespace;
  LazyBox<Uint8List>? _blobs;
  Box<String>? _meta; // key -> "<bytes>|<mime>"
  final Map<String, String> _urls = <String, String>{};

  HiveMediaStore({this.namespace = 'sound_media'});

  @override
  Future<void> init() async {
    if (_blobs != null) return;
    await Hive.initFlutter();
    _blobs = await Hive.openLazyBox<Uint8List>('${namespace}_blobs');
    _meta = await Hive.openBox<String>('${namespace}_meta');
    await requestPersistentStorage();
  }

  LazyBox<Uint8List> get _b {
    final b = _blobs;
    if (b == null) throw StateError('HiveMediaStore: apelează init() întâi');
    return b;
  }

  Box<String> get _m {
    final m = _meta;
    if (m == null) throw StateError('HiveMediaStore: apelează init() întâi');
    return m;
  }

  @override
  Future<void> put(String key, Uint8List bytes, String mime) async {
    _forgetUrl(key);
    await _b.put(key, bytes);
    await _m.put(key, '${bytes.length}|$mime');
  }

  @override
  Future<bool> has(String key) async =>
      _m.containsKey(key) && _b.containsKey(key);

  @override
  Future<String?> playableUrl(String key) async {
    final cached = _urls[key];
    if (cached != null) return cached;
    final bytes = await _b.get(key);
    if (bytes == null) return null;
    final mime = _mimeOf(key);
    final url = createBlobUrl(bytes, mime);
    _urls[key] = url;
    return url;
  }

  String _mimeOf(String key) {
    final raw = _m.get(key);
    if (raw == null) return 'application/octet-stream';
    final i = raw.indexOf('|');
    return i < 0 ? 'application/octet-stream' : raw.substring(i + 1);
  }

  void _forgetUrl(String key) {
    final u = _urls.remove(key);
    if (u != null) revokeBlobUrl(u);
  }

  @override
  Future<void> delete(String key) async {
    _forgetUrl(key);
    await _b.delete(key);
    await _m.delete(key);
  }

  @override
  Future<int> totalBytes() async {
    var sum = 0;
    for (final v in _m.values) {
      final i = v.indexOf('|');
      sum += int.tryParse(i < 0 ? v : v.substring(0, i)) ?? 0;
    }
    return sum;
  }

  @override
  Future<double?> freeBytes() async => (await storageEstimate())?.freeBytes;

  @override
  Future<void> clear() async {
    for (final k in List<String>.of(_urls.keys)) {
      _forgetUrl(k);
    }
    await _b.clear();
    await _m.clear();
  }
}
