// lib/features/control/control_gate_page.dart
//
// Login simplu: parolă + numele proiectului (ex: proiect1, proiect3...)
// Fără selector de proiect, fără broadcast, fără grilă.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/firebase_service.dart';
import 'bloc/control_bloc.dart';
import 'control_page.dart';

const _kMasterPassword = 'adf145';

class ControlGatePage extends StatefulWidget {
  const ControlGatePage({super.key});

  @override
  State<ControlGatePage> createState() => _ControlGatePageState();
}

class _ControlGatePageState extends State<ControlGatePage>
    with SingleTickerProviderStateMixin {
  final _passwordCtrl     = TextEditingController();
  final _projectCtrl      = TextEditingController(text: 'proiect1');
  final _passwordFocus    = FocusNode();
  final _projectFocus     = FocusNode();
  final _keyListenerFocus = FocusNode();

  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  bool   _obscure  = true;
  bool   _hasError = false;
  bool   _loading  = false;
  String _errorMsg = '';

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

    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _passwordFocus.requestFocus());
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _projectCtrl.dispose();
    _passwordFocus.dispose();
    _projectFocus.dispose();
    _keyListenerFocus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    final password = _passwordCtrl.text.trim();
    final project  = _projectCtrl.text.trim();

    if (password != _kMasterPassword) {
      _passwordCtrl.clear();
      _triggerError('Parolă incorectă');
      return;
    }
    if (project.isEmpty) {
      _triggerError('Introduceți numele proiectului');
      return;
    }

    setState(() => _loading = true);

    await FirebaseService.instance.switchProject(project);
    if (!mounted) return;

    final bloc = ControlBloc(FirebaseService.instance);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => BlocProvider.value(
          value: bloc,
          child: const ControlPage(),
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _triggerError(String msg) {
    setState(() { _hasError = true; _errorMsg = msg; });
    _shakeCtrl.forward(from: 0).then((_) {
      Future.delayed(const Duration(milliseconds: 900), () {
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
              width:   400,
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

                  // ── Iconiță ──────────────────────────────────────────────
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
                      _hasError
                          ? Icons.lock_outline
                          : Icons.admin_panel_settings_outlined,
                      color: _hasError
                          ? const Color(0xFFFF6584)
                          : const Color(0xFF6C63FF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'CONTROL',
                    style: TextStyle(
                      color:         Colors.white,
                      fontSize:      18,
                      fontWeight:    FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _hasError
                          ? _errorMsg
                          : 'Introdu parola și proiectul',
                      key: ValueKey(_hasError ? _errorMsg : 'default'),
                      style: TextStyle(
                        color: _hasError
                            ? const Color(0xFFFF6584)
                            : Colors.white.withOpacity(0.35),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Câmp parolă ───────────────────────────────────────────
                  _buildField(
                    controller: _passwordCtrl,
                    focusNode:  _passwordFocus,
                    hint:       'Parolă',
                    obscure:    _obscure,
                    suffix: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white24, size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Câmp proiect ──────────────────────────────────────────
                  _buildField(
                    controller: _projectCtrl,
                    focusNode:  _projectFocus,
                    hint:       'Proiect  (ex: proiect3)',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 14, right: 8),
                      child: Icon(Icons.slideshow_outlined,
                          color: Colors.white24, size: 18),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Buton INTRĂ ───────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _loading ? null : _submit,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: (!_hasError && !_loading)
                              ? const LinearGradient(
                                  colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                                )
                              : null,
                          color: _hasError
                              ? const Color(0xFFFF6584).withOpacity(0.15)
                              : _loading
                                  ? Colors.white.withOpacity(0.06)
                                  : null,
                          borderRadius: BorderRadius.circular(10),
                          border: _hasError
                              ? Border.all(
                                  color: const Color(0xFFFF6584).withOpacity(0.4))
                              : null,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white54, strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _hasError ? 'EROARE' : 'INTRĂ',
                                style: TextStyle(
                                  color: _hasError
                                      ? const Color(0xFFFF6584)
                                      : Colors.white,
                                  fontSize:      13,
                                  fontWeight:    FontWeight.w800,
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

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode             focusNode,
    required String                hint,
    bool                           obscure = false,
    Widget?                        suffix,
    Widget?                        prefix,
  }) {
    return AnimatedContainer(
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
        controller:  controller,
        focusNode:   focusNode,
        obscureText: obscure,
        style: const TextStyle(
          color:      Colors.white,
          fontSize:   15,
          fontFamily: 'monospace',
          letterSpacing: 1,
        ),
        decoration: InputDecoration(
          hintText:  hint,
          hintStyle: TextStyle(
            color:       Colors.white.withOpacity(0.2),
            fontSize:    13,
            fontFamily:  'sans-serif',
            letterSpacing: 0,
          ),
          border:         InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          suffixIcon: suffix,
          prefixIcon: prefix,
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
