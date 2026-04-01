// lib/features/control/control_gate_page.dart
//
// Parola master hardcodată: "adf145"
// După autentificare → ecran de selecție proiect (proiect1...proiect11)
//   + opțiunea "CONTROL ALL" care activează modul broadcast.
//
// FIX: ControlBloc-ul anterior este închis (close()) înainte de a crea unul nou,
//       pentru a preveni memory leaks și scrieri accidentale pe proiectul greșit.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/firebase_service.dart';
import 'bloc/control_bloc.dart';
import 'control_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Parola master — schimb-o doar aici
// ─────────────────────────────────────────────────────────────────────────────
const _kMasterPassword = 'adf145';

// ─────────────────────────────────────────────────────────────────────────────
// Lista proiectelor disponibile — sincronizată cu FirebaseService.kAllProjects
// ─────────────────────────────────────────────────────────────────────────────
final _kProjects = FirebaseService.kAllProjects;

// Culori per proiect
const _kProjectColors = [
  Color(0xFF6C63FF), // 1 - violet
  Color(0xFF00D9A3), // 2 - verde
  Color(0xFFFF6584), // 3 - roșu
  Color(0xFFFBBF24), // 4 - galben
  Color(0xFF38BDF8), // 5 - albastru
  Color(0xFF4ADE80), // 6 - verde deschis
  Color(0xFFF87171), // 7 - roșu deschis
  Color(0xFF818CF8), // 8 - indigo
  Color(0xFF22D3EE), // 9 - cyan
  Color(0xFFFCD34D), // 10 - galben deschis
  Color(0xFFE879F9), // 11 - roz
];

// ─────────────────────────────────────────────────────────────────────────────
// ControlGatePage — ecran de login
// ─────────────────────────────────────────────────────────────────────────────
class ControlGatePage extends StatefulWidget {
  const ControlGatePage({super.key});

  @override
  State<ControlGatePage> createState() => _ControlGatePageState();
}

class _ControlGatePageState extends State<ControlGatePage>
    with SingleTickerProviderStateMixin {
  final _controller       = TextEditingController();
  final _focusNode        = FocusNode();
  final _keyListenerFocus = FocusNode();

  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  bool _obscure  = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0,   end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end:  12), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  12, end:  -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  -8, end:   8), weight: 2),
      TweenSequenceItem(tween: Tween(begin:   8, end:   0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _keyListenerFocus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == _kMasterPassword) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ProjectSelectorPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } else {
      _controller.clear();
      _triggerError();
    }
  }

  void _triggerError() {
    setState(() => _hasError = true);
    _shakeCtrl.forward(from: 0).then((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _hasError = false);
      });
    });
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06060f),
      body: KeyboardListener(
        focusNode: _keyListenerFocus,
        onKeyEvent: (e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter) {
            _submit();
          }
        },
        child: Center(
          child: AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child:  child,
            ),
            child: Container(
              width:   380,
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: const Color(0xFF0d0d18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hasError
                      ? const Color(0xFFFF6584).withOpacity(0.6)
                      : Colors.white.withOpacity(0.08),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color:      Colors.black.withOpacity(0.5),
                    blurRadius: 60,
                    offset:     const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_hasError
                          ? const Color(0xFFFF6584)
                          : const Color(0xFF6C63FF)).withOpacity(0.12),
                    ),
                    child: Icon(
                      _hasError ? Icons.lock_outline : Icons.admin_panel_settings_outlined,
                      color: _hasError ? const Color(0xFFFF6584) : const Color(0xFF6C63FF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'MASTER CONTROL',
                    style: TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hasError ? 'Parolă incorectă' : 'Introdu parola master',
                    style: TextStyle(
                      color: _hasError
                          ? const Color(0xFFFF6584)
                          : Colors.white.withOpacity(0.35),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 28),

                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _hasError
                            ? const Color(0xFFFF6584).withOpacity(0.5)
                            : Colors.white.withOpacity(0.12),
                      ),
                      color: Colors.white.withOpacity(0.04),
                    ),
                    child: TextField(
                      controller:  _controller,
                      focusNode:   _focusNode,
                      obscureText: _obscure,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 16,
                        fontFamily: 'monospace', letterSpacing: 2,
                      ),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.15), letterSpacing: 4,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.white24, size: 18,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _submit,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: _hasError ? null : const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                          ),
                          color: _hasError
                              ? const Color(0xFFFF6584).withOpacity(0.15)
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          border: _hasError
                              ? Border.all(
                              color: const Color(0xFFFF6584).withOpacity(0.4))
                              : null,
                        ),
                        child: Text(
                          _hasError ? 'PAROLĂ GREȘITĂ' : 'INTRĂ',
                          style: TextStyle(
                            color: _hasError
                                ? const Color(0xFFFF6584)
                                : Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProjectSelectorPage — selectează proiectul sau activează modul broadcast
// ─────────────────────────────────────────────────────────────────────────────
class ProjectSelectorPage extends StatefulWidget {
  const ProjectSelectorPage({super.key});

  @override
  State<ProjectSelectorPage> createState() => _ProjectSelectorPageState();
}

class _ProjectSelectorPageState extends State<ProjectSelectorPage> {
  String? _loading;          // proiectul care se încarcă
  bool    _loadingBroadcast = false;

  // Reținem bloc-ul activ pentru a-l putea disposa corect la switch
  ControlBloc? _activeBloc;

  Future<void> _selectProject(String project) async {
    if (_loading != null || _loadingBroadcast) return;
    setState(() => _loading = project);

    await FirebaseService.instance.switchProject(project);
    if (!mounted) return;

    _navigateToControl(isBroadcast: false);
  }

  Future<void> _selectBroadcast() async {
    if (_loading != null || _loadingBroadcast) return;
    setState(() => _loadingBroadcast = true);

    await FirebaseService.instance.activateBroadcast();
    if (!mounted) return;

    _navigateToControl(isBroadcast: true);
  }

  void _navigateToControl({required bool isBroadcast}) {
    // Închide bloc-ul anterior dacă există (previne memory leaks și scrieri
    // accidentale pe proiectul vechi).
    _activeBloc?.close();

    final bloc = ControlBloc(FirebaseService.instance);
    _activeBloc = bloc;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => BlocProvider.value(
          value: bloc,
          child: ControlPage(isBroadcast: isBroadcast),
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    // Nu dispose-uim _activeBloc aici — e folosit de ControlPage
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _loading != null || _loadingBroadcast;

    return Scaffold(
      backgroundColor: const Color(0xFF06060f),
      body: Column(
        children: [
          // ── Header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF6C63FF),
                        boxShadow: [BoxShadow(
                          color: Color(0x556C63FF), blurRadius: 8,
                        )],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'MASTER CONTROL',
                      style: TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 3,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const ControlGatePage(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.logout, size: 12, color: Colors.white38),
                            SizedBox(width: 6),
                            Text(
                              'IEȘI',
                              style: TextStyle(
                                color: Colors.white38, fontSize: 10,
                                fontWeight: FontWeight.w700, letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Selectează proiectul',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_kProjects.length} proiecte disponibile',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // ── Buton CONTROL ALL ──
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: _BroadcastCard(
              isLoading: _loadingBroadcast,
              disabled:  busy && !_loadingBroadcast,
              onTap:     _selectBroadcast,
            ),
          ),

          // ── Grid proiecte individuale ──
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: List.generate(_kProjects.length, (i) {
                    final project   = _kProjects[i];
                    final color     = _kProjectColors[i];
                    final isLoading = _loading == project;

                    return _ProjectCard(
                      number:    i + 1,
                      project:   project,
                      color:     color,
                      isLoading: isLoading,
                      disabled:  busy && !isLoading,
                      onTap:     () => _selectProject(project),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card BROADCAST — controlează TOATE proiectele simultan
// ─────────────────────────────────────────────────────────────────────────────
class _BroadcastCard extends StatefulWidget {
  final bool isLoading;
  final bool disabled;
  final VoidCallback onTap;

  const _BroadcastCard({
    required this.isLoading,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_BroadcastCard> createState() => _BroadcastCardState();
}

class _BroadcastCardState extends State<_BroadcastCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const color   = Color(0xFFFFBE21);
    final opacity = widget.disabled ? 0.35 : 1.0;

    return MouseRegion(
      onEnter: (_) { if (!widget.disabled) setState(() => _hovered = true); },
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: opacity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: _hovered || widget.isLoading
                  ? color.withOpacity(0.10)
                  : const Color(0xFF0d0d18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered || widget.isLoading
                    ? color.withOpacity(0.6)
                    : color.withOpacity(0.25),
                width: 1.5,
              ),
              boxShadow: _hovered || widget.isLoading
                  ? [BoxShadow(
                color: color.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 6),
              )]
                  : [],
            ),
            child: Row(
              children: [
                // Iconiță / spinner
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(_hovered || widget.isLoading ? 0.2 : 0.1),
                  ),
                  child: widget.isLoading
                      ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      color: color, strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.broadcast_on_personal, color: color, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTROL ALL — TOATE PROIECTELE',
                        style: TextStyle(
                          color: _hovered || widget.isLoading ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Comenzile se transmit simultan la toate cele ${FirebaseService.kAllProjects.length} proiecte',
                        style: TextStyle(
                          color: color.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:        color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: const Text(
                    'BROADCAST',
                    style: TextStyle(
                      color:         color,
                      fontSize:      9,
                      fontWeight:    FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card pentru un proiect individual
// ─────────────────────────────────────────────────────────────────────────────
class _ProjectCard extends StatefulWidget {
  final int    number;
  final String project;
  final Color  color;
  final bool   isLoading;
  final bool   disabled;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.number,
    required this.project,
    required this.color,
    required this.isLoading,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final opacity = widget.disabled ? 0.35 : 1.0;

    return MouseRegion(
      onEnter: (_) { if (!widget.disabled) setState(() => _hovered = true); },
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: opacity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width:  160,
            height: 140,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _hovered || widget.isLoading
                  ? widget.color.withOpacity(0.12)
                  : const Color(0xFF0d0d18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovered || widget.isLoading
                    ? widget.color.withOpacity(0.6)
                    : Colors.white.withOpacity(0.08),
                width: 1.5,
              ),
              boxShadow: _hovered || widget.isLoading
                  ? [BoxShadow(
                color: widget.color.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 6),
              )]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withOpacity(
                        _hovered || widget.isLoading ? 0.2 : 0.1),
                  ),
                  child: widget.isLoading
                      ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      color: widget.color, strokeWidth: 2,
                    ),
                  )
                      : Icon(
                    Icons.slideshow_outlined,
                    color: widget.color, size: 22,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'PROIECT',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.number}',
                  style: TextStyle(
                    color: _hovered || widget.isLoading
                        ? Colors.white
                        : Colors.white70,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}