// lib/core/firebase/firebase_service.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'model.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final _db = FirebaseDatabase.instance;
  late DatabaseReference _ref;

  bool _initialized = false;
  String _currentProject = 'proiect1';

  /// Proiectul curent activ.
  String get currentProject => _currentProject;

  /// Starea pre-încărcată sincron înainte de runApp.
  PresentationState? cachedState;

  /// Init inițial — apelat din main.dart.
  Future<void> init([String project = 'proiect1']) async {
    if (_initialized) return;
    _initialized = true;
    _currentProject = project;
    _ref = _db.ref(project);

    if (!kIsWeb) {
      _db.setPersistenceEnabled(true);
      _ref.keepSynced(true);
    }

    cachedState = await fetchCurrentState();
  }

  /// Schimbă proiectul activ — apelat din panoul master de control.
  /// Returnează starea pre-încărcată a noului proiect.
  Future<PresentationState?> switchProject(String project) async {
    _currentProject = project;
    _ref = _db.ref(project);

    if (!kIsWeb) {
      _ref.keepSynced(true);
    }

    cachedState = await fetchCurrentState();
    return cachedState;
  }

  // ── Type-safe helpers ─────────────────────────────────────────────────────
  static bool _toBool(dynamic val, {bool fallback = false}) {
    if (val is bool)   return val;
    if (val is int)    return val != 0;
    if (val is String) return val == 'true' || val == '1';
    return fallback;
  }

  static double _toDouble(dynamic val, {double fallback = 1.0}) {
    if (val is double) return val;
    if (val is int)    return val.toDouble();
    if (val is num)    return val.toDouble();
    return fallback;
  }

  static int _toInt(dynamic val, {int fallback = 0}) {
    if (val is int)    return val;
    if (val is double) return val.toInt();
    if (val is num)    return val.toInt();
    return fallback;
  }

  static Iterable<dynamic> _iterableFrom(dynamic val) {
    if (val is List) return val.where((e) => e != null);
    if (val is Map)  return val.values;
    return const [];
  }

  static Map<String, dynamic> _mapEntries(dynamic val) {
    if (val is List) {
      return { for (var i = 0; i < (val as List).length; i++) i.toString(): val[i] };
    }
    return Map<String, dynamic>.from(val as Map);
  }

  // ── STREAMS ───────────────────────────────────────────────────────────────

  Stream<int> get currentSlideStream =>
      _ref.child('currentSlide').onValue
          .map((e) => _toInt(e.snapshot.value));

  Stream<bool> get touchEnabledStream =>
      _ref.child('touchEnabled').onValue
          .map((e) => _toBool(e.snapshot.value, fallback: true));

  Stream<double> get volumeStream =>
      _ref.child('volume').onValue
          .map((e) => _toDouble(e.snapshot.value, fallback: 1.0).clamp(0.0, 1.0));

  Stream<List<SlideModel>> get slidesStream =>
      _ref.child('slides').onValue.map((e) {
        final val = e.snapshot.value;
        if (val == null) return <SlideModel>[];
        return _iterableFrom(val)
            .map((v) => SlideModel.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      });

  Stream<bool> get timerRunningStream =>
      _ref.child('timerRunning').onValue
          .map((e) => _toBool(e.snapshot.value, fallback: false));

  Stream<int> get timerBaseStream =>
      _ref.child('timerBase').onValue
          .map((e) => _toInt(e.snapshot.value));

  Stream<int> get timerStartStream =>
      _ref.child('timerStart').onValue
          .map((e) => _toInt(e.snapshot.value));

  Stream<Map<int, SlideTimerData>> get slideTimersStream =>
      _ref.child('slideTimers').onValue.map((e) {
        final val = e.snapshot.value;
        if (val == null) return <int, SlideTimerData>{};
        return _mapEntries(val).map((k, v) => MapEntry(
          int.parse(k),
          SlideTimerData.fromMap(Map<String, dynamic>.from(v as Map)),
        ));
      });

  Stream<int> get iframePageIndexStream =>
      _ref.child('iframePageIndex').onValue
          .map((e) => _toInt(e.snapshot.value));

  Stream<bool> get overlayEnabledStream =>
      _ref.child('overlayEnabled').onValue
          .map((e) => _toBool(e.snapshot.value, fallback: true));

  // ── WRITE OPERATIONS ──────────────────────────────────────────────────────

  Future<void> setCurrentSlide(int idx, int prevIdx) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ref.runTransaction((data) {
      final map = Map<String, dynamic>.from(data as Map? ?? {});
      map['currentSlide'] = idx;
      map['iframePageIndex'] = 0;

      final rawTimers = map['slideTimers'];
      final Map<String, dynamic> timers;
      if (rawTimers == null) {
        timers = {};
      } else if (rawTimers is List) {
        timers = {};
        for (var i = 0; i < rawTimers.length; i++) {
          if (rawTimers[i] != null) timers[i.toString()] = rawTimers[i];
        }
      } else {
        timers = Map<String, dynamic>.from(rawTimers as Map);
      }

      final prevTimer = timers[prevIdx.toString()];
      if (prevTimer != null) {
        final pt          = Map<String, dynamic>.from(prevTimer as Map);
        final startTs     = pt['startTs'] as int?;
        final accumulated = (pt['accumulated'] as int?) ?? 0;
        if (startTs != null) {
          pt['accumulated'] = accumulated + (now - startTs);
          pt['endTs']       = now;
          pt['startTs']     = null;
        }
        timers[prevIdx.toString()] = pt;
      } else {
        timers[prevIdx.toString()] = {'endTs': now, 'accumulated': 0};
      }

      final newTimer = timers[idx.toString()];
      if (newTimer != null) {
        final nt = Map<String, dynamic>.from(newTimer as Map);
        nt['startTs'] = now;
        nt['endTs']   = null;
        timers[idx.toString()] = nt;
      } else {
        timers[idx.toString()] = {'startTs': now, 'accumulated': 0};
      }

      map['slideTimers'] = timers;
      return Transaction.success(map);
    });
  }

  Future<void> setTouchEnabled(bool val) =>
      _ref.child('touchEnabled').set(val);

  Future<void> setVolume(double val) =>
      _ref.child('volume').set(val.clamp(0.0, 1.0));

  Future<void> setTimerRunning(bool val, {int? base}) async {
    await _ref.child('timerRunning').set(val);
    if (val) {
      await _ref.child('timerStart')
          .set(DateTime.now().millisecondsSinceEpoch);
    }
    if (base != null) await _ref.child('timerBase').set(base);
  }

  Future<void> setIframePageIndex(int idx) =>
      _ref.child('iframePageIndex').set(idx < 0 ? 0 : idx);

  Future<void> setOverlayEnabled(bool val) =>
      _ref.child('overlayEnabled').set(val);

  // ── Pointer laser ─────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get pointerStream =>
      _ref.child('pointer').onValue.map((e) {
        final val = e.snapshot.value;
        if (val == null) return <String, dynamic>{};
        return Map<String, dynamic>.from(val as Map);
      });

  Future<void> setPointer(double x, double y) =>
      _ref.child('pointer').set({
        'x':      x.clamp(0.0, 1.0),
        'y':      y.clamp(0.0, 1.0),
        'active': true,
      });

  Future<void> clearPointer() =>
      _ref.child('pointer').update({'active': false});

  // ── Pointer click ─────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get pointerClickStream =>
      _ref.child('pointerClick').onValue.map((e) {
        final val = e.snapshot.value;
        if (val == null) return <String, dynamic>{};
        return Map<String, dynamic>.from(val as Map);
      });

  Future<void> setPointerClick(double x, double y) =>
      _ref.child('pointerClick').set({
        'x':  x.clamp(0.0, 1.0),
        'y':  y.clamp(0.0, 1.0),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

  Future<String?> fetchControlPassword() async {
    try {
      final snap = await _ref.child('controlPassword').get();
      if (!snap.exists) return null;
      return snap.value?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> initSlides(List<SlideModel> slides) async {
    final map = {for (var s in slides) s.id.toString(): s.toMap()};
    await _ref.child('slides').set(map);
  }

  Future<PresentationState?> fetchCurrentState() async {
    try {
      final snap = await _ref.get();
      if (!snap.exists) return null;
      final raw = Map<String, dynamic>.from(snap.value as Map);

      final slidesRaw = raw['slides'];
      final slides = slidesRaw == null
          ? <SlideModel>[]
          : _iterableFrom(slidesRaw)
          .map((v) => SlideModel.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      final timersRaw = raw['slideTimers'];
      final timers = timersRaw == null
          ? <int, SlideTimerData>{}
          : _mapEntries(timersRaw).map((k, v) => MapEntry(
        int.parse(k),
        SlideTimerData.fromMap(Map<String, dynamic>.from(v as Map)),
      ));

      return PresentationState(
        currentSlide:    _toInt(raw['currentSlide']),
        touchEnabled:    _toBool(raw['touchEnabled'], fallback: true),
        volume:          _toDouble(raw['volume'], fallback: 1.0).clamp(0.0, 1.0),
        timerRunning:    _toBool(raw['timerRunning'], fallback: false),
        timerBase:       _toInt(raw['timerBase']),
        timerStart:      _toInt(raw['timerStart']),
        slides:          slides,
        slideTimers:     timers,
        iframePageIndex: _toInt(raw['iframePageIndex']),
        overlayEnabled:  _toBool(raw['overlayEnabled'], fallback: true),
        pointerX:        _toDouble((raw['pointer'] as Map?)?['x'], fallback: 0.5),
        pointerY:        _toDouble((raw['pointer'] as Map?)?['y'], fallback: 0.5),
        pointerActive:   _toBool((raw['pointer'] as Map?)?['active'], fallback: false),
      );
    } catch (_) {
      return null;
    }
  }
}
