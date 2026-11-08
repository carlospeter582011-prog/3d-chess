import 'dart:convert';
import 'dart:typed_data';

import 'package:chess3d/chess/types.dart';
import 'package:chess3d/game/settings.dart';
import 'package:chess3d/game/storage.dart';
import 'package:chess3d/platform/sfx_synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings', () {
    test('defaults', () {
      const s = Settings();
      expect(s.sound, isTrue);
      expect(s.labels, isTrue);
      expect(s.quality, Quality.high);
      expect(s.autoFlip, isFalse);
      expect(s.elo, 1200);
      expect(s.humanColor, HumanColor.white);
      expect(s.mode, GameMode.bot);
    });
    test('encode / decode round trip', () {
      const s = Settings(
        sound: false,
        labels: false,
        quality: Quality.low,
        autoFlip: true,
        elo: 2450,
        humanColor: HumanColor.random,
        mode: GameMode.local,
      );
      expect(Settings.decode(s.encode()), s);
    });
    test('missing, empty or broken data gives defaults', () {
      for (final bad in [null, '', 'garbage', '[]', '42', '{"elo":"x","quality":"ultra","mode":5}']) {
        final s = Settings.decode(bad);
        expect(s.elo, 1200, reason: '$bad');
        expect(s.quality, Quality.high, reason: '$bad');
        expect(s.mode, GameMode.bot, reason: '$bad');
      }
    });
    test('elo is clamped to the valid range', () {
      expect(Settings.decode('{"elo": 50}').elo, 400);
      expect(Settings.decode('{"elo": 99999}').elo, 3200);
    });
    test('copyWith changes only what is given', () {
      const s = Settings();
      final n = s.copyWith(elo: 2000);
      expect(n.elo, 2000);
      expect(n.sound, s.sound);
      expect(n.labels, s.labels);
    });
  });

  group('GameConfig', () {
    test('json round trip', () {
      const c = GameConfig(mode: GameMode.local, humanColor: Side.b, elo: 777);
      expect(GameConfig.fromJson(jsonDecode(jsonEncode(c.toJson()))), c);
    });
    test('bad json gives null', () {
      expect(GameConfig.fromJson(null), isNull);
      expect(GameConfig.fromJson('x'), isNull);
    });
  });

  group('eloName', () {
    test('names grow with strength', () {
      expect(eloName(400), 'Beginner');
      expect(eloName(1200), 'Casual');
      expect(eloName(3200), 'Grandmaster+');
    });
  });

  group('MemoryStore', () {
    test('set / get / remove', () {
      final s = MemoryStore();
      expect(s.get('a'), isNull);
      s.set('a', '1');
      expect(s.get('a'), '1');
      s.remove('a');
      expect(s.get('a'), isNull);
    });
  });

  group('sound synthesis', () {
    test('every sound exists and has a plausible length', () {
      expect(soundNames.toSet(), {'move', 'capture', 'check', 'end'});
      for (final n in soundNames) {
        final s = synthesize(n);
        expect(s.length, greaterThan(sampleRate ~/ 20), reason: n);
        expect(s.length, lessThan(sampleRate), reason: n);
      }
    });
    test('samples are finite, within -1..1 and not silent', () {
      for (final n in soundNames) {
        final s = synthesize(n);
        var peak = 0.0;
        for (final v in s) {
          expect(v.isFinite, isTrue, reason: n);
          expect(v.abs(), lessThanOrEqualTo(1.0), reason: n);
          peak = peak < v.abs() ? v.abs() : peak;
        }
        expect(peak, greaterThan(0.02), reason: '$n is silent');
      }
    });
    test('synthesis is deterministic for a given seed', () {
      expect(synthesize('capture', seed: 3), synthesize('capture', seed: 3));
    });
    test('the capture sound is longer than a plain move; the end sound is the longest', () {
      expect(synthesize('capture').length, greaterThan(synthesize('move').length));
      expect(synthesize('end').length, greaterThan(synthesize('capture').length));
    });
    test('unknown sound throws', () {
      expect(() => synthesize('nope'), throwsArgumentError);
    });
    test('WAV container is valid mono 16-bit PCM', () {
      final samples = synthesize('move');
      final wav = toWav(samples);
      final bd = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(bd.getUint16(20, Endian.little), 1); // PCM
      expect(bd.getUint16(22, Endian.little), 1); // mono
      expect(bd.getUint32(24, Endian.little), sampleRate);
      expect(bd.getUint16(34, Endian.little), 16);
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(bd.getUint32(40, Endian.little), samples.length * 2);
      expect(wav.length, 44 + samples.length * 2);
      expect(bd.getUint32(4, Endian.little), wav.length - 8);
    });
  });
}
