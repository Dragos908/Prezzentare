// lib/sound/data/rtdb_sync_channel.dart
//
// Implementarea SyncChannelPort peste Firebase Realtime Database — aceeași
// bază de date și același proiect ca restul aplicației. Noduri noi (nu
// modifică nimic existent):
//   <proiect>/settings             setările (displayAudioMuted, avSyncOffsetMs…)
//   <proiect>/sound/items/<id>     biblioteca de sunete (metadate)
//   <proiect>/sound/playback       starea de redare (scris la evenimente)
//   <proiect>/sound/heartbeat      poziția reală a audio, ~1/s
//   <proiect>/sound/displayStatus  starea displayului, ~1/s
//   <proiect>/sound/clockProbe/<client>  probe pentru ceasul comun
//
// RTDB nu limitează scrierile la 1/s/nod (spre deosebire de Firestore), dar
// heartbeat-ul stă oricum într-un nod separat, ca stările de eveniment să
// rămână mici.

import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';

import '../../core/firebase_service.dart';
import '../core/clock_sync.dart';
import '../core/models.dart';
import '../core/playlist_logic.dart';
import '../core/ports.dart';
import '../core/sync_math.dart';

class RtdbSyncChannel implements SyncChannelPort {
  final FirebaseDatabase _db;
  final String _project;
  final String _clientId;

  RtdbSyncChannel({String? project, FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance,
        _project = project ?? FirebaseService.instance.currentProject,
        _clientId = _newClientId();

  static String _newClientId() {
    final r = math.Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${r.nextInt(1 << 30).toRadixString(36)}';
  }

  DatabaseReference get _root => _db.ref(_project);
  DatabaseReference get _sound => _root.child('sound');
  DatabaseReference get _settings => _root.child('settings');
  DatabaseReference get _items => _sound.child('items');
  DatabaseReference get _playback => _sound.child('playback');
  DatabaseReference get _heartbeat => _sound.child('heartbeat');
  DatabaseReference get _displayStatus => _sound.child('displayStatus');

  static Map<dynamic, dynamic> _asMap(Object? v) =>
      v is Map ? v : const <dynamic, dynamic>{};

  // ── setări ────────────────────────────────────────────────────────────────
  @override
  Stream<AppSettings> settingsStream() => _settings.onValue
      .map((e) => AppSettings.fromJson(_asMap(e.snapshot.value)));

  @override
  Future<void> saveSettings(Map<String, Object?> values) =>
      _settings.update(values);

  // ── biblioteca ────────────────────────────────────────────────────────────
  @override
  Stream<List<SoundItem>> itemsStream() => _items.onValue.map((e) {
        final out = <SoundItem>[];
        _asMap(e.snapshot.value).forEach((k, v) {
          if (v is Map) out.add(SoundItem.fromJson(k.toString(), v));
        });
        return sortedItems(out);
      });

  @override
  Future<void> upsertItem(SoundItem item) =>
      _items.child(item.id).set(item.toJson());

  @override
  Future<void> deleteItem(String id) => _items.child(id).remove();

  @override
  Future<void> setOrder(List<String> orderedIds) {
    final updates = <String, Object?>{};
    for (var i = 0; i < orderedIds.length; i++) {
      updates['${orderedIds[i]}/sortOrder'] = i;
    }
    return _items.update(updates);
  }

  // ── stare de redare + heartbeat ───────────────────────────────────────────
  @override
  Stream<PlaybackState> playbackStream() => _playback.onValue.map((e) {
        final m = _asMap(e.snapshot.value);
        return m.isEmpty ? PlaybackState.idle : PlaybackState.fromJson(m);
      });

  @override
  Future<PlaybackState> readPlayback() async {
    final snap = await _playback.get();
    final m = _asMap(snap.value);
    return m.isEmpty ? PlaybackState.idle : PlaybackState.fromJson(m);
  }

  @override
  Future<void> writePlayback(PlaybackState state) =>
      _playback.set(state.toJson());

  @override
  Stream<Heartbeat> heartbeatStream() => _heartbeat.onValue
      .where((e) => e.snapshot.value is Map)
      .map((e) => Heartbeat.fromJson(_asMap(e.snapshot.value)));

  @override
  Future<void> writeHeartbeat(Heartbeat beat) => _heartbeat.set(beat.toJson());

  // ── display ───────────────────────────────────────────────────────────────
  @override
  Stream<DisplayStatus> displayStatusStream() => _displayStatus.onValue.map(
      (e) => DisplayStatus.fromJson(_asMap(e.snapshot.value)));

  @override
  Future<void> writeDisplayStatus(DisplayStatus status) =>
      _displayStatus.set(status.toJson());

  @override
  Future<void> armDisplayDisconnect() =>
      _displayStatus.onDisconnect().update(<String, Object?>{
        'connected': false,
        'lastSeen': ServerValue.timestamp,
      });

  /// Dacă controlul dispare (tab închis, rețea căzută), serverul scrie singur
  /// „stopped” — displayul își ascunde video-ul chiar dacă nu mai primește nimic.
  @override
  Future<void> armControlDisconnect() =>
      _playback.onDisconnect().set(<String, Object?>{
        'seq': ServerValue.timestamp,
        'itemId': null,
        'status': PlaybackStatus.stopped.name,
        'positionMs': 0,
        'anchorTs': ServerValue.timestamp,
        'rate': 1.0,
        'trimStartMs': 0,
        'trimEndMs': 0,
        'loop': false,
      });

  // ── calibrare A/V ─────────────────────────────────────────────────────────
  @override
  Stream<int> calibrationStream() =>
      _sound.child('calibration').onValue.map((e) {
        final v = _asMap(e.snapshot.value)['startAt'];
        return v is num ? v.toInt() : 0;
      }).where((t) => t > 0);

  @override
  Future<void> triggerCalibration(int startAtTs) =>
      _sound.child('calibration').set(<String, Object?>{
        'startAt': startAtTs,
        'id': _newClientId(),
      });

  // ── ceas comun (ServerTimeProbe) ──────────────────────────────────────────
  @override
  Future<ProbeResult> probe(MonoClock clock) async {
    final ref = _sound.child('clockProbe').child(_clientId);
    final sent = clock.nowUs;
    await ref.set(ServerValue.timestamp); // se termină la confirmarea serverului
    final received = clock.nowUs;
    final snap = await ref.get(); // valoarea rezolvată de server
    final v = snap.value;
    if (v is! num) throw StateError('probă de ceas invalidă');
    return ProbeResult(serverMs: v.toInt(), sentUs: sent, receivedUs: received);
  }

  @override
  Future<int?> wallClockOffsetHintMs() async {
    final snap = await _db.ref('.info/serverTimeOffset').get();
    final v = snap.value;
    return v is num ? v.round() : null;
  }
}
