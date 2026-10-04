// lib/sound/core/clock_sync.dart
//
// Ceas comun control ↔ display. DART PUR.
//
// Fiecare client estimează offsetul dintre ceasul lui MONOTON (Stopwatch) și
// ceasul serverului:   serverNow = monoMs + offset
// Se fac mai multe probe (burst); fiecare probă are un RTT. Probele cu RTT mic
// sunt cele mai de încredere (întârzierea dus/întors e aproape simetrică), deci
// se ia MEDIANA offseturilor din cele mai bune probe. Reîmprospătare la 30–60 s.

import 'dart:async';

import 'sync_math.dart';

/// Rezultatul unei probe: timpul serverului la procesarea cererii + momentele
/// locale (monotone, µs) de trimitere și de primire a confirmării.
class ProbeResult {
  final int serverMs;
  final int sentUs;
  final int receivedUs;

  const ProbeResult({
    required this.serverMs,
    required this.sentUs,
    required this.receivedUs,
  });

  int get rttUs => receivedUs - sentUs;
}

/// Sursa timpului de server (implementată peste baza de date realtime).
abstract class ServerTimeProbe {
  /// O probă dus-întors. [clock] e ceasul monoton al clientului.
  Future<ProbeResult> probe(MonoClock clock);

  /// Un offset estimat de baza de date (ex. Firebase `.info/serverTimeOffset`),
  /// față de DateTime.now(). null dacă nu există.
  Future<int?> wallClockOffsetHintMs();
}

class ClockSample {
  final double offsetMs;
  final double rttMs;
  const ClockSample(this.offsetMs, this.rttMs);
}

/// Estimator pur: păstrează ultimele [maxSamples] probe și calculează mediana
/// offseturilor din fracția [keepFraction] cu RTT cel mai mic.
class ClockOffsetEstimator {
  final int maxSamples;
  final double keepFraction;
  final List<ClockSample> _samples = <ClockSample>[];

  ClockOffsetEstimator({this.maxSamples = 24, this.keepFraction = 0.4})
      : assert(maxSamples >= 3),
        assert(keepFraction > 0 && keepFraction <= 1);

  int get sampleCount => _samples.length;

  void add(ClockSample s) {
    if (s.rttMs < 0) return; // probă invalidă
    _samples.add(s);
    if (_samples.length > maxSamples) _samples.removeAt(0);
  }

  void clear() => _samples.clear();

  /// Cel mai mic RTT din probele curente (ms), sau null.
  double? get bestRttMs {
    if (_samples.isEmpty) return null;
    double best = _samples.first.rttMs;
    for (final s in _samples) {
      if (s.rttMs < best) best = s.rttMs;
    }
    return best;
  }

  /// Offset estimat (ms) sau null dacă nu există probe.
  double? get offsetMs {
    if (_samples.isEmpty) return null;
    final sorted = List<ClockSample>.of(_samples)
      ..sort((a, b) => a.rttMs.compareTo(b.rttMs));
    var keep = (sorted.length * keepFraction).ceil();
    if (keep < 3) keep = sorted.length < 3 ? sorted.length : 3;
    final best = sorted.take(keep).map((s) => s.offsetMs).toList()..sort();
    final mid = best.length ~/ 2;
    return best.length.isOdd ? best[mid] : (best[mid - 1] + best[mid]) / 2;
  }
}

/// Serviciul de ceas comun.
class ClockSync {
  final MonoClock mono;
  final ServerTimeProbe source;
  final ClockOffsetEstimator _est;
  final int probesPerBurst;
  final Duration probeSpacing;
  final Duration refreshEvery;

  /// Funcție care dă ceasul de perete local (injectabilă în teste).
  final int Function() wallClockMs;

  double _offsetMs = 0;
  bool _hasEstimate = false;
  Timer? _timer;
  bool _disposed = false;
  bool _bursting = false;

  ClockSync({
    required this.mono,
    required this.source,
    ClockOffsetEstimator? estimator,
    this.probesPerBurst = 8,
    this.probeSpacing = const Duration(milliseconds: 80),
    this.refreshEvery = const Duration(seconds: 45),
    int Function()? wallClockMs,
  })  : _est = estimator ?? ClockOffsetEstimator(),
        wallClockMs = wallClockMs ?? _defaultWall;

  static int _defaultWall() => DateTime.now().millisecondsSinceEpoch;

  /// True după prima estimare (din hint sau din probe).
  bool get isSynced => _hasEstimate;

  double get offsetMs => _offsetMs;

  /// Cel mai bun RTT observat (ms), pentru adaptarea lead-ului.
  int? get bestRttMs {
    final v = _est.bestRttMs;
    return v?.round();
  }

  /// Timpul estimat al serverului (ms epoch).
  int get serverNowMs => (mono.nowUs / 1000 + _offsetMs).round();

  /// Timpul de server corespunzător unui moment monoton local (µs).
  int serverMsAtMonoUs(int monoUs) => (monoUs / 1000 + _offsetMs).round();

  /// Pornește sincronizarea: hint rapid + burst imediat + refresh periodic.
  Future<void> start() async {
    await _applyHint();
    await sync();
    _timer?.cancel();
    _timer = Timer.periodic(refreshEvery, (_) {
      if (!_disposed) sync(probes: (probesPerBurst / 2).ceil());
    });
  }

  Future<void> _applyHint() async {
    try {
      final hint = await source.wallClockOffsetHintMs();
      if (hint == null || _hasEstimate) return;
      // serverNow ≈ wall + hint ⇒ offset față de ceasul monoton:
      _offsetMs = (wallClockMs() + hint) - mono.nowUs / 1000;
      _hasEstimate = true;
    } catch (_) {/* hint-ul e opțional */}
  }

  /// Un burst de probe. Erorile de rețea se ignoră (se păstrează estimarea veche).
  Future<void> sync({int? probes}) async {
    if (_disposed || _bursting) return;
    _bursting = true;
    final n = probes ?? probesPerBurst;
    try {
      for (var i = 0; i < n && !_disposed; i++) {
        try {
          final r = await source.probe(mono);
          final rttMs = r.rttUs / 1000;
          // serverul a procesat cererea la mijlocul dus-întorsului (ipoteză simetrică)
          final localMidMs = (r.sentUs + r.receivedUs) / 2 / 1000;
          _est.add(ClockSample(r.serverMs - localMidMs, rttMs));
        } catch (_) {/* probă pierdută */}
        if (i < n - 1) await Future<void>.delayed(probeSpacing);
      }
      final est = _est.offsetMs;
      if (est != null) {
        _offsetMs = est;
        _hasEstimate = true;
      }
    } finally {
      _bursting = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
