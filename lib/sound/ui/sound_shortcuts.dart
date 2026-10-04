// lib/sound/ui/sound_shortcuts.dart
//
// Scurtături de tastatură pentru sunet (configurabile în Setări). Se integrează în
// handler-ul de taste EXISTENT al paginii de control: dacă tasta e a unei acțiuni de
// sunet, o execută și întoarce true (evenimentul e consumat); altfel false.
// Implicit: Esc = Oprește tot · F = Fade-out · L = Fade la nivel · N = Următorul ·
// B = Anteriorul · Z = Restart. (P rămâne cronometrul existent, deci Anteriorul e B.)

import 'package:flutter/services.dart';

import '../audio/playback_coordinator.dart';
import '../core/models.dart';

class SoundShortcuts {
  final PlaybackCoordinator coordinator;
  final AppSettings Function() settings;

  SoundShortcuts({required this.coordinator, required this.settings});

  /// Etichete acceptate în Setări → tastă.
  static LogicalKeyboardKey? parseKey(String label) {
    final l = label.trim().toLowerCase();
    if (l.isEmpty) return null;
    switch (l) {
      case 'escape':
      case 'esc':
        return LogicalKeyboardKey.escape;
      case 'space':
        return LogicalKeyboardKey.space;
      case 'enter':
        return LogicalKeyboardKey.enter;
      case 'delete':
        return LogicalKeyboardKey.delete;
      case 'backspace':
        return LogicalKeyboardKey.backspace;
    }
    if (l.length == 1) {
      final code = l.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7a) {
        // litere a–z
        return LogicalKeyboardKey(0x00000000061 + (code - 0x61));
      }
      if (code >= 0x30 && code <= 0x39) {
        return LogicalKeyboardKey(0x00000000030 + (code - 0x30));
      }
    }
    return null;
  }

  /// Executa acțiunea asociată tastei. True = consumat.
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final map = settings().shortcuts;
    final key = event.logicalKey;

    bool matches(String action) {
      final k = parseKey(map[action] ?? AppSettings.defaultShortcuts[action] ?? '');
      return k != null && k == key;
    }

    // un sunet „curent” sau cel mai recent pornit, pentru acțiunile per sunet
    final id = coordinator.currentId.value;

    if (matches('stopAll')) {
      coordinator.stopAll();
      return true;
    }
    if (matches('fadeOut')) {
      coordinator.fadeOutAll();
      return true;
    }
    if (matches('fadeToLevel')) {
      coordinator.fadeToLevelAll();
      return true;
    }
    if (matches('next')) {
      coordinator.next();
      return true;
    }
    if (matches('previous')) {
      coordinator.previous();
      return true;
    }
    if (matches('restart') && id != null) {
      coordinator.restart(id);
      return true;
    }
    return false;
  }
}
