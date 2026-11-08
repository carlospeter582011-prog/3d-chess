// Elo -> engine settings. Direct port of settingsForElo / pickCandidate from the web version's engine.ts.

import 'dart:math' as math;

class Candidate {
  final String move;
  final int cp;
  const Candidate(this.move, this.cp);
}

const int eloMin = 400;
const int eloMax = 3200;
const int _sfMin = 1320; // lowest Elo Stockfish's UCI_LimitStrength supports
const int _sfMax = 3190;

class BotSettings {
  final bool limitStrength;
  final int uciElo;
  final int movetime;
  final int multiPV;

  /// extra human-like mistakes for Elo below Stockfish's own minimum (0..1)
  final double weakness;

  const BotSettings({
    required this.limitStrength,
    required this.uciElo,
    required this.movetime,
    required this.multiPV,
    required this.weakness,
  });

  @override
  String toString() =>
      'BotSettings(limit=$limitStrength, elo=$uciElo, movetime=$movetime, multiPV=$multiPV, weakness=$weakness)';
}

/// Maps a target Elo (400-3200) to engine settings.
BotSettings settingsForElo(num elo) {
  final e = math.max(eloMin, math.min(eloMax, elo.round()));
  if (e >= _sfMin) {
    if (e > _sfMax) {
      return const BotSettings(limitStrength: false, uciElo: _sfMax, movetime: 1500, multiPV: 1, weakness: 0);
    }
    final movetime = (400 + ((e - _sfMin) / (_sfMax - _sfMin)) * 1100).round();
    return BotSettings(limitStrength: true, uciElo: e, movetime: movetime, multiPV: 1, weakness: 0);
  }
  // below 1320: weakest Stockfish + shallow search + a growing chance of picking a worse move
  final weakness = (_sfMin - e) / (_sfMin - eloMin); // 0..1
  return BotSettings(limitStrength: true, uciElo: _sfMin, movetime: 120, multiPV: 6, weakness: weakness);
}

/// Chooses among MultiPV candidates; the weaker the bot, the more it drifts down the list.
String pickCandidate(List<Candidate> cands, double weakness, [double Function()? rnd]) {
  final next = rnd ?? math.Random().nextDouble;
  if (cands.length == 1 || weakness <= 0) return cands[0].move;
  final sorted = [...cands]..sort((a, b) => b.cp.compareTo(a.cp));
  // probability of deviating from the best move
  if (next() > 0.15 + 0.8 * weakness) return sorted[0].move;
  // weights favour better moves but give worse ones a chance, flattening with weakness
  final tau = 0.6 + 3.5 * weakness;
  final w = [for (var i = 0; i < sorted.length; i++) math.exp(-i / tau)];
  final sum = w.fold<double>(0, (a, b) => a + b);
  var r = next() * sum;
  for (var i = 0; i < w.length; i++) {
    r -= w[i];
    if (r <= 0) return sorted[i].move;
  }
  return sorted[0].move;
}
