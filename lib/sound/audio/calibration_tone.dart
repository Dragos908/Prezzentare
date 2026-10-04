// lib/sound/audio/calibration_tone.dart
//
// Bipul testului de calibrare A/V: sinusoidă 1 kHz, 150 ms, mono, PCM 16-bit WAV,
// cu atac/decădere scurte (fără pocnet). DART PUR.

import 'dart:math' as math;
import 'dart:typed_data';

Uint8List buildBeepWav({
  int sampleRate = 44100,
  double frequencyHz = 1000,
  int durationMs = 150,
  double amplitude = 0.6,
}) {
  final samples = sampleRate * durationMs ~/ 1000;
  final dataLen = samples * 2;
  final bytes = ByteData(44 + dataLen);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLen, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // dimensiunea blocului fmt
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // biți / eșantion
  ascii(36, 'data');
  bytes.setUint32(40, dataLen, Endian.little);

  final ramp = (sampleRate * 0.008).round(); // 8 ms atac / decădere
  for (var i = 0; i < samples; i++) {
    var env = 1.0;
    if (i < ramp) env = i / ramp;
    if (samples - i < ramp) env = (samples - i) / ramp;
    final v = math.sin(2 * math.pi * frequencyHz * i / sampleRate) * amplitude * env;
    bytes.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
