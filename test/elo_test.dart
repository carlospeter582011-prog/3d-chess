import 'package:chess3d/chess/elo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settingsForElo', () {
    test('range limits are 400..3200', () {
      expect(eloMin, 400);
      expect(eloMax, 3200);
    });
    test('1320 is Stockfish\'s own minimum: no extra weakness', () {
      final s = settingsForElo(1320);
      expect(s.limitStrength, isTrue);
      expect(s.uciElo, 1320);
      expect(s.multiPV, 1);
      expect(s.weakness, 0);
      expect(s.movetime, 400);
    });
    test('400 is the weakest: shallow, MultiPV 6, full weakness', () {
      final s = settingsForElo(400);
      expect(s.limitStrength, isTrue);
      expect(s.uciElo, 1320);
      expect(s.multiPV, 6);
      expect(s.weakness, 1);
      expect(s.movetime, 120);
    });
    test('weakness grows linearly below 1320', () {
      expect(settingsForElo(860).weakness, closeTo(0.5, 1e-9));
      expect(settingsForElo(1100).weakness, closeTo((1320 - 1100) / 920, 1e-9));
    });
    test('above 1320 the strength is limited and the time grows', () {
      final lo = settingsForElo(1400), hi = settingsForElo(3000);
      expect(lo.uciElo, 1400);
      expect(hi.uciElo, 3000);
      expect(hi.movetime, greaterThan(lo.movetime));
      expect(hi.multiPV, 1);
      expect(hi.weakness, 0);
    });
    test('3190 is the top limited level, above it the engine plays at full strength', () {
      final top = settingsForElo(3190);
      expect(top.limitStrength, isTrue);
      expect(top.movetime, 1500);
      final max = settingsForElo(3200);
      expect(max.limitStrength, isFalse);
      expect(max.movetime, 1500);
    });
    test('values outside the range are clamped', () {
      expect(settingsForElo(0).weakness, 1);
      expect(settingsForElo(-50).weakness, 1);
      expect(settingsForElo(9000).limitStrength, isFalse);
    });
    test('think time never decreases with Elo above 1320', () {
      var prev = 0;
      for (var e = 1320; e <= 3190; e += 10) {
        final t = settingsForElo(e).movetime;
        expect(t, greaterThanOrEqualTo(prev));
        prev = t;
      }
    });
  });

  group('pickCandidate', () {
    const cands = [Candidate('e2e4', 50), Candidate('d2d4', 40), Candidate('a2a3', -30), Candidate('h2h4', -200)];
    test('a single candidate or zero weakness always plays the best', () {
      expect(pickCandidate(const [Candidate('a2a3', 0)], 1), 'a2a3');
      expect(pickCandidate(cands, 0), 'e2e4');
    });
    test('input order does not matter, best score wins', () {
      final shuffled = [cands[2], cands[0], cands[3], cands[1]];
      expect(pickCandidate(shuffled, 0.0001, () => 0.999), 'e2e4');
    });
    test('when the dice say "no mistake" the best move is played', () {
      expect(pickCandidate(cands, 1, () => 0.99), 'e2e4'); // threshold is 0.95 at weakness 1
    });
    test('when the dice say "mistake" a worse move can be chosen', () {
      var n = 0;
      final seq = [0.0, 0.9999];
      final picked = pickCandidate(cands, 1, () => seq[n++]);
      expect(picked, 'h2h4'); // lowest scoring candidate for the highest random draw
    });
    test('the chosen move is always one of the candidates', () {
      var i = 0;
      double rnd() => ((i++ * 37) % 100) / 100;
      for (var k = 0; k < 200; k++) {
        expect(cands.map((c) => c.move), contains(pickCandidate(cands, 0.7, rnd)));
      }
    });
    test('low weakness rarely deviates, high weakness often does', () {
      int deviations(double w) {
        var n = 0;
        var seed = 12345;
        double rnd() {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          return seed / 0x7fffffff;
        }

        for (var k = 0; k < 2000; k++) {
          if (pickCandidate(cands, w, rnd) != 'e2e4') n++;
        }
        return n;
      }

      expect(deviations(0.1), lessThan(deviations(0.9)));
    });
  });
}
