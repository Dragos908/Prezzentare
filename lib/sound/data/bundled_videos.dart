// lib/sound/data/bundled_videos.dart
//
// BundledVideosPort peste manifestul de assets al aplicației. Video-urile pentru
// display sunt incluse ÎN aplicație (folderul `assets/sound_video/`, declarat în
// pubspec.yaml), deci nu mai e nevoie de niciun serviciu extern de stocare.
//
// Legătura se face după numele fișierului: când imporți un video din calculator,
// dacă în `assets/sound_video/` există un fișier cu ACELAȘI nume, displayul îl
// redă din aplicație. Compararea ignoră majusculele, spațiile în plus și
// diacriticele (ca „Crăciun.mp4” și „craciun.mp4” să fie același fișier).
//
// Atenție: lista de assets e fixată la BUILD. Un fișier pus în folder după build
// apare doar după ce aplicația e reconstruită (și, pe web, reîncărcată fără cache).

import 'package:flutter/services.dart';

import '../core/ports.dart';

class BundledVideos implements BundledVideosPort, BundledVideosCatalog {
  /// Folderul (din pubspec.yaml) în care se pun video-urile pentru display.
  static const String dir = 'assets/sound_video/';

  List<String>? _assets;

  /// Lista asset-urilor din [dir]. Un eșec la citirea manifestului NU se ține minte
  /// (se reîncearcă la următorul apel); o listă goală citită cu succes, da.
  Future<List<String>> _list() async {
    final cached = _assets;
    if (cached != null) return cached;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final list = manifest
          .listAssets()
          .where((a) => a.startsWith(dir))
          .toList(growable: false);
      _assets = list;
      return list;
    } catch (_) {
      return const <String>[]; // fără manifest: niciun video în aplicație
    }
  }

  static String _fileOf(String asset) =>
      asset.substring(asset.lastIndexOf('/') + 1);

  static String _stemOf(String file) {
    final i = file.lastIndexOf('.');
    return i <= 0 ? file : file.substring(0, i);
  }

  static const Map<String, String> _plain = <String, String>{
    'ă': 'a',
    'â': 'a',
    'î': 'i',
    'ș': 's',
    'ş': 's',
    'ț': 't',
    'ţ': 't',
  };

  /// Forma de comparare a unui nume: litere mici, fără diacritice (nici cele
  /// „combinate”, din forma NFD pe care o scriu unele sisteme), spații simple.
  static String fold(String s) {
    final b = StringBuffer();
    for (final r in s.trim().toLowerCase().runes) {
      if (r >= 0x0300 && r <= 0x036F) continue; // semn combinat (NFD)
      final ch = String.fromCharCode(r);
      b.write(_plain[ch] ?? ch);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Future<String?> find(String fileName) async {
    final want = fold(fileName);
    if (want.isEmpty) return null;
    for (final asset in await _list()) {
      if (fold(_fileOf(asset)) == want) return asset;
    }
    return null;
  }

  @override
  Future<List<String>> names() async {
    final out = <String>[for (final a in await _list()) _fileOf(a)];
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  @override
  Future<String?> findByTitle(String title) async {
    final want = fold(title);
    if (want.isEmpty) return null;
    for (final asset in await _list()) {
      final file = _fileOf(asset);
      if (fold(file) == want || fold(_stemOf(file)) == want) return asset;
    }
    return null;
  }
}
