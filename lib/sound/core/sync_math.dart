// lib/sound/core/sync_math.dart
//
// Logica de sincronizare audio (control) ↔ video (display). DART PUR.
//
//  • expectedPositionMs  — poziția la care TREBUIE să fie video acum
//  • signedDriftMs       — cât e video înaintea (+) / în urma (−) poziției așteptate
//  • DriftController     — decide: nimic / ajustare fină a vitezei / seek
//  • SeqGate             — ignoră actualizările cu seq mai vechi

import 'models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ceas monoton (Stopwatch) — NU DateTime.now(), care poate sări
// ─────────────────────────────────────────────────────────────────────────────
abstract class MonoClock {
  int get nowUs;
  int get nowMs => nowUs ~/ 1000;
}

class SystemMonoClock implements MonoClock {
  final Stopwatch _sw = Stopwatch()..start();

  @override
  int get nowUs => _sw.elapsedMicroseconds;

  @override
  int get nowMs => nowUs ~/ 1000;
}

/// Ceas manual, pentru teste.
class ManualClock implements MonoClock {
  int _us;
  ManualClock([this._us = 0]);

  @override
  int get nowUs => _us;

  @override
  int get nowMs => _us ~/ 1000;

  void advanceMs(num ms) => _us += (ms * 1000).round();
}

// ─────────────────────────────────────────────────────────────────────────────
// Instantaneu de sincronizare (din PlaybackState sau din Heartbeat)
// ─────────────────────────────────────────────────────────────────────────────
class SyncSnapshot {
  final int seq;
  final String? itemId;
  final PlaybackStatus status;
  final int positionMs;
  final int anchorTs;
  final double rate;
  final int trimStartMs;
  final int trimEndMs;
  final bool loop;

  const SyncSnapshot({
    required this.seq,
    required this.itemId,
    required this.status,
    required this.positionMs,
    required this.anchorTs,
    required this.rate,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.loop,
  });

  factory SyncSnapshot.fromState(PlaybackState s) => SyncSnapshot(
        seq: s.seq,
        itemId: s.itemId,
        status: s.status,
        positionMs: s.positionMs,
        anchorTs: s.anchorTs,
        rate: s.rate,
        trimStartMs: s.trimStartMs,
        trimEndMs: s.trimEndMs,
        loop: s.loop,
      );

  /// Heartbeat-ul aduce poziția reală; zona de tăiere vine din starea curentă.
  factory SyncSnapshot.fromHeartbeat(Heartbeat h, PlaybackState base) =>
      SyncSnapshot(
        seq: h.seq,
        itemId: h.itemId,
        status: h.status,
        positionMs: h.positionMs,
        anchorTs: h.anchorTs,
        rate: h.rate,
        trimStartMs: base.trimStartMs,
        trimEndMs: base.trimEndMs,
        loop: base.loop,
      );

  int get windowMs => trimEndMs - trimStartMs;
}

/// Poziția „brută” (fără limitare la capăt) la timpul de server [serverNowMs].
/// Înainte de [SyncSnapshot.anchorTs] (start programat) rămâne la poziția de start.
double rawExpectedPositionMs(SyncSnapshot s, int serverNowMs) {
  if (s.status != PlaybackStatus.playing) return s.positionMs.toDouble();
  final elapsed = (serverNowMs - s.anchorTs) * s.rate;
  if (elapsed <= 0) return s.positionMs.toDouble();
  return s.positionMs + elapsed;
}

/// Poziția așteptată, respectând tăierea și bucla.
int expectedPositionMs(SyncSnapshot s, int serverNowMs) {
  final raw = rawExpectedPositionMs(s, serverNowMs);
  if (s.status != PlaybackStatus.playing) return raw.round();
  final window = s.windowMs;
  if (window <= 0) return s.trimStartMs;
  if (s.loop) {
    final rel = (raw - s.trimStartMs) % window; // Dart: rezultat ≥ 0
    return (s.trimStartMs + rel).round();
  }
  return raw > s.trimEndMs ? s.trimEndMs : raw.round();
}

/// True dacă un sunet fără buclă a ajuns la sfârșitul zonei redate.
/// Decizia se ia din ACEEAȘI poziție așteptată pe ambele părți (nu din timere
/// independente), deci audio și video se opresc împreună.
bool hasReachedEnd(SyncSnapshot s, int serverNowMs) {
  if (s.loop || s.status != PlaybackStatus.playing) return false;
  if (s.windowMs <= 0) return true;
  return rawExpectedPositionMs(s, serverNowMs) >= s.trimEndMs;
}

/// Drift cu semn: > 0 = video e ÎN FAȚA poziției așteptate.
/// La buclă, diferența se aduce în [−window/2, +window/2] (distanța cea mai scurtă
/// în cerc), ca un heartbeat care trece peste capătul buclei să nu dea seek fals.
int signedDriftMs({
  required int actualMs,
  required int expectedMs,
  int avOffsetMs = 0,
  bool loop = false,
  int windowMs = 0,
}) {
  double d = (actualMs - expectedMs - avOffsetMs).toDouble();
  if (loop && windowMs > 0) {
    d = ((d + windowMs / 2) % windowMs) - windowMs / 2;
  }
  return d.round();
}

// ─────────────────────────────────────────────────────────────────────────────
// DriftController — |drift| > hard → seek; soft…hard → viteză ±2–5 %; < soft → nimic
// ─────────────────────────────────────────────────────────────────────────────
enum DriftActionKind { none, seek, adjustRate, resetRate }

class DriftDecision {
  final DriftActionKind kind;

  /// Pentru [DriftActionKind.seek]: poziția țintă (deja compensată cu latența seek-ului).
  final int? seekToMs;

  /// Viteza de redare de aplicat (1.0 = normal).
  final double rate;

  const DriftDecision(this.kind, {this.seekToMs, this.rate = 1.0});

  static const DriftDecision none = DriftDecision(DriftActionKind.none);
}

class DriftController {
  final int hardMs;
  final int softMs;

  /// Ajustare minimă / maximă a vitezei (fracție: 0.02 = 2 %).
  final double minRateDelta;
  final double maxRateDelta;

  /// Compensare pentru timpul cât durează un seek până la primul cadru afișat.
  final int seekLeadMs;

  bool _adjusting = false;

  DriftController({
    this.hardMs = 200,
    this.softMs = 40,
    this.minRateDelta = 0.02,
    this.maxRateDelta = 0.05,
    this.seekLeadMs = 40,
  }) : assert(hardMs > softMs);

  bool get isAdjusting => _adjusting;

  void reset() => _adjusting = false;

  DriftDecision decide({
    required int driftMs,
    required int expectedMs,
    required bool playing,
  }) {
    if (!playing) {
      return _release();
    }
    final a = driftMs.abs();

    if (a > hardMs) {
      _adjusting = false;
      return DriftDecision(
        DriftActionKind.seek,
        seekToMs: expectedMs + seekLeadMs,
        rate: 1.0,
      );
    }

    if (a > softMs) {
      _adjusting = true;
      return DriftDecision(DriftActionKind.adjustRate, rate: _rateFor(driftMs, a));
    }

    // Histerezis: cât timp ajustăm, continuăm până coborâm sub jumătate de prag,
    // ca viteza să nu oscileze la marginea pragului.
    if (_adjusting && a > softMs ~/ 2) {
      return DriftDecision(DriftActionKind.adjustRate, rate: _rateFor(driftMs, a));
    }
    return _release();
  }

  DriftDecision _release() {
    if (_adjusting) {
      _adjusting = false;
      return const DriftDecision(DriftActionKind.resetRate, rate: 1.0);
    }
    return DriftDecision.none;
  }

  double _rateFor(int driftMs, int a) {
    final span = (hardMs - softMs).toDouble();
    final t = span <= 0 ? 1.0 : ((a - softMs) / span).clamp(0.0, 1.0);
    final delta = minRateDelta + (maxRateDelta - minRateDelta) * t;
    // video înainte (drift > 0) → încetinește; în urmă → accelerează
    return driftMs > 0 ? 1.0 - delta : 1.0 + delta;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SeqGate — ignoră actualizările cu seq mai vechi sau duplicate
// ─────────────────────────────────────────────────────────────────────────────
class SeqGate {
  int _last = -1;

  int get last => _last;

  /// True dacă [seq] e nou (strict mai mare) și actualizarea trebuie aplicată.
  bool accept(int seq) {
    if (seq <= _last) return false;
    _last = seq;
    return true;
  }

  void reset() => _last = -1;
}

/// seq crescător monoton chiar și după repornirea controlului:
/// max(ultimul + 1, timpul serverului în ms).
int nextSeq(int lastSeq, int serverNowMs) {
  final candidate = lastSeq + 1;
  return candidate > serverNowMs ? candidate : serverNowMs;
}

/// Start programat: control și display pornesc la același moment de server.
int scheduledStartTs(int serverNowMs, int leadMs) => serverNowMs + leadMs;

/// Lead adaptat la rețea: cel puțin [baseLeadMs], dar și ≥ 2×RTT + 150 ms, max 1500 ms.
int adaptiveLeadMs({required int baseLeadMs, int? rttMs}) {
  if (rttMs == null) return baseLeadMs;
  final needed = rttMs * 2 + 150;
  final lead = needed > baseLeadMs ? needed : baseLeadMs;
  return lead > 1500 ? 1500 : lead;
}

/// Opacitatea imaginii în timpul fade-out-ului opțional (1 → 0), din ceasul de server.
double imageFadeOpacity({
  required int? fadeStartTs,
  required int? fadeMs,
  required int serverNowMs,
}) {
  if (fadeStartTs == null || fadeMs == null || fadeMs <= 0) return 1.0;
  final t = (serverNowMs - fadeStartTs) / fadeMs;
  if (t <= 0) return 1.0;
  if (t >= 1) return 0.0;
  return 1.0 - t;
}
