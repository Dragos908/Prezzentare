// lib/sound/display/display_media_cache.dart
//
// Displayul încarcă în avans video-urile din bibliotecă din ASSETS-urile
// aplicației (assets/sound_video/) și le ține în cache local (același
// MediaStorePort ca la control) — start instant, seek precis. Până când fișierul
// e în cache, se redă direct din asset (`asset:<cale>`); `lastError` spune de ce
// a eșuat o încărcare.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../core/models.dart';
import '../core/ports.dart';

class DisplayMediaCache {
  final MediaStorePort store;
  final Future<Uint8List> Function(String assetPath) _fetch;
  final Set<String> _inFlight = <String>{};

  /// Ultimul motiv pentru care o încărcare în avans a eșuat.
  String? lastError;

  DisplayMediaCache(
      {required this.store, Future<Uint8List> Function(String assetPath)? fetch})
      : _fetch = fetch ?? _fromBundle;

  /// Citește un asset din aplicație ca octeți.
  static Future<Uint8List> _fromBundle(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  String _key(SoundItem item) => 'd_${item.id}_${(item.assetPath ?? '').hashCode}';

  /// `assetPath` poate fi și un link direct (https://…/video.mp4): displayul îl
  /// redă direct de la acel link, fără asset din aplicație și fără cache local.
  static bool isLink(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  /// Sursă redabilă: din cache dacă există (URL `blob:`), altfel direct din asset
  /// (`asset:<cale>`) — și se pornește încărcarea în fundal pentru data viitoare.
  /// null = sunetul nu are video în aplicație.
  Future<String?> resolve(SoundItem item) async {
    final path = item.assetPath;
    if (path == null) return null;
    if (isLink(path)) return path; // link direct: se redă de la el
    final key = _key(item);
    try {
      if (await store.has(key)) {
        final local = await store.playableUrl(key);
        if (local != null) return local;
      }
    } catch (_) {/* cache indisponibil: redăm direct din asset */}
    unawaited(prefetch(item));
    return '$kAssetSourcePrefix$path';
  }

  Future<void> prefetch(SoundItem item) async {
    final path = item.assetPath;
    if (path == null || isLink(path)) return; // linkurile nu se pun în cache
    final key = _key(item);
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);
    try {
      if (await store.has(key)) return;
      final bytes = await _fetch(path);
      await store.put(key, bytes, item.mime.isEmpty ? 'video/mp4' : item.mime);
      lastError = null;
    } catch (e) {
      lastError = 'Încărcare eșuată pentru „${item.name}”: $e '
          '(verifică să existe în assets/sound_video/ și să fie declarat în pubspec.yaml).';
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Încarcă pe rând toate video-urile din bibliotecă.
  Future<void> prefetchAll(Iterable<SoundItem> items) async {
    for (final it in items) {
      if (it.isVideo) await prefetch(it);
    }
  }
}