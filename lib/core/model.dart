import 'package:equatable/equatable.dart';
import 'dart:async';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// SlideTimerData
// ─────────────────────────────────────────────
class SlideTimerData extends Equatable {
  final int? startTs;
  final int? endTs;
  final int accumulated;

  const SlideTimerData({this.startTs, this.endTs, this.accumulated = 0});

  factory SlideTimerData.fromMap(Map<String, dynamic> map) => SlideTimerData(
    startTs:     map['startTs'] as int?,
    endTs:       map['endTs'] as int?,
    accumulated: map['accumulated'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {
    if (startTs != null) 'startTs': startTs,
    if (endTs   != null) 'endTs':   endTs,
    'accumulated': accumulated,
  };

  int get totalMs {
    if (startTs == null) return accumulated;
    final running = endTs == null
        ? DateTime.now().millisecondsSinceEpoch - startTs!
        : endTs! - startTs!;
    return accumulated + running.clamp(0, 999999999);
  }

  @override
  List<Object?> get props => [startTs, endTs, accumulated];
}

// ─────────────────────────────────────────────
// PresentationState
// ─────────────────────────────────────────────
class PresentationState extends Equatable {
  final int currentSlide;
  final bool touchEnabled;
  final double volume;
  final bool timerRunning;
  final int timerBase;
  final int timerStart;
  final List<SlideModel> slides;
  final Map<int, SlideTimerData> slideTimers;
  final int iframePageIndex;
  final bool overlayEnabled;
  final double pointerX;
  final double pointerY;
  final bool pointerActive;

  // ── Vizibilitate cronometru (cerință #1) ──────────────────────────────────
  // Controlează afișarea cronometrului general în UI-ul de Control:
  // chip-ul din bara de sus, secțiunea „Cronometre" din centru, și timpul
  // acumulat afișat lângă fiecare slide din lista din dreapta. Nu afectează
  // funcționarea propriu-zisă a cronometrului (continuă să ruleze/acumuleze
  // în fundal, control via tastatură P/R rămâne activ) — doar vizibilitatea.
  // Persistat în Firebase sub cheia `timerVisible`.
  final bool timerVisible;

  const PresentationState({
    this.currentSlide       = 0,
    this.touchEnabled       = true,
    this.volume             = 1.0,
    this.timerRunning       = false,
    this.timerBase          = 0,
    this.timerStart         = 0,
    this.slides             = const [],
    this.slideTimers        = const {},
    this.iframePageIndex    = 0,
    this.overlayEnabled     = true,
    this.pointerX           = 0.5,
    this.pointerY           = 0.5,
    this.pointerActive      = false,
    this.timerVisible       = true,
  });

  int get timerTotalMs {
    if (!timerRunning || timerStart == 0) return timerBase;
    return timerBase +
        (DateTime.now().millisecondsSinceEpoch - timerStart).clamp(0, 999999999);
  }

  SlideModel? get currentSlideModel => slides.isEmpty
      ? null
      : slides[currentSlide.clamp(0, slides.length - 1)];

  String? get pagedIframeUrl {
    final slide = currentSlideModel;
    if (slide == null || slide.type != SlideType.iframe) return null;
    final base = slide.url;
    if (base == null || base.isEmpty) return null;
    return _buildPagedUrl(base, iframePageIndex);
  }

  static String _buildPagedUrl(String base, int page) {
    if (page == 0) return base;
    if (base.contains('docs.google.com/presentation')) {
      try {
        final uri    = Uri.parse(base.split('#').first);
        final params = Map<String, String>.from(uri.queryParameters);
        params['slide'] = (page + 1).toString();
        return uri.replace(queryParameters: params).toString();
      } catch (_) { return base; }
    }
    return base;
  }

  PresentationState copyWith({
    int?                      currentSlide,
    bool?                     touchEnabled,
    double?                   volume,
    bool?                     timerRunning,
    int?                      timerBase,
    int?                      timerStart,
    List<SlideModel>?         slides,
    Map<int, SlideTimerData>? slideTimers,
    int?                      iframePageIndex,
    bool?                     overlayEnabled,
    double?                   pointerX,
    double?                   pointerY,
    bool?                     pointerActive,
    bool?                     timerVisible,
  }) => PresentationState(
    currentSlide:    currentSlide    ?? this.currentSlide,
    touchEnabled:    touchEnabled    ?? this.touchEnabled,
    volume:          volume          ?? this.volume,
    timerRunning:    timerRunning    ?? this.timerRunning,
    timerBase:       timerBase       ?? this.timerBase,
    timerStart:      timerStart      ?? this.timerStart,
    slides:          slides          ?? this.slides,
    slideTimers:     slideTimers     ?? this.slideTimers,
    iframePageIndex: iframePageIndex ?? this.iframePageIndex,
    overlayEnabled:  overlayEnabled  ?? this.overlayEnabled,
    pointerX:        pointerX        ?? this.pointerX,
    pointerY:        pointerY        ?? this.pointerY,
    pointerActive:   pointerActive   ?? this.pointerActive,
    timerVisible:    timerVisible    ?? this.timerVisible,
  );

  @override
  List<Object?> get props => [
    currentSlide, touchEnabled, volume,
    timerRunning, timerBase, timerStart,
    slides, slideTimers, iframePageIndex, overlayEnabled,
    pointerX, pointerY, pointerActive, timerVisible,
  ];
}

enum SlideType { intro, transition, iframe, end, announce }

// Sursă hibridă pentru slide-urile de tip video: fie link din baza de date
// (network), fie fișier local împachetat cu aplicația (asset).
enum VideoSourceType { network, asset }

class SlideModel extends Equatable {
  final int id;
  final SlideType type;
  final String title;
  final String? heading;
  final String? subtitle;
  final List<String>? orbColors;
  final String? animation;
  final String? color1;
  final String? color2;
  final String? url;
  final String? staticImageUrl;

  // ── Sursă hibridă video (cerință #2) ──────────────────────────────────────
  // videoSource == null            → slide-ul nu redă video (comportament vechi)
  // videoSource == network         → redă din `url` (link stocat în Firebase)
  // videoSource == asset           → redă din `localAssetPath` (fișier local,
  //                                   NU trece prin baza de date/rețea)
  final VideoSourceType? videoSource;
  final String? localAssetPath;

  // ── Buclă video / freeze-black (cerință #2) ───────────────────────────────
  // videoLoop == null  → comportament implicit: bucla infinită DOAR pentru
  //                       slide-ul de tip intro (ex: slide 1); orice alt
  //                       slide video redă o singură dată, apoi ecranul se
  //                       stinge treptat spre negru și rămâne înghețat până
  //                       la avansul manual din Control.
  // videoLoop == true  → forțează bucla infinită, indiferent de tip.
  // videoLoop == false → forțează redare unică + freeze-black, indiferent de tip.
  final bool? videoLoop;

  // ── Redare video (opțional) ───────────────────────────────────────────────
  // videoMuted == true  → videoclipul pornește fără sunet (util pentru bucla
  //                        de intro, care rulează în fundal).
  // videoFit   == 'cover'   → umple tot ecranul (implicit, poate tăia marginile)
  // videoFit   == 'contain' → se vede tot cadrul, cu benzi negre dacă e nevoie
  final bool?   videoMuted;
  final String? videoFit;

  // ── Tranziția de INTRARE a slide-ului (opțional) ─────────────────────────
  //   'flash' (implicit) → crossfade + dâră de lumină
  //   'fade'             → crossfade simplu, fără dâră de lumină
  //   'black'            → ecranul se stinge spre negru, apoi apare slide-ul
  //   'cut'              → schimbare instantanee
  final String? transitionIn;

  // ── Slide de anunț: rândurile cu reguli (opțional) ────────────────────────
  // Dacă lipsește, panoul de anunț folosește regulile implicite.
  final List<String>? rules;

  /// True dacă acest slide trebuie să reia videoclipul la infinit.
  /// Implicit: doar slide-urile de tip [SlideType.intro].
  bool get loopsForever => videoLoop ?? (type == SlideType.intro);

  /// Calea/URL-ul fișierului video al slide-ului (asset sau link), sau ''.
  String get videoPath =>
      (videoSource == VideoSourceType.asset ? localAssetPath : url) ?? '';

  /// True dacă fișierul video este un .mov (QuickTime).
  bool get isMovVideo {
    final clean = videoPath.toLowerCase().split('?').first.split('#').first;
    return clean.endsWith('.mov');
  }

  const SlideModel({
    required this.id,
    required this.type,
    required this.title,
    this.heading,
    this.subtitle,
    this.orbColors,
    this.animation,
    this.color1,
    this.color2,
    this.url,
    this.staticImageUrl,
    this.videoSource,
    this.localAssetPath,
    this.videoLoop,
    this.videoMuted,
    this.videoFit,
    this.transitionIn,
    this.rules,
  });

  factory SlideModel.fromMap(Map<String, dynamic> map) => SlideModel(
    id:             map['id'] as int,
    type:           SlideType.values.byName(map['type'] as String),
    title:          map['title'] as String? ?? '',
    heading:        map['heading'] as String?,
    subtitle:       map['subtitle'] as String?,
    orbColors:      (map['orbColors'] as List?)?.cast<String>(),
    animation:      map['animation'] as String?,
    color1:         map['color1'] as String?,
    color2:         map['color2'] as String?,
    url:            map['url'] as String?,
    staticImageUrl: map['staticImageUrl'] as String?,
    videoSource:    map['videoSource'] != null
        ? VideoSourceType.values.byName(map['videoSource'] as String)
        : null,
    localAssetPath: map['localAssetPath'] as String?,
    videoLoop:      map['videoLoop'] as bool?,
    videoMuted:     map['videoMuted'] as bool?,
    videoFit:       map['videoFit'] as String?,
    transitionIn:   map['transitionIn'] as String?,
    rules:          _stringList(map['rules']),
  );

  /// Firebase poate întoarce o listă (chei 0,1,2…) sau un Map — le acceptăm pe
  /// amândouă și ignorăm elementele goale.
  static List<String>? _stringList(dynamic v) {
    if (v == null) return null;
    final Iterable<dynamic> items =
        v is Map ? v.values : (v is Iterable ? v : const <dynamic>[]);
    final out = items
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .toList();
    return out.isEmpty ? null : out;
  }

  Map<String, dynamic> toMap() => {
    'id':    id,
    'type':  type.name,
    'title': title,
    if (heading        != null) 'heading':        heading,
    if (subtitle       != null) 'subtitle':       subtitle,
    if (orbColors      != null) 'orbColors':      orbColors,
    if (animation      != null) 'animation':      animation,
    if (color1         != null) 'color1':         color1,
    if (color2         != null) 'color2':         color2,
    if (url            != null) 'url':            url,
    if (staticImageUrl != null) 'staticImageUrl': staticImageUrl,
    if (videoSource    != null) 'videoSource':    videoSource!.name,
    if (localAssetPath != null) 'localAssetPath': localAssetPath,
    if (videoLoop      != null) 'videoLoop':      videoLoop,
    if (videoMuted     != null) 'videoMuted':     videoMuted,
    if (videoFit       != null) 'videoFit':       videoFit,
    if (transitionIn   != null) 'transitionIn':   transitionIn,
    if (rules          != null) 'rules':          rules,
  };

  /// True dacă acest slide are un video de redat (din DB sau local).
  bool get isVideoSlide => videoSource != null;

  @override
  List<Object?> get props => [
    id, type, title, heading, subtitle,
    orbColors, animation, color1, color2, url, staticImageUrl,
    videoSource, localAssetPath, videoLoop,
    videoMuted, videoFit, transitionIn, rules,
  ];
}

// ─────────────────────────────────────────────
// Utilități
// ─────────────────────────────────────────────

bool shouldProcessEvent(DateTime? lastTime,
    {Duration minGap = const Duration(milliseconds: 900)}) {
  if (lastTime == null) return true;
  return DateTime.now().difference(lastTime) >= minGap;
}

class Debouncer {
  final Duration delay;
  Timer? _timer;
  Debouncer({this.delay = const Duration(milliseconds: 300)});
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }
  void dispose() => _timer?.cancel();
}

Color hexToColor(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
  if (clean.length == 8) return Color(int.parse(clean, radix: 16));
  return Colors.purple;
}

String formatMs(int ms) {
  if (ms < 0) ms = 0;
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return '${_pad(h)}:${_pad(m)}:${_pad(s)}';
}

String formatMsShort(int ms) {
  if (ms < 0) ms = 0;
  final total = ms ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  return '${_pad(m)}:${_pad(s)}';
}

String _pad(int n) => n.toString().padLeft(2, '0');