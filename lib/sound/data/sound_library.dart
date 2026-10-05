// lib/sound/data/sound_library.dart
//
// Biblioteca de sunete: metadatele sunt în baza de date, fișierele în magazia
// locală persistentă (copiate la import, nu doar calea din selector). Pentru
// sunetele video, imaginea de pe display NU vine din aplicație: vine din linkul
// (Google Drive) scris în baza de date, în câmpul `videoUrl` al sunetului.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/drive_link.dart';
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
    });
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
    String? videoLink,
  }) {
    final created = <ImportJob>[];
    for (final f in files) {
      final job = ImportJob(++_jobSeq, f.name);
      created.add(job);
    }
    jobs.value = <ImportJob>[...jobs.value, ...created];
    unawaited(_runImports(files, created, forceType, nameOverride, videoLink));
    return created;
  }

  Future<void> _runImports(List<PickedMedia> files, List<ImportJob> js,
      SoundType? forceType, String? nameOverride, String? videoLink) async {
    for (var i = 0; i < files.length; i++) {
      await _importOne(files[i], js[i], forceType,
          files.length == 1 ? nameOverride : null,
          files.length == 1 ? videoLink : null);
    }
  }

  Future<void> _importOne(PickedMedia f, ImportJob job, SoundType? forceType,
      String? name, String? videoLink) async {
    job.state.value = JobState.working;
    try {
      final err = validate(f);
      if (err != null) throw StateError(err);

      final type = forceType ?? detectType(f)!;

      // video: linkul (Google Drive) din care displayul își ia imaginea; se
      // verifică ÎNAINTE de orice copiere locală
      String? videoUrl;
      if (type == SoundType.video) {
        final link = (videoLink ?? '').trim();
        final linkErr = DriveLink.validate(link);
        if (linkErr != null) throw StateError(linkErr);
        if (link.isNotEmpty) videoUrl = link;
      }

      final free = await store.freeBytes();
      if (free != null && free < f.bytes.length * 1.3) {
        throw StateError('Spațiu insuficient în browser pentru „${f.name}” '
            '(liber ≈ ${(free / (1024 * 1024)).floor()} MB).');
      }

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

      // 3) video: displayul își ia imaginea din linkul Google Drive scris în baza
      // de date (`videoUrl`), nu din aplicație
      final title = (name != null && name.trim().isNotEmpty) ? name.trim() : f.baseName;
      if (type == SoundType.video && videoUrl == null) {
        // sunetul funcționează (audio local); displayul n-are imagine până se pune linkul
        job.error = 'Video fără link: displayul nu va avea imaginea. Deschide '
            '„Editează” la acest sunet și lipește linkul Google Drive.';
      }
      job.progress.value = 0.9;

      final order = items.value.isEmpty
          ? 0
          : items.value.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

      final item = SoundItem(
        id: id,
        name: title,
        type: type,
        videoUrl: videoUrl,
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
