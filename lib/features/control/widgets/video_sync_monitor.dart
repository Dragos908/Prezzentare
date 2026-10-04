// lib/features/control/widgets/video_sync_monitor.dart
//
// Cerință #3 — Sistem precis de monitorizare/sincronizare pentru video:
//   • Oglindă mută (muted) a videoclipului care rulează pe Display
//   • Countdown cu timp rămas; ultimele 20s -> efect vizual (mărire + glow roșu)
//   • Afișare timp curent (mm:ss) sincronizat cu videoclipul de pe ecranul
//     principal, prin nodul `videoHeartbeat` din Realtime Database
//   • Detectare automată freeze/pauză -> indicator "OPRIT" / "PAUZĂ"
//
// Integrare: adaugă acest widget în `SlideMonitorPanel`
// (lib/features/control/widgets/slide_panels.dart), afișat doar când
// `current.isVideoSlide == true`.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/firebase_service.dart';
import '../../../core/model.dart';
import 'package:video_player/video_player.dart';
import '../../display/widgets/hybrid_video_widget.dart';

class VideoSyncMonitor extends StatefulWidget {
  final SlideModel slide;
  const VideoSyncMonitor({super.key, required this.slide});

  @override
  State<VideoSyncMonitor> createState() => _VideoSyncMonitorState();
}

class _VideoSyncMonitorState extends State<VideoSyncMonitor> {
  late final StreamSubscription _sub;

  double _position = 0;
  double _duration = 0;
  bool   _playing   = false;
  DateTime? _lastHeartbeat;
  Timer? _staleCheckTimer;
  bool _isFrozen = false;
  VideoPlayerController? _previewController;

  // Prag peste care considerăm că fluxul de heartbeat s-a oprit
  // (buffering / pauză neanunțată / slide oprit).
  static const _staleThreshold = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();

    _sub = FirebaseService.instance.videoHeartbeatStream.listen((m) {
      if (!mounted) return;
      setState(() {
        _position      = (m['position'] as num?)?.toDouble() ?? 0;
        _duration      = (m['duration'] as num?)?.toDouble() ?? 0;
        _playing       = m['playing'] == true;
        _lastHeartbeat = DateTime.now();
        _isFrozen      = false;
      });

      // Resincronizare fină a oglinzii dacă a derapat >0.5s față de sursă.
      final ctrl = _previewController;
      if (ctrl != null && ctrl.value.isInitialized) {
        final diff = (ctrl.value.position.inMilliseconds / 1000) - _position;
        if (diff.abs() > 0.5) {
          ctrl.seekTo(Duration(milliseconds: (_position * 1000).round()));
        }
      }
    });

    _staleCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_lastHeartbeat == null || !mounted) return;
      final elapsed = DateTime.now().difference(_lastHeartbeat!);
      final shouldBeFrozen = _playing && elapsed > _staleThreshold;
      if (shouldBeFrozen != _isFrozen) {
        setState(() => _isFrozen = shouldBeFrozen);
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _staleCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining  = (_duration - _position).clamp(0, double.infinity);
    final isCritical = remaining <= 20 && remaining > 0 && _playing && !_isFrozen;
    // Video fără buclă, ajuns la final → pe Display ecranul s-a făcut negru
    // și așteaptă comanda de avans. Nu e o „pauză” defectă, deci nu alarmăm.
    final ended = !widget.slide.loopsForever &&
        _lastHeartbeat != null &&
        !_playing &&
        _duration > 0 &&
        _position >= _duration - 0.5;
    final stopped =
        !ended && (_isFrozen || (!_playing && _lastHeartbeat != null));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: stopped
              ? Colors.redAccent.withOpacity(0.6)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Oglindă video, OBLIGATORIU mută ──────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: HybridVideoWidget(
                      slide: widget.slide,
                      muted: true, // ← esențial: fără sunet în panoul de control
                      onControllerReady: (c) => _previewController = c,
                    ),
                  ),
                  if (stopped)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: Text(
                        _isFrozen ? 'OPRIT' : 'PAUZĂ',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 3,
                        ),
                      ),
                    )
                  else if (ended)
                    Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: const Text(
                        'ECRAN NEGRU',
                        style: TextStyle(
                          color: Colors.white38,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Timp curent (mm:ss) ──────────────────────────────────────────
          Text(
            formatMsShort((_position * 1000).round()),
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),

          // ── Countdown — glow + mărire în ultimele 20s ────────────────────
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: isCritical ? 42 : 28,
              color: isCritical ? const Color(0xFFFF3B3B) : Colors.white,
              shadows: isCritical
                  ? const [
                      Shadow(color: Color(0xFFFF3B3B), blurRadius: 20),
                      Shadow(color: Color(0xFFFF3B3B), blurRadius: 40),
                    ]
                  : const [],
            ),
            child: Text('-${formatMsShort((remaining * 1000).round())}'),
          ),
        ],
      ),
    );
  }
}
