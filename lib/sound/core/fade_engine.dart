// lib/sound/core/fade_engine.dart
//
// FadeController — singurul serviciu care execută rampe de volum. DART PUR.
//
//  • valoarea rampei se CALCULEAZĂ din ceasul monoton:
//        valoare = from + (to − from) × curbă(t / durată)
//    (nu se incrementează un contor, deci nu derivează dacă un tick întârzie);
//  • ultimul pas e EXACT la țintă;
//  • o rampă nouă pornește din volumul curent real (fără salturi);
//  • o rampă activă e anulată de: altă rampă pe același canal, mutarea manuală
//    a slider-ului (setVolume), „Oprește tot" (cancelAll).

import 'dart:async';

import 'models.dart';
import 'sync_math.dart';

/// Forma rampei. „natural” = pătratică (amplitudine ~ t² la intrare și
/// 1−(1−t)² la ieșire): sună mai uniform decât cea liniară, fără „tăiere” la final.
double fadeShape(FadeCurveKind kind, double t, {required bool rising}) {
  final x = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  if (kind == FadeCurveKind.linear) return x;
  return rising ? x * x : 1 - (1 - x) * (1 - x);
}

class Ramp {
  final double from;
  final double to;
  final int startUs;
  final int durationUs;
  final FadeCurveKind curve;

  /// Etichetă liberă pentru cel care a cerut rampa (ex. „toLevel”, „fadeOut”).
  final Object? tag;

  const Ramp({
    required this.from,
    required this.to,
    required this.startUs,
    required this.durationUs,
    required this.curve,
    this.tag,
  });

  bool get rising => to > from;

  double valueAt(int nowUs) {
    if (durationUs <= 0) return to;
    final t = (nowUs - startUs) / durationUs;
    if (t >= 1) return to; // ultimul pas, exact la țintă
    if (t <= 0) return from;
    return from + (to - from) * fadeShape(curve, t, rising: rising);
  }

  bool isDone(int nowUs) => nowUs - startUs >= durationUs;

  int remainingMs(int nowUs) {
    final left = durationUs - (nowUs - startUs);
    return left <= 0 ? 0 : (left / 1000).ceil();
  }
}

typedef FadeValueCallback = void Function(String channelId, double value);
typedef FadeDoneCallback = void Function(String channelId, Object? tag);

class FadeController {
  final MonoClock clock;
  final FadeValueCallback? onValue;
  final FadeDoneCallback? onComplete;

  final Map<String, double> _values = <String, double>{};
  final Map<String, Ramp> _ramps = <String, Ramp>{};
  Timer? _ticker;

  FadeController({required this.clock, this.onValue, this.onComplete});

  /// Volumul curent al canalului (0..1). Un canal necunoscut are [fallback].
  double volumeOf(String id, {double fallback = 1.0}) => _values[id] ?? fallback;

  bool isRamping(String id) => _ramps.containsKey(id);

  Ramp? rampOf(String id) => _ramps[id];

  int remainingMs(String id) => _ramps[id]?.remainingMs(clock.nowUs) ?? 0;

  bool get hasActiveRamps => _ramps.isNotEmpty;

  /// Setare imediată (ex. mutarea manuală a slider-ului): anulează rampa, fără
  /// să apeleze onComplete (rampa a fost întreruptă, nu terminată).
  void setVolume(String id, double v) {
    final x = v.clamp(0.0, 1.0).toDouble();
    _ramps.remove(id);
    _values[id] = x;
    onValue?.call(id, x);
    _maybeStopTicker();
  }

  /// Pornește o rampă din volumul curent real (sau din [from], dacă e dat).
  void ramp(
    String id, {
    double? from,
    required double to,
    required int durationMs,
    FadeCurveKind curve = FadeCurveKind.natural,
    Object? tag,
  }) {
    final start = from ?? volumeOf(id);
    final target = to.clamp(0.0, 1.0).toDouble();
    _values[id] = start.clamp(0.0, 1.0).toDouble();

    if (durationMs <= 0) {
      _ramps.remove(id);
      _values[id] = target;
      onValue?.call(id, target);
      onComplete?.call(id, tag);
      _maybeStopTicker();
      return;
    }

    _ramps[id] = Ramp(
      from: _values[id]!,
      to: target,
      startUs: clock.nowUs,
      durationUs: durationMs * 1000,
      curve: curve,
      tag: tag,
    );
    _ensureTicker();
  }

  /// Oprește rampa; volumul rămâne unde a ajuns. Returnează true dacă era activă.
  bool cancel(String id) {
    final had = _ramps.remove(id) != null;
    _maybeStopTicker();
    return had;
  }

  void cancelAll() {
    _ramps.clear();
    _maybeStopTicker();
  }

  /// Uită un canal (după oprirea sunetului).
  void forget(String id) {
    _ramps.remove(id);
    _values.remove(id);
    _maybeStopTicker();
  }

  /// Un pas de calcul. Public ca testele și UI-ul să-l poată apela direct.
  void tick() {
    if (_ramps.isEmpty) return;
    final now = clock.nowUs;
    final finished = <String>[];
    // copiem cheile: callback-urile pot porni/anula rampe în timpul iterației
    for (final id in List<String>.of(_ramps.keys)) {
      final r = _ramps[id];
      if (r == null) continue;
      final v = r.valueAt(now);
      _values[id] = v;
      onValue?.call(id, v);
      if (r.isDone(now)) finished.add(id);
    }
    for (final id in finished) {
      final r = _ramps[id];
      // Dacă între timp s-a pornit altă rampă pe același canal, nu o finalizăm.
      if (r == null || !r.isDone(now)) continue;
      _ramps.remove(id);
      _values[id] = r.to;
      onComplete?.call(id, r.tag);
    }
    _maybeStopTicker();
  }

  // ── Driver (Timer) ────────────────────────────────────────────────────────
  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 20), (_) => tick());
  }

  void _maybeStopTicker() {
    if (_ramps.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _ramps.clear();
    _values.clear();
  }
}
