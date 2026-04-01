// lib/features/control/control_gate_page.dart
//
// Parola se citește din Firebase Realtime Database:
//   prez → controlPassword  (string)
//
// Ca s-o schimbi: deschide consola Firebase → Realtime Database →
//   prez → controlPassword → editează valoarea → Save.
// Fără redeploy, instant.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/firebase_service.dart';
import 'bloc/control_bloc.dart';
import 'control_page.dart';

class ControlGatePage extends StatefulWidget {
  const ControlGatePage({super.key});

  @override
  State<ControlGatePage> createState() => _ControlGatePageState();
}

class _ControlGatePageState extends State<ControlGatePage>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();

  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  bool    _obscure  = true;
  bool    _hasError = false;
  bool    _loading  = true;
  String? _password;

  // ✅ FIX: Blocul e creat o singură dată aici, nu în ControlPage.
  // Astfel supraviețuiește oricărui rebuild al widget tree-ului.
  late final ControlBloc _controlBloc;
  bool _blocHandedOff = false;

  @override
  void initState() {
    super.initState();

    _controlBloc = ControlBloc(FirebaseService.instance);
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

    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final pw = await FirebaseService.instance.fetchControlPassword();
    if (!mounted) return;
    setState(() {
      _password = pw;
      _loading  = false;
    });
    _focusNode.requestFocus();
  }

  // ── FocusNode pentru KeyboardListener — creat ca field, nu inline în build() ──
  final _keyListenerFocus = FocusNode();

  @override
  void dispose() {
    if (!_blocHandedOff) _controlBloc.close();
    _controller.dispose();
    _focusNode.dispose();
    _keyListenerFocus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password == null || _password!.isEmpty) {
      _triggerError();
      return;
    }
    if (_controller.text.trim() == _password) {
      _blocHandedOff = true;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          // ✅ FIX: furnizăm blocul existent prin BlocProvider.value
          // (nu creează un bloc nou — folosește cel din _controlBloc)
          pageBuilder: (_, __, ___) => BlocProvider.value(
            value: _controlBloc,
            child: const ControlPage(),
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
    // ✅ FIX: nu mai returnăm ControlPage() inline din build().
    // Navigarea reală se face în _submit() cu pushReplacement.

    return Scaffold(
      backgroundColor: const Color(0xFF06060f),
      body: KeyboardListener(
        // ✅ FIX: FocusNode creat ca field, nu `FocusNode()` inline (evită memory leak)
        focusNode: _keyListenerFocus,
        onKeyEvent: (e) {
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.enter) {
            _submit();
          }
        },
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(
              color: Color(0xFF6C63FF), strokeWidth: 2)
              : AnimatedBuilder(
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
                    width:  64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_hasError
                          ? const Color(0xFFFF6584)
                          : const Color(0xFF6C63FF))
                          .withOpacity(0.12),
                    ),
                    child: Icon(
                      _hasError
                          ? Icons.lock_outline
                          : Icons.shield_outlined,
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
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hasError
                        ? 'Parolă incorectă'
                        : 'Introdu parola pentru acces',
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
                        color:         Colors.white,
                        fontSize:      16,
                        fontFamily:    'monospace',
                        letterSpacing: 2,
                      ),
                      decoration: InputDecoration(
                        hintText: '••••••••',
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
                            color: Colors.white24,
                            size:  18,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
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
                          gradient: _hasError
                              ? null
                              : const LinearGradient(colors: [
                            Color(0xFF6C63FF),
                            Color(0xFF8B5CF6),
                          ]),
                          color: _hasError
                              ? const Color(0xFFFF6584).withOpacity(0.15)
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          border: _hasError
                              ? Border.all(
                              color: const Color(0xFFFF6584)
                                  .withOpacity(0.4))
                              : null,
                        ),
                        child: Text(
                          _hasError ? 'PAROLĂ GREȘITĂ' : 'INTRĂ',
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
}