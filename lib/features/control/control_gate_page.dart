// lib/features/control/control_gate_page.dart
//
// Panou web — autentificare cu o singură parolă master.
// Proiectul activ este deja setat din URL (?p=proiect1) în main.dart,
// prin FirebaseService.init(). Nu e nevoie de nicio selecție suplimentară.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/firebase_service.dart';
import 'bloc/control_bloc.dart';
import '../settings/settings_page.dart';
import 'control_page.dart';

const _kFallbackPassword = 'adf145'; // folosit doar dacă nu există parolă în DB

/// Ce se deschide după introducerea parolei.
enum GateTarget { control, settings }

class ControlGatePage extends StatefulWidget {
  final GateTarget target;
  const ControlGatePage({super.key, this.target = GateTarget.control});

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

  // ── Parola reală, citită din Firebase RTDB (nod `controlPassword`) ────────
  String?  _dbPassword;
  bool     _loadingPassword = true;

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
            (_) => _focusNode.requestFocus());

    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final pass = await FirebaseService.instance.fetchControlPassword();
    if (!mounted) return;
    setState(() {
      _dbPassword      = pass;
      _loadingPassword = false;
    });
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
    if (_loadingPassword) return; // nu compara înainte să știm parola reală

    final expected = (_dbPassword != null && _dbPassword!.isNotEmpty)
        ? _dbPassword!
        : _kFallbackPassword;

    if (_controller.text.trim() == expected) {
      final bloc = ControlBloc(FirebaseService.instance);
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => BlocProvider.value(
            value: bloc,
            child: widget.target == GateTarget.settings
                ? const SettingsPage()
                : const ControlPage(),
          ),
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
                  Text(
                    _hasError ? 'Parolă incorectă' : 'Introdu parola pentru acces',
                    style: TextStyle(
                      color: _hasError
                          ? const Color(0xFFFF6584)
                          : Colors.white.withOpacity(0.35),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Câmp parolă ───────────────────────────────────────────
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
                        color:         Colors.white,
                        fontSize:      16,
                        fontFamily:    'monospace',
                        letterSpacing: 2,
                      ),
                      decoration: InputDecoration(
                        hintText:  '••••••••',
                        hintStyle: TextStyle(
                          color:         Colors.white.withOpacity(0.15),
                          letterSpacing: 4,
                        ),
                        border:         InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.white24, size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Buton INTRĂ ───────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _loadingPassword ? null : _submit,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: _hasError || _loadingPassword ? null : const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                          ),
                          color: _hasError
                              ? const Color(0xFFFF6584).withOpacity(0.15)
                              : (_loadingPassword ? Colors.white.withOpacity(0.05) : null),
                          borderRadius: BorderRadius.circular(10),
                          border: _hasError
                              ? Border.all(
                              color: const Color(0xFFFF6584).withOpacity(0.4))
                              : null,
                        ),
                        child: Text(
                          _loadingPassword
                              ? 'SE ÎNCARCĂ...'
                              : (_hasError ? 'PAROLĂ GREȘITĂ' : 'INTRĂ'),
                          style: TextStyle(
                            color: _hasError
                                ? const Color(0xFFFF6584)
                                : (_loadingPassword ? Colors.white38 : Colors.white),
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
}