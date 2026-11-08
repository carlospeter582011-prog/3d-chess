// Synthesised wood-click sounds (a port of sound.ts). The samples are generated in Dart, wrapped as 16-bit WAV
// and handed to Android's SoundPool, so the app ships no audio files.

import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;

/// One click: noise + sine with a fast decay, through a band-pass filter at 1.6x the pitch (Q 0.9).
Float64List _click(double freq, double dur, double gain, double noise, math.Random rnd) {
  final len = (sampleRate * dur).floor();
  final raw = Float64List(len);
  for (var i = 0; i < len; i++) {
    final env = math.exp(-i / (len * 0.18));
    raw[i] = ((rnd.nextDouble() * 2 - 1) * noise + math.sin(2 * math.pi * freq * i / sampleRate) * (1 - noise)) * env;
  }
  // RBJ band-pass, constant 0 dB peak gain (same as WebAudio's "bandpass")
  final w0 = 2 * math.pi * (freq * 1.6) / sampleRate;
  final alpha = math.sin(w0) / (2 * 0.9);
  final a0 = 1 + alpha;
  final b0 = alpha / a0, b2 = -alpha / a0;
  final a1 = -2 * math.cos(w0) / a0, a2 = (1 - alpha) / a0;
  final out = Float64List(len);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < len; i++) {
    final x = raw[i];
    final y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    out[i] = y * gain;
  }
  return out;
}

class _Part {
  final double freq, dur, gain, noise;
  final double offsetMs;
  const _Part(this.freq, this.dur, this.gain, this.noise, [this.offsetMs = 0]);
}

const Map<String, List<_Part>> _recipes = {
  'move': [_Part(260, 0.12, 0.9, 0.5)],
  'capture': [_Part(190, 0.16, 1.2, 0.7), _Part(320, 0.08, 0.6, 0.5, 40)],
  'check': [_Part(520, 0.18, 0.7, 0.2), _Part(690, 0.22, 0.6, 0.1, 110)],
  'end': [_Part(330, 0.3, 0.7, 0.1), _Part(247, 0.4, 0.7, 0.1, 180)],
};

/// Names of all sounds.
List<String> get soundNames => _recipes.keys.toList();

/// Mono PCM samples in -1..1.
Float64List synthesize(String name, {int seed = 7}) {
  final parts = _recipes[name];
  if (parts == null) throw ArgumentError('unknown sound $name');
  final rnd = math.Random(seed);
  var total = 0;
  for (final p in parts) {
    total = math.max(total, (sampleRate * p.offsetMs / 1000).round() + (sampleRate * p.dur).floor());
  }
  final mix = Float64List(total);
  for (final p in parts) {
    final c = _click(p.freq, p.dur, p.gain, p.noise, rnd);
    final off = (sampleRate * p.offsetMs / 1000).round();
    for (var i = 0; i < c.length; i++) {
      mix[off + i] += c[i];
    }
  }
  for (var i = 0; i < mix.length; i++) {
    mix[i] = mix[i].clamp(-1.0, 1.0);
  }
  return mix;
}

/// A complete mono 16-bit WAV file.
Uint8List toWav(Float64List samples, {int rate = sampleRate}) {
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, (samples[i] * 32767 * 0.9).round().clamp(-32768, 32767), Endian.little);
  }
  return b.buffer.asUint8List();
}
