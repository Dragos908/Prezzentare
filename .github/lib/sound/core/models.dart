// lib/sound/core/models.dart
//
// Modele imutabile pentru sunet + sincronizare. DART PUR (fără Flutter).
// Convenția bazei de date rămâne cea existentă: chei lowerCamelCase.
// Parsarea e tolerantă: câmpurile lipsă primesc valori implicite, deci datele
// vechi / incomplete din Firebase nu pot strica aplicația.

// ─────────────────────────────────────────────────────────────────────────────
// Enum-uri
// ─────────────────────────────────────────────────────────────────────────────
enum SoundType { audio, video }

enum PlaybackStatus { idle, playing, paused, stopped }

enum NextTransition { cut, fadeThenStart, crossfade }

enum AfterFadeOut { stop, pause }

enum FadeCurveKind { natural, linear }

T enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
  }
  return fallback;
}

int _int(Object? v, int fallback) {
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? _intOrNull(Object? v) => v is num ? v.round() : null;

double _dbl(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

String? _strOrNull(Object? v) =>
    (v is String && v.trim().isNotEmpty) ? v : null;

// ─────────────────────────────────────────────────────────────────────────────
// SoundItem (sound_items)
// ─────────────────────────────────────────────────────────────────────────────
class SoundItem {
  final String id;
  final String name;
  final SoundType type;

  /// Doar pentru video: calea fișierului din assets-urile aplicației
  /// (ex. `assets/sound_video/intro.mp4`), redat de display. null = displayul nu
  /// are imagine pentru acest sunet (fișierul nu e inclus în aplicație).
  final String? assetPath;
  final String mime;

  final int durationMs;
  final int trimStartMs;

  /// null = până la sfârșitul fișierului.
  final int? trimEndMs;

  /// Volumul de bază al sunetului (0..1).
  final double volume;

  /// Nivelul (0..1) la care coboară / urcă „Fade la nivel”.
  final double targetLevel;
  final bool loop;

  final int fadeInMs;

  /// null = valoarea implicită din Setări.
  final int? fadeOutMs;
  final int? fadeToLevelMs;

  final int color; // ARGB
  final int sortOrder;
  final int createdAt;

  const SoundItem({
    required this.id,
    required this.name,
    required this.type,
    this.assetPath,
    this.mime = '',
    this.durationMs = 0,
    this.trimStartMs = 0,
    this.trimEndMs,
    this.volume = 1.0,
    this.targetLevel = 0.2,
    this.loop = false,
    this.fadeInMs = 0,
    this.fadeOutMs,
    this.fadeToLevelMs,
    this.color = 0xFF6C63FF,
    this.sortOrder = 0,
    this.createdAt = 0,
  });

  bool get isVideo => type == SoundType.video;

  /// Sfârșitul efectiv al zonei redate (după tăiere), în ms.
  int get effectiveTrimEndMs {
    final end = trimEndMs ?? durationMs;
    if (end <= trimStartMs) return durationMs > trimStartMs ? durationMs : trimStartMs;
    return end;
  }

  /// Lungimea zonei redate, în ms (≥ 0).
  int get trimLengthMs {
    final len = effectiveTrimEndMs - trimStartMs;
    return len < 0 ? 0 : len;
  }

  static const Object _keep = Object();

  SoundItem copyWith({
    String? name,
    SoundType? type,
    Object? assetPath = _keep,
    String? mime,
    int? durationMs,
    int? trimStartMs,
    Object? trimEndMs = _keep,
    double? volume,
    double? targetLevel,
    bool? loop,
    int? fadeInMs,
    Object? fadeOutMs = _keep,
    Object? fadeToLevelMs = _keep,
    int? color,
    int? sortOrder,
  }) {
    return SoundItem(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      assetPath: identical(assetPath, _keep) ? this.assetPath : assetPath as String?,
      mime: mime ?? this.mime,
      durationMs: durationMs ?? this.durationMs,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: identical(trimEndMs, _keep) ? this.trimEndMs : trimEndMs as int?,
      volume: volume ?? this.volume,
      targetLevel: targetLevel ?? this.targetLevel,
      loop: loop ?? this.loop,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: identical(fadeOutMs, _keep) ? this.fadeOutMs : fadeOutMs as int?,
      fadeToLevelMs:
          identical(fadeToLevelMs, _keep) ? this.fadeToLevelMs : fadeToLevelMs as int?,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
    );
  }

  factory SoundItem.fromJson(String id, Map<dynamic, dynamic> j) {
    return SoundItem(
      id: id,
      name: (j['name'] as String?)?.trim().isNotEmpty == true
          ? (j['name'] as String).trim()
          : 'Sunet',
      type: enumByName(SoundType.values, j['type'], SoundType.audio),
      assetPath: _strOrNull(j['assetPath']),
      mime: (j['mime'] as String?) ?? '',
      durationMs: _int(j['durationMs'], 0),
      trimStartMs: _int(j['trimStartMs'], 0),
      trimEndMs: _intOrNull(j['trimEndMs']),
      volume: _dbl(j['volume'], 1.0).clamp(0.0, 1.0).toDouble(),
      targetLevel: _dbl(j['targetLevel'], 0.2).clamp(0.0, 1.0).toDouble(),
      loop: _bool(j['loop'], false),
      fadeInMs: _int(j['fadeInMs'], 0),
      fadeOutMs: _intOrNull(j['fadeOutMs']),
      fadeToLevelMs: _intOrNull(j['fadeToLevelMs']),
      color: _int(j['color'], 0xFF6C63FF),
      sortOrder: _int(j['sortOrder'], 0),
      createdAt: _int(j['createdAt'], 0),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type.name,
        if (assetPath != null) 'assetPath': assetPath,
        'mime': mime,
        'durationMs': durationMs,
        'trimStartMs': trimStartMs,
        if (trimEndMs != null) 'trimEndMs': trimEndMs,
        'volume': volume,
        'targetLevel': targetLevel,
        'loop': loop,
        'fadeInMs': fadeInMs,
        if (fadeOutMs != null) 'fadeOutMs': fadeOutMs,
        if (fadeToLevelMs != null) 'fadeToLevelMs': fadeToLevelMs,
        'color': color,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// PlaybackState (playback_state) — scris la fiecare EVENIMENT, nu la fiecare cadru
// ─────────────────────────────────────────────────────────────────────────────
class PlaybackState {
  /// Crește mereu (ms de server la momentul evenimentului, forțat monoton).
  final int seq;
  final String? itemId;
  final PlaybackStatus status;

  /// Poziția audio la momentul [anchorTs].
  final int positionMs;

  /// Timp de SERVER (ms epoch) la care poziția era [positionMs].
  /// La „Play” poate fi în viitor (start programat).
  final int anchorTs;
  final double rate;
  final int trimStartMs;
  final int trimEndMs;
  final bool loop;

  /// Doar pentru fade-ul opțional al imaginii.
  final int? fadeOutStartTs;
  final int? fadeOutMs;

  const PlaybackState({
    required this.seq,
    required this.itemId,
    required this.status,
    required this.positionMs,
    required this.anchorTs,
    this.rate = 1.0,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.loop = false,
    this.fadeOutStartTs,
    this.fadeOutMs,
  });

  static const PlaybackState idle = PlaybackState(
    seq: 0,
    itemId: null,
    status: PlaybackStatus.idle,
    positionMs: 0,
    anchorTs: 0,
  );

  bool get isActive =>
      itemId != null &&
      (status == PlaybackStatus.playing || status == PlaybackStatus.paused);

  PlaybackState copyWith({
    int? seq,
    PlaybackStatus? status,
    int? positionMs,
    int? anchorTs,
    double? rate,
    bool clearFade = false,
    int? fadeOutStartTs,
    int? fadeOutMs,
  }) {
    return PlaybackState(
      seq: seq ?? this.seq,
      itemId: itemId,
      status: status ?? this.status,
      positionMs: positionMs ?? this.positionMs,
      anchorTs: anchorTs ?? this.anchorTs,
      rate: rate ?? this.rate,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
      loop: loop,
      fadeOutStartTs: clearFade ? null : (fadeOutStartTs ?? this.fadeOutStartTs),
      fadeOutMs: clearFade ? null : (fadeOutMs ?? this.fadeOutMs),
    );
  }

  factory PlaybackState.fromJson(Map<dynamic, dynamic> j) {
    return PlaybackState(
      seq: _int(j['seq'], 0),
      itemId: _strOrNull(j['itemId']),
      status: enumByName(PlaybackStatus.values, j['status'], PlaybackStatus.idle),
      positionMs: _int(j['positionMs'], 0),
      anchorTs: _int(j['anchorTs'], 0),
      rate: _dbl(j['rate'], 1.0),
      trimStartMs: _int(j['trimStartMs'], 0),
      trimEndMs: _int(j['trimEndMs'], 0),
      loop: _bool(j['loop'], false),
      fadeOutStartTs: _intOrNull(j['fadeOutStartTs']),
      fadeOutMs: _intOrNull(j['fadeOutMs']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'itemId': itemId,
        'status': status.name,
        'positionMs': positionMs,
        'anchorTs': anchorTs,
        'rate': rate,
        'trimStartMs': trimStartMs,
        'trimEndMs': trimEndMs,
        'loop': loop,
        'fadeOutStartTs': fadeOutStartTs,
        'fadeOutMs': fadeOutMs,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Heartbeat — poziția reală a audio, ~1/s, într-un nod separat
// ─────────────────────────────────────────────────────────────────────────────
class Heartbeat {
  final int seq;
  final String? itemId;
  final PlaybackStatus status;
  final int positionMs;

  /// Timp de server la care s-a măsurat [positionMs].
  final int anchorTs;
  final double rate;

  const Heartbeat({
    required this.seq,
    required this.itemId,
    required this.status,
    required this.positionMs,
    required this.anchorTs,
    this.rate = 1.0,
  });

  factory Heartbeat.fromJson(Map<dynamic, dynamic> j) => Heartbeat(
        seq: _int(j['seq'], 0),
        itemId: _strOrNull(j['itemId']),
        status: enumByName(PlaybackStatus.values, j['status'], PlaybackStatus.idle),
        positionMs: _int(j['positionMs'], 0),
        anchorTs: _int(j['anchorTs'], 0),
        rate: _dbl(j['rate'], 1.0),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'itemId': itemId,
        'status': status.name,
        'positionMs': positionMs,
        'anchorTs': anchorTs,
        'rate': rate,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// DisplayStatus (display_status) — scris de display la ~1 s
// ─────────────────────────────────────────────────────────────────────────────
class DisplayStatus {
  final bool connected;
  final int lastSeen; // timp de server
  final bool ready;
  final bool buffering;
  final String? itemId;
  final int positionMs;
  final int driftMs;

  // audio_guard
  final bool guardActive;
  final int guardPlayers;
  final int guardUnmuted;
  final int embedsUnmutable;

  const DisplayStatus({
    this.connected = false,
    this.lastSeen = 0,
    this.ready = false,
    this.buffering = false,
    this.itemId,
    this.positionMs = 0,
    this.driftMs = 0,
    this.guardActive = false,
    this.guardPlayers = 0,
    this.guardUnmuted = 0,
    this.embedsUnmutable = 0,
  });

  factory DisplayStatus.fromJson(Map<dynamic, dynamic> j) {
    final g = j['audioGuard'];
    final guard = g is Map ? g : const <dynamic, dynamic>{};
    return DisplayStatus(
      connected: _bool(j['connected'], false),
      lastSeen: _int(j['lastSeen'], 0),
      ready: _bool(j['ready'], false),
      buffering: _bool(j['buffering'], false),
      itemId: _strOrNull(j['itemId']),
      positionMs: _int(j['positionMs'], 0),
      driftMs: _int(j['driftMs'], 0),
      guardActive: _bool(guard['active'], false),
      guardPlayers: _int(guard['players'], 0),
      guardUnmuted: _int(guard['unmuted'], 0),
      embedsUnmutable: _int(guard['embedsUnmutable'], 0),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'connected': connected,
        'lastSeen': lastSeen,
        'ready': ready,
        'buffering': buffering,
        'itemId': itemId,
        'positionMs': positionMs,
        'driftMs': driftMs,
        'audioGuard': <String, Object?>{
          'active': guardActive,
          'players': guardPlayers,
          'unmuted': guardUnmuted,
          'embedsUnmutable': embedsUnmutable,
        },
      };

  /// Display considerat online dacă a scris recent (toleranță 4 s).
  bool isOnline(int serverNowMs) =>
      connected && (serverNowMs - lastSeen).abs() <= 4000;
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSettings (settings)
// ─────────────────────────────────────────────────────────────────────────────
class AppSettings {
  // Display & sunet
  final bool displayAudioMuted;
  final bool blockUnmutableEmbeds;
  final String? audioOutputDeviceId;

  // Sincronizare
  final int avSyncOffsetMs;
  final int leadMs;
  final int driftHardMs;
  final int driftSoftMs;
  final int heartbeatMs;

  // Sunet & fade
  final double masterVolume;
  final int defaultFadeInMs;
  final int defaultFadeOutMs;
  final int defaultFadeToLevelMs;
  final double defaultTargetLevel;
  final FadeCurveKind fadeCurve;
  final AfterFadeOut afterFadeOut;
  final bool fadeImageWithAudio;
  final NextTransition nextTransition;
  final int nextFadeMs;
  final bool autoAdvance;
  final bool loopPlaylist;

  // Aspect
  final String padSize; // small | medium | large

  // Scurtături: acțiune → tastă (etichetă, ex. „Escape”, „F”)
  final Map<String, String> shortcuts;

  static const Map<String, String> defaultShortcuts = <String, String>{
    'stopAll': 'Escape',
    'fadeOut': 'F',
    'fadeToLevel': 'L',
    'next': 'N',
    'previous': 'B',
    'restart': 'Z',
  };

  const AppSettings({
    this.displayAudioMuted = true,
    this.blockUnmutableEmbeds = false,
    this.audioOutputDeviceId,
    this.avSyncOffsetMs = 0,
    this.leadMs = 400,
    this.driftHardMs = 200,
    this.driftSoftMs = 40,
    this.heartbeatMs = 1000,
    this.masterVolume = 1.0,
    this.defaultFadeInMs = 0,
    this.defaultFadeOutMs = 5000,
    this.defaultFadeToLevelMs = 3000,
    this.defaultTargetLevel = 0.2,
    this.fadeCurve = FadeCurveKind.natural,
    this.afterFadeOut = AfterFadeOut.stop,
    this.fadeImageWithAudio = false,
    this.nextTransition = NextTransition.cut,
    this.nextFadeMs = 3000,
    this.autoAdvance = false,
    this.loopPlaylist = false,
    this.padSize = 'medium',
    this.shortcuts = defaultShortcuts,
  });

  AppSettings copyWith({
    bool? displayAudioMuted,
    bool? blockUnmutableEmbeds,
    Object? audioOutputDeviceId = SoundItem._keep,
    int? avSyncOffsetMs,
    int? leadMs,
    int? driftHardMs,
    int? driftSoftMs,
    int? heartbeatMs,
    double? masterVolume,
    int? defaultFadeInMs,
    int? defaultFadeOutMs,
    int? defaultFadeToLevelMs,
    double? defaultTargetLevel,
    FadeCurveKind? fadeCurve,
    AfterFadeOut? afterFadeOut,
    bool? fadeImageWithAudio,
    NextTransition? nextTransition,
    int? nextFadeMs,
    bool? autoAdvance,
    bool? loopPlaylist,
    String? padSize,
    Map<String, String>? shortcuts,
  }) {
    return AppSettings(
      displayAudioMuted: displayAudioMuted ?? this.displayAudioMuted,
      blockUnmutableEmbeds: blockUnmutableEmbeds ?? this.blockUnmutableEmbeds,
      audioOutputDeviceId: identical(audioOutputDeviceId, SoundItem._keep)
          ? this.audioOutputDeviceId
          : audioOutputDeviceId as String?,
      avSyncOffsetMs: avSyncOffsetMs ?? this.avSyncOffsetMs,
      leadMs: leadMs ?? this.leadMs,
      driftHardMs: driftHardMs ?? this.driftHardMs,
      driftSoftMs: driftSoftMs ?? this.driftSoftMs,
      heartbeatMs: heartbeatMs ?? this.heartbeatMs,
      masterVolume: masterVolume ?? this.masterVolume,
      defaultFadeInMs: defaultFadeInMs ?? this.defaultFadeInMs,
      defaultFadeOutMs: defaultFadeOutMs ?? this.defaultFadeOutMs,
      defaultFadeToLevelMs: defaultFadeToLevelMs ?? this.defaultFadeToLevelMs,
      defaultTargetLevel: defaultTargetLevel ?? this.defaultTargetLevel,
      fadeCurve: fadeCurve ?? this.fadeCurve,
      afterFadeOut: afterFadeOut ?? this.afterFadeOut,
      fadeImageWithAudio: fadeImageWithAudio ?? this.fadeImageWithAudio,
      nextTransition: nextTransition ?? this.nextTransition,
      nextFadeMs: nextFadeMs ?? this.nextFadeMs,
      autoAdvance: autoAdvance ?? this.autoAdvance,
      loopPlaylist: loopPlaylist ?? this.loopPlaylist,
      padSize: padSize ?? this.padSize,
      shortcuts: shortcuts ?? this.shortcuts,
    );
  }

  factory AppSettings.fromJson(Map<dynamic, dynamic> j) {
    const d = AppSettings();
    final rawShortcuts = j['shortcuts'];
    final shortcuts = Map<String, String>.from(defaultShortcuts);
    if (rawShortcuts is Map) {
      rawShortcuts.forEach((k, v) {
        if (k is String && v is String && v.trim().isNotEmpty) {
          shortcuts[k] = v.trim();
        }
      });
    }
    int ms(String key, int fallback, {int min = 0, int max = 60000}) =>
        _int(j[key], fallback).clamp(min, max).toInt();

    return AppSettings(
      displayAudioMuted: _bool(j['displayAudioMuted'], d.displayAudioMuted),
      blockUnmutableEmbeds: _bool(j['blockUnmutableEmbeds'], d.blockUnmutableEmbeds),
      audioOutputDeviceId: _strOrNull(j['audioOutputDeviceId']),
      avSyncOffsetMs: ms('avSyncOffsetMs', d.avSyncOffsetMs, min: -2000, max: 2000),
      leadMs: ms('leadMs', d.leadMs, min: 100, max: 3000),
      driftHardMs: ms('driftHardMs', d.driftHardMs, min: 60, max: 2000),
      driftSoftMs: ms('driftSoftMs', d.driftSoftMs, min: 10, max: 500),
      heartbeatMs: ms('heartbeatMs', d.heartbeatMs, min: 250, max: 5000),
      masterVolume: _dbl(j['masterVolume'], d.masterVolume).clamp(0.0, 1.0).toDouble(),
      defaultFadeInMs: ms('defaultFadeInMs', d.defaultFadeInMs, max: 30000),
      defaultFadeOutMs: ms('defaultFadeOutMs', d.defaultFadeOutMs, min: 500, max: 30000),
      defaultFadeToLevelMs:
          ms('defaultFadeToLevelMs', d.defaultFadeToLevelMs, min: 500, max: 30000),
      defaultTargetLevel:
          _dbl(j['defaultTargetLevel'], d.defaultTargetLevel).clamp(0.0, 1.0).toDouble(),
      fadeCurve: enumByName(FadeCurveKind.values, j['fadeCurve'], d.fadeCurve),
      afterFadeOut: enumByName(AfterFadeOut.values, j['afterFadeOut'], d.afterFadeOut),
      fadeImageWithAudio: _bool(j['fadeImageWithAudio'], d.fadeImageWithAudio),
      nextTransition:
          enumByName(NextTransition.values, j['nextTransition'], d.nextTransition),
      nextFadeMs: ms('nextFadeMs', d.nextFadeMs, min: 500, max: 30000),
      autoAdvance: _bool(j['autoAdvance'], d.autoAdvance),
      loopPlaylist: _bool(j['loopPlaylist'], d.loopPlaylist),
      padSize: (j['padSize'] is String &&
              const ['small', 'medium', 'large'].contains(j['padSize']))
          ? j['padSize'] as String
          : d.padSize,
      shortcuts: shortcuts,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'displayAudioMuted': displayAudioMuted,
        'blockUnmutableEmbeds': blockUnmutableEmbeds,
        'audioOutputDeviceId': audioOutputDeviceId,
        'avSyncOffsetMs': avSyncOffsetMs,
        'leadMs': leadMs,
        'driftHardMs': driftHardMs,
        'driftSoftMs': driftSoftMs,
        'heartbeatMs': heartbeatMs,
        'masterVolume': masterVolume,
        'defaultFadeInMs': defaultFadeInMs,
        'defaultFadeOutMs': defaultFadeOutMs,
        'defaultFadeToLevelMs': defaultFadeToLevelMs,
        'defaultTargetLevel': defaultTargetLevel,
        'fadeCurve': fadeCurve.name,
        'afterFadeOut': afterFadeOut.name,
        'fadeImageWithAudio': fadeImageWithAudio,
        'nextTransition': nextTransition.name,
        'nextFadeMs': nextFadeMs,
        'autoAdvance': autoAdvance,
        'loopPlaylist': loopPlaylist,
        'padSize': padSize,
        'shortcuts': shortcuts,
      };
}
