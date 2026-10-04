// lib/sound/data/sound_library.dart
//
// Biblioteca de sunete: metadatele sunt în baza de date, fișierele în magazia
// locală persistentă (copiate la import, nu doar calea din selector). Pentru
// sunetele video, imaginea de pe display vine din fișierul cu același nume aflat
// ÎN aplicație (assets/sound_video/); aici se face doar legătura (`assetPath`).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/playlist_logic.dart';
import '../core/ports.dart';

class PickedMedia {
  final String name;
  final Uint8List bytes;
  final String? mime;
  const PickedMedia({required this.name, required this.bytes, this.mime});

  String get extension {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  String get baseName {
    final i = name.lastIndexOf('.');
    final b = i <= 0 ? name : name.substring(0, i);
    return b.trim().isEmpty ? 'Sunet' : b.trim();
  }
}

enum MediaHealth { ok, missing }

enum JobState { queued, working, done, failed }

class ImportJob {
  final int id;
  final String name;
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  final ValueNotifier<JobState> state = ValueNotifier<JobState>(JobState.queued);
  String? error;
  ImportJob(this.id, this.name);
}

class SoundLibrary {
  static const int maxBytes = 700 * 1024 * 1024;
  static const Set<String> audioExt = {'mp3', 'wav', 'ogg', 'oga', 'm4a', 'aac', 'flac', 'opus', 'weba'};
  static const Set<String> videoExt = {'mp4', 'mov', 'm4v', 'webm', 'mkv'};

  final SyncChannelPort channel;
  final MediaStorePort store;
  final BundledVideosPort? bundledVideos;
  final AudioPlayerFactory playerFactory;

  final ValueNotifier<List<SoundItem>> items =
      ValueNotifier<List<SoundItem>>(const <SoundItem>[]);
  final ValueNotifier<Map<String, MediaHealth>> health =
      ValueNotifier<Map<String, MediaHealth>>(const <String, MediaHealth>{});
  final ValueNotifier<List<ImportJob>> jobs =
      ValueNotifier<List<ImportJob>>(const <ImportJob>[]);

  StreamSubscription<List<SoundItem>>? _sub;
  int _jobSeq = 0;
  bool _disposed = false;

  SoundLibrary({
    required this.channel,
    required this.store,
    required this.playerFactory,
    this.bundledVideos,
  });

  SoundItem? byId(String id) {
    for (final i in items.value) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> start() async {
    await store.init();
    _sub = channel.itemsStream().listen((list) {
      items.value = sortedItems(list);
      unawaited(_checkIntegrity());
      unawaited(_autoRelink());
    });
  }

  // ── legătura cu video-urile din aplicație (assets) ────────────────────────
  /// Lista fișierelor din aplicație, dacă implementarea o poate da.
  BundledVideosCatalog? get _catalog {
    final Object? b = bundledVideos;
    return b is BundledVideosCatalog ? b : null;
  }

  bool _relinking = false;

  /// Id-urile pentru care s-a încercat deja o salvare în sesiunea asta: dacă
  /// baza de date nu păstrează legătura, nu intrăm într-o buclă de scrieri.
  final Set<String> _relinkTried = <String>{};

  Future<void> _autoRelink() async {
    if (_relinking || _disposed) return;
    _relinking = true;
    try {
      await relinkBundledVideos();
    } catch (_) {
      // se reîncearcă la următoarea schimbare a listei
    } finally {
      _relinking = false;
    }
  }

  /// Leagă de aplicație video-urile rămase fără `assetPath` al căror fișier a apărut
  /// între timp în assets/sound_video/ (build nou după import). Potrivire după
  /// numele sunetului (cu sau fără extensie, fără diferență între majuscule și
  /// minuscule). Întoarce câte video-uri au fost legate.
  Future<int> relinkBundledVideos() async {
    final cat = _catalog;
    if (cat == null) return 0;
    var linked = 0;
    final waiting =
        items.value.where((e) => e.isVideo && e.assetPath == null).toList();
    for (final it in waiting) {
      if (_disposed || _relinkTried.contains(it.id)) continue;
      final asset = await cat.findByTitle(it.name);
      if (asset == null) continue;
      // starea de ACUM: sunetul poate fi șters sau editat cât timp am căutat
      final fresh = byId(it.id);
      if (fresh == null || fresh.assetPath != null) continue;
      _relinkTried.add(it.id);
      await save(fresh.copyWith(assetPath: asset));
      linked++;
    }
    return linked;
  }

  /// Mesajul pentru un video care nu e (încă) în aplicație, cu ce vede aplicația
  /// acum în assets/sound_video/ — ca să se vadă dacă problema e folderul / build-ul
  /// (listă goală) sau numele fișierului (listă fără el).
  Future<String> _notBundledMessage(String fileName) async {
    const head = 'Video-ul nu e în aplicație: displayul nu va avea imaginea.';
    List<String>? seen;
    try {
      seen = await _catalog?.names();
    } catch (_) {/* fără diagnostic */}
    if (seen == null) {
      return '$head Pune „$fileName” în assets/sound_video/ și reconstruiește aplicația.';
    }
    if (seen.isEmpty) {
      return '$head Aplicația nu vede niciun fișier în assets/sound_video/. Pune '
          '„$fileName” acolo, verifică să fie declarat în pubspec.yaml și '
          'reconstruiește aplicația (build nou, nu doar hot reload).';
    }
    final shown = seen.take(6).join(', ') + (seen.length > 6 ? ', …' : '');
    return '$head Aplicația vede în assets/sound_video/: $shown. Numele trebuie să '
        'fie identic cu „$fileName” (cu tot cu extensie). După ce îl pui acolo, '
        'reconstruiește aplicația.';
  }

  /// La pornire și la schimbarea listei: fișier lipsă → marcaj (re-adăugare).
  Future<void> _checkIntegrity() async {
    final next = <String, MediaHealth>{};
    for (final it in items.value) {
      next[it.id] = await store.has(it.id) ? MediaHealth.ok : MediaHealth.missing;
    }
    if (!_disposed) health.value = next;
  }

  // ── tip / validare ────────────────────────────────────────────────────────
  static SoundType? detectType(PickedMedia f) {
    final mime = (f.mime ?? '').toLowerCase();
    if (mime.startsWith('video/') || videoExt.contains(f.extension)) {
      return SoundType.video;
    }
    if (mime.startsWith('audio/') || audioExt.contains(f.extension)) {
      return SoundType.audio;
    }
    return null;
  }

  /// null = valid; altfel mesajul de eroare (în română).
  static String? validate(PickedMedia f) {
    if (f.bytes.isEmpty) return 'Fișierul „${f.name}” este gol.';
    if (f.bytes.length > maxBytes) {
      return 'Fișierul „${f.name}” depășește ${maxBytes ~/ (1024 * 1024)} MB.';
    }
    if (detectType(f) == null) {
      return 'Tip nesuportat pentru „${f.name}”. Folosește audio (mp3, wav, ogg, m4a…) '
          'sau video (mp4, mov, webm).';
    }
    return null;
  }

  static String mimeFor(PickedMedia f, SoundType type) {
    final m = f.mime;
    if (m != null && m.isNotEmpty) return m;
    switch (f.extension) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return type == SoundType.video ? 'video/webm' : 'audio/webm';
      default:
        return type == SoundType.video ? 'video/mp4' : 'audio/mpeg';
    }
  }

  // ── import ────────────────────────────────────────────────────────────────
  /// Importă mai multe fișiere, pe rând. Întoarce joburile (progres + erori).
  List<ImportJob> importFiles(
    List<PickedMedia> files, {
    SoundType? forceType,
    String? nameOverride,
  }) {
    final created = <ImportJob>[];
    for (final f in files) {
      final job = ImportJob(++_jobSeq, f.name);
      created.add(job);
    }
    jobs.value = <ImportJob>[...jobs.value, ...created];
    unawaited(_runImports(files, created, forceType, nameOverride));
    return created;
  }

  Future<void> _runImports(List<PickedMedia> files, List<ImportJob> js,
      SoundType? forceType, String? nameOverride) async {
    for (var i = 0; i < files.length; i++) {
      await _importOne(files[i], js[i], forceType,
          files.length == 1 ? nameOverride : null);
    }
  }

  Future<void> _importOne(
      PickedMedia f, ImportJob job, SoundType? forceType, String? name) async {
    job.state.value = JobState.working;
    try {
      final err = validate(f);
      if (err != null) throw StateError(err);

      final free = await store.freeBytes();
      if (free != null && free < f.bytes.length * 1.3) {
        throw StateError('Spațiu insuficient în browser pentru „${f.name}” '
            '(liber ≈ ${(free / (1024 * 1024)).floor()} MB).');
      }

      final type = forceType ?? detectType(f)!;
      final mime = mimeFor(f, type);
      final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '${_jobSeq.toRadixString(36)}';

      // 1) copie locală persistentă
      try {
        await store.put(id, f.bytes, mime);
      } catch (_) {
        throw StateError('Nu s-a putut salva local „${f.name}” (spațiu insuficient?).');
      }
      job.progress.value = 0.25;

      // 2) durata
      final url = await store.playableUrl(id);
      var duration = 0;
      if (url != null) {
        final p = playerFactory();
        try {
          duration = (await p.load(url)) ?? 0;
        } catch (_) {
          await store.delete(id);
          throw StateError('Fișierul „${f.name}” nu poate fi redat de browser.');
        } finally {
          await p.dispose();
        }
      }
      job.progress.value = 0.4;

      // 3) video: legătura către fișierul din aplicație (assets), redat de display
      final title = (name != null && name.trim().isNotEmpty) ? name.trim() : f.baseName;
      String? assetPath;
      if (type == SoundType.video) {
        try {
          // întâi numele exact al fișierului, apoi titlul sunetului (fără extensie)
          assetPath =
              await bundledVideos?.find(f.name) ?? await _catalog?.findByTitle(title);
        } catch (_) {/* fără manifest de assets: tratat ca „nu e în aplicație” */}
        if (assetPath == null) {
          // fișierul rămâne local (sunetul funcționează); displayul nu va avea imaginea
          job.error = await _notBundledMessage(f.name);
        }
      }
      job.progress.value = 0.9;

      final order = items.value.isEmpty
          ? 0
          : items.value.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

      final item = SoundItem(
        id: id,
        name: title,
        type: type,
        assetPath: assetPath,
        mime: mime,
        durationMs: duration,
        trimStartMs: 0,
        trimEndMs: null,
        sortOrder: order,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await channel.upsertItem(item);
      job.progress.value = 1;
      job.state.value = JobState.done;
    } catch (e) {
      job.error = e is StateError ? e.message : e.toString();
      job.state.value = JobState.failed;
    }
  }

  /// Re-atașează fișierul unui sunet al cărui fișier local lipsește.
  Future<void> reattach(String id, PickedMedia f) async {
    final it = byId(id);
    if (it == null) return;
    final err = validate(f);
    if (err != null) throw StateError(err);
    await store.put(id, f.bytes, mimeFor(f, it.type));
    // video încă nelegat de aplicație: reîncearcă după numele fișierului ales
    if (it.isVideo && it.assetPath == null) {
      final asset = await bundledVideos?.find(f.name);
      if (asset != null) await save(it.copyWith(assetPath: asset));
    }
    await _checkIntegrity();
  }

  void dismissJob(ImportJob job) {
    jobs.value = jobs.value.where((j) => j.id != job.id).toList();
  }

  // ── editare ───────────────────────────────────────────────────────────────
  Future<void> save(SoundItem item) => channel.upsertItem(item);

  Future<void> rename(String id, String name) async {
    final it = byId(id);
    if (it != null && name.trim().isNotEmpty) {
      await save(it.copyWith(name: name.trim()));
    }
  }

  Future<void> reorder(List<String> orderedIds) => channel.setOrder(orderedIds);

  Future<void> remove(String id) async {
    await channel.deleteItem(id);
    await store.delete(id);
    await _checkIntegrity();
  }

  Future<int> usedBytes() => store.totalBytes();

  Future<void> clearLocalCache() async {
    await store.clear();
    await _checkIntegrity();
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    items.dispose();
    health.dispose();
    jobs.dispose();
  }
}
