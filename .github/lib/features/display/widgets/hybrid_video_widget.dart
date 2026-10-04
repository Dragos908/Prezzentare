// lib/features/display/widgets/hybrid_video_widget.dart
//
// Redă un slide de tip video din DOUĂ surse posibile:
//   • VideoSourceType.asset   → slide.localAssetPath  (fișier împachetat în
//                               aplicație, ex: assets/videos/intro.mov)
//   • VideoSourceType.network → slide.url             (link direct din Firebase)
//
// ── FORMAT .mov ───────────────────────────────────────────────────────────────
// Pe web, `video_player` folosește elementul HTML <video>, deci un fișier .mov
// se redă exact ca în browser: funcționează în Chrome / Edge / Safari dacă
// fișierul conține video H.264 (yuv420p) + audio AAC. Dacă fișierul are alt
// codec (ProRes, HEVC, 10-bit, PCM...), browserul refuză să-l deschidă și
// widgetul afișează un mesaj clar (vezi _VideoErrorView) în loc să rămână
// blocat pe un cadru înghețat.
//
// ── Buclă vs. fade la negru ───────────────────────────────────────────────────
// `slide.loopsForever` (vezi model.dart) decide ce se întâmplă la final:
//   • true  → buclă infinită (implicit pentru slide-ul de tip intro).
//   • false → redare o singură dată; la final ecranul se stinge treptat spre
//             negru (fade ~2.5 s) și rămâne negru până la comanda manuală de
//             avans din Control (schimbarea slide-ului distruge acest widget).
//
// ── Sunet și politica de autoplay a browserului ───────────────────────────────
// Browserele refuză pornirea automată CU sunet dacă utilizatorul nu a făcut
// niciun click în pagină. În acest caz videoclipul este repornit automat MUT
// (imagine în mișcare, nu cadru înghețat). Deschide Display-ul din butonul
// „DISPLAY" de pe pagina de start (click-ul acela deblochează sunetul).

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/model.dart';
import '../../../sound/display/display_audio_guard.dart';
import '../../../sound/display/display_media_factory.dart';

class HybridVideoWidget extends StatefulWidget {
  final SlideModel slide;

  /// Forțează redarea fără sunet (ex: oglinda din panoul de Control).
  final bool muted;

  /// Volumul 0.0–1.0 (din panoul de Control, prin Firebase).
  final double volume;

  /// Cât timp e true, videoclipul se încarcă dar NU pornește. Folosit de
  /// DoubleBuffer: slide-ul care intră așteaptă să devină vizibil, ca imaginea
  /// și sunetul să înceapă împreună. Când devine false, redarea pornește.
  final bool hold;

  /// Apelat când un controller nou e gata și rulează.
  final ValueChanged<VideoPlayerController>? onControllerReady;

  /// Apelat când controllerul curent a fost eliberat (repornire / eroare /
  /// dispose) — cei care au reținut controllerul trebuie să-l uite.
  final VoidCallback? onControllerReleased;

  const HybridVideoWidget({
    super.key,
    required this.slide,
    this.muted = false,
    this.volume = 1.0,
    this.hold = false,
    this.onControllerReady,
    this.onControllerReleased,
  });

  @override
  State<HybridVideoWidget> createState() => _HybridVideoWidgetState();
}

class _HybridVideoWidgetState extends State<HybridVideoWidget> {
  /// Durata fade-ului spre negru la finalul unui video care nu rulează în buclă.
  static const Duration _fadeToBlack = Duration(milliseconds: 2500);

  /// Cât de aproape de final considerăm că videoclipul s-a terminat.
  static const Duration _endTolerance = Duration(milliseconds: 150);

  VideoPlayerController? _controller;
  Object? _error;

  /// Crește la fiecare (re)inițializare; o inițializare veche care se termină
  /// târziu își dă seama că a fost depășită și se oprește.
  int _generation = 0;

  bool _loop = true;
  bool _ended = false;

  /// Browserul a refuzat pornirea cu sunet → repornim mut.
  bool _soundBlocked = false;
  bool _restarting = false;

  double get _targetVolume {
    if (widget.muted || _soundBlocked || (widget.slide.videoMuted ?? false)) {
      return 0.0;
    }
    // Setarea `displayAudioMuted` (guard): 0 cât timp displayul e mut.
    return DisplayMediaFactory.instance
        .allowedVolume(widget.volume.clamp(0.0, 1.0).toDouble());
  }

  /// Setarea de mut s-a schimbat live (≤ 1 s, fără repornire).
  void _onGuardChanged() {
    final c = _controller;
    if (c == null || !mounted) return;
    c.setVolume(_targetVolume);
  }

  @override
  void initState() {
    super.initState();
    DisplayAudioGuard.instance.mutedNotifier.addListener(_onGuardChanged);
    _init();
  }

  @override
  void didUpdateWidget(covariant HybridVideoWidget old) {
    super.didUpdateWidget(old);
    final o = old.slide;
    final s = widget.slide;
    final sourceChanged = o.videoSource != s.videoSource ||
        o.url != s.url ||
        o.localAssetPath != s.localAssetPath ||
        o.loopsForever != s.loopsForever;

    if (sourceChanged) {
      _soundBlocked = false;
      _init();
    } else {
      if (old.muted != widget.muted ||
          old.volume != widget.volume ||
          o.videoMuted != s.videoMuted) {
        _controller?.setVolume(_targetVolume);
      }
      if (old.hold && !widget.hold) {
        final c = _controller;
        if (c != null && c.value.isInitialized) _startPlayback(_generation, c);
      }
    }
  }

  @override
  void dispose() {
    DisplayAudioGuard.instance.mutedNotifier.removeListener(_onGuardChanged);
    _generation++;
    _disposeController();
    super.dispose();
  }

  // ── Controller ────────────────────────────────────────────────────────────

  VideoPlayerController? _createController(SlideModel slide) {
    if (slide.videoSource == VideoSourceType.asset &&
        (slide.localAssetPath?.isNotEmpty ?? false)) {
      return DisplayMediaFactory.instance.createAsset(slide.localAssetPath!,
          label: 'slide-asset');
    }
    if (slide.videoSource == VideoSourceType.network &&
        (slide.url?.isNotEmpty ?? false)) {
      return DisplayMediaFactory.instance.createNetwork(Uri.parse(slide.url!),
          label: 'slide-network');
    }
    return null;
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    c.removeListener(_onValue);
    DisplayMediaFactory.instance.release(c); // scoate din guard + dispose
    widget.onControllerReleased?.call();
  }

  Future<void> _init() async {
    final gen = ++_generation;
    final slide = widget.slide;

    _disposeController();
    _loop = slide.loopsForever;
    _ended = false;
    _error = null;

    try {
      final ctrl = _createController(slide);
      if (ctrl == null) {
        throw StateError('lipsește sursa video (url / localAssetPath)');
      }
      _controller = ctrl;

      await ctrl.initialize();
      if (!mounted || gen != _generation) return;

      await ctrl.setLooping(_loop);
      await ctrl.setVolume(_targetVolume);
      ctrl.addListener(_onValue);
      if (!widget.hold) await ctrl.play();
      if (!mounted || gen != _generation) return;

      setState(() {});
      widget.onControllerReady?.call(ctrl);
      if (!widget.hold) _scheduleStartCheck(gen, ctrl);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      _disposeController();
      setState(() => _error = e);
    }
  }

  /// Pornește redarea după ce un `hold` a fost eliberat.
  Future<void> _startPlayback(int gen, VideoPlayerController ctrl) async {
    try {
      await ctrl.play();
    } catch (_) {
      return;
    }
    if (!mounted || gen != _generation) return;
    _scheduleStartCheck(gen, ctrl);
  }

  /// Ascultător apelat de `video_player` la fiecare schimbare de stare.
  void _onValue() {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;
    final v = ctrl.value;

    if (v.hasError) {
      if (_restarting) return;
      if (!_soundBlocked && _targetVolume > 0) {
        // Cel mai probabil browserul a blocat pornirea cu sunet.
        _restarting = true;
        _soundBlocked = true;
        Future<void>.microtask(() {
          _restarting = false;
          if (mounted) _init();
        });
        return;
      }
      if (_error == null) {
        setState(() => _error = v.errorDescription ?? 'eroare necunoscută');
      }
      return;
    }

    // ── Final de video (doar pentru slide-uri fără buclă) ──────────────────
    if (_loop || _ended) return;
    if (!v.isInitialized || v.duration <= Duration.zero) return;

    final nearEnd = v.position >= v.duration - _endTolerance;
    final stoppedAtEnd = !v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 700);

    if (nearEnd || stoppedAtEnd) {
      // Nu apelăm pause(): lăsăm videoclipul să se termine natural (rămâne pe
      // ultimul cadru, cu tot sunetul), iar peste el pornește fade-ul negru.
      setState(() => _ended = true);
    }
  }

  /// Plasă de siguranță pentru browserele care nu raportează eroare la autoplay
  /// blocat: dacă după 1,2 s poziția nu s-a mișcat deloc, repornim mut.
  void _scheduleStartCheck(int gen, VideoPlayerController ctrl) {
    if (_targetVolume <= 0) return; // pornirea mută nu poate fi blocată
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted || gen != _generation || _ended || _soundBlocked) return;
      final v = ctrl.value;
      final stuck = v.isInitialized &&
          v.isPlaying &&
          !v.isBuffering &&
          v.position == Duration.zero;
      if (stuck) {
        _soundBlocked = true;
        _init();
      }
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _VideoErrorView(slide: widget.slide, error: _error!);
    }

    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white24,
            ),
          ),
        ),
      );
    }

    final size = ctrl.value.size;
    final fit = widget.slide.videoFit == 'contain' ? BoxFit.contain : BoxFit.cover;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(ctrl),
            ),
          ),

          // ── Fade spre negru la final: ~2,5 s, apoi rămâne complet negru ──
          // până la avansul manual din Control (care distruge acest widget
          // odată cu schimbarea slide-ului).
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _ended ? 1.0 : 0.0,
              duration: _fadeToBlack,
              curve: Curves.easeInOut,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stare de eroare: fundal negru + mesaj discret jos (nu roșu pe tot ecranul).
// ─────────────────────────────────────────────────────────────────────────────
class _VideoErrorView extends StatelessWidget {
  final SlideModel slide;
  final Object error;

  const _VideoErrorView({required this.slide, required this.error});

  @override
  Widget build(BuildContext context) {
    final path = slide.videoPath;
    final name = path.isEmpty ? '(fără fișier)' : path.split('/').last.split('?').first;
    final hint = slide.isMovVideo
        ? 'Un .mov trebuie să fie H.264 + AAC (yuv420p). Re-exportă fișierul.'
        : 'Verifică fișierul / link-ul și formatul video.';
    var reason = error.toString().replaceAll('\n', ' ');
    if (reason.length > 90) reason = '${reason.substring(0, 90)}…';

    return ColoredBox(
      color: Colors.black,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Text(
            'Video indisponibil: $name\n$hint\n$reason',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}
