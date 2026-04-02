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
  );

  @override
  List<Object?> get props => [
    currentSlide, touchEnabled, volume,
    timerRunning, timerBase, timerStart,
    slides, slideTimers, iframePageIndex, overlayEnabled,
    pointerX, pointerY, pointerActive,
  ];
}

enum SlideType { intro, transition, iframe, end, announce }

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
  );

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
  };

  @override
  List<Object?> get props => [
    id, type, title, heading, subtitle,
    orbColors, animation, color1, color2, url, staticImageUrl,
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