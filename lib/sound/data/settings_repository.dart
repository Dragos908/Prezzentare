// lib/sound/data/settings_repository.dart
//
// Setările aplicației, în baza de date. Orice modificare se aplică imediat local
// (UI fluid), se salvează cu debounce, iar displayul o primește în timp real.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/ports.dart';

enum SaveStatus { idle, saving, saved, error }

class SettingsRepository {
  final SyncChannelPort _channel;
  final Duration debounce;

  final ValueNotifier<AppSettings> settings =
      ValueNotifier<AppSettings>(const AppSettings());
  final ValueNotifier<SaveStatus> status =
      ValueNotifier<SaveStatus>(SaveStatus.idle);

  StreamSubscription<AppSettings>? _sub;
  Timer? _debounceTimer;
  Timer? _statusReset;
  bool _dirty = false;
  bool _saving = false;
  bool _disposed = false;

  SettingsRepository(this._channel,
      {this.debounce = const Duration(milliseconds: 500)});

  AppSettings get value => settings.value;

  void start() {
    _sub ??= _channel.settingsStream().listen((s) {
      // cât timp avem o modificare locală nesalvată, nu o suprascriem cu ecoul
      if (_dirty || _saving) return;
      settings.value = s;
    });
  }

  /// Aplică modificarea local, imediat, și o salvează după [debounce].
  void update(AppSettings Function(AppSettings current) change) {
    settings.value = change(settings.value);
    _dirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _flush);
  }

  /// Salvează imediat (ex. la părăsirea paginii).
  Future<void> flush() async {
    _debounceTimer?.cancel();
    if (_dirty) await _flush();
  }

  Future<void> _flush() async {
    if (_disposed || _saving) return;
    _saving = true;
    _dirty = false;
    status.value = SaveStatus.saving;
    try {
      await _channel.saveSettings(settings.value.toJson());
      status.value = SaveStatus.saved;
    } catch (_) {
      status.value = SaveStatus.error;
      _dirty = true; // se reîncearcă la următoarea modificare
    } finally {
      _saving = false;
    }
    _statusReset?.cancel();
    _statusReset = Timer(const Duration(milliseconds: 1800), () {
      if (!_disposed && status.value == SaveStatus.saved) {
        status.value = SaveStatus.idle;
      }
    });
    // o modificare a apărut cât salvam
    if (_dirty && !_disposed) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, _flush);
    }
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _statusReset?.cancel();
    _sub?.cancel();
    settings.dispose();
    status.dispose();
  }
}
