// UCI client: talks to Stockfish through a [UciTransport]. Port of the Engine class from the web version.
// The transport is abstract so the logic can be unit-tested with a fake engine.

import 'dart:async';

import 'elo.dart';

/// Something that can talk UCI: a real Stockfish process or a test double.
abstract class UciTransport {
  /// Output lines of the engine. Must be a broadcast stream.
  Stream<String> get lines;

  /// Starts the engine (idempotent).
  Future<void> start();

  void send(String command);

  void dispose();
}

/// What the game needs from a bot.
abstract class BotEngine {
  /// Best move in UCI form ("e2e4", "e7e8q"), or null if cancelled / no move.
  Future<String?> bestMove(String fen, int elo);

  /// Abort the current search.
  void stop();

  /// Tell the engine a new game starts.
  void resetGame();

  void dispose();
}

class _Pending {
  final Completer<String?> completer;
  final Map<int, Candidate> cands = {};
  final double weakness;
  _Pending(this.completer, this.weakness);
}

class UciEngine implements BotEngine {
  UciEngine(
    this._transport, {
    this.initTimeout = const Duration(seconds: 60),
    this.commandTimeout = const Duration(seconds: 20),
    this.searchSlack = const Duration(seconds: 10),
    double Function()? random,
  }) : _random = random;

  final UciTransport _transport;
  final Duration initTimeout;
  final Duration commandTimeout;

  /// Extra time on top of movetime before a search is declared dead.
  final Duration searchSlack;
  final double Function()? _random;

  StreamSubscription<String>? _sub;
  final List<void Function(String)> _listeners = [];
  Future<void>? _ready;
  _Pending? _pending;
  Future<Object?> _chain = Future<Object?>.value();
  bool _newGameNeeded = true;
  int? _eloMin;
  int? _eloMax;

  void _send(String cmd) => _transport.send(cmd);

  Future<String> _waitFor(bool Function(String) test, Duration timeout) {
    final c = Completer<String>();
    late void Function(String) fn;
    final timer = Timer(timeout, () {
      _listeners.remove(fn);
      if (!c.isCompleted) c.completeError(TimeoutException('engine timeout'));
    });
    fn = (l) {
      if (test(l)) {
        timer.cancel();
        _listeners.remove(fn);
        if (!c.isCompleted) c.complete(l);
      }
    };
    _listeners.add(fn);
    return c.future;
  }

  Future<void> init() => _ready ??= _init();

  Future<void> _init() async {
    try {
      await _transport.start();
      await _sub?.cancel();
      _sub = _transport.lines.listen(_onRawLine);
      final lines = <String>[];
      void collect(String l) => lines.add(l);
      _listeners.add(collect);
      final uciok = _waitFor((l) => l == 'uciok', initTimeout);
      _send('uci');
      await uciok;
      _listeners.remove(collect);
      for (final l in lines) {
        if (l.contains('name UCI_Elo ')) {
          final mn = RegExp(r'min (\d+)').firstMatch(l);
          final mx = RegExp(r'max (\d+)').firstMatch(l);
          _eloMin = mn == null ? null : int.parse(mn.group(1)!);
          _eloMax = mx == null ? null : int.parse(mx.group(1)!);
        }
      }
      await _isReady();
    } catch (e) {
      _ready = null; // allow a retry on the next request
      rethrow;
    }
  }

  Future<void> _isReady() async {
    final p = _waitFor((l) => l == 'readyok', commandTimeout);
    _send('isready');
    await p;
  }

  void _onRawLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    _onLine(line);
    for (final l in List.of(_listeners)) {
      l(line);
    }
  }

  void _onLine(String line) {
    final p = _pending;
    if (p == null) return;
    if (line.startsWith('info ') && line.contains(' pv ')) {
      final mpv = RegExp(r'multipv (\d+)').firstMatch(line);
      final idx = mpv == null ? 1 : int.parse(mpv.group(1)!);
      final cp = RegExp(r'score cp (-?\d+)').firstMatch(line);
      final mate = RegExp(r'score mate (-?\d+)').firstMatch(line);
      final pv = RegExp(r' pv (\S+)').firstMatch(line);
      if (pv != null && (cp != null || mate != null)) {
        int score;
        if (cp != null) {
          score = int.parse(cp.group(1)!);
        } else {
          final m = int.parse(mate!.group(1)!);
          score = m > 0 ? 100000 - m : -100000 - m;
        }
        p.cands[idx] = Candidate(pv.group(1)!, score);
      }
    } else if (line.startsWith('bestmove')) {
      final m = RegExp(r'bestmove (\S+)').firstMatch(line);
      final best = (m != null && m.group(1) != '(none)') ? m.group(1) : null;
      _pending = null;
      var chosen = best;
      if (best != null && p.cands.length > 1) {
        chosen = pickCandidate(p.cands.values.toList(), p.weakness, _random);
      }
      if (!p.completer.isCompleted) p.completer.complete(chosen);
    }
  }

  @override
  Future<String?> bestMove(String fen, int elo) {
    Future<String?> run() async {
      await init();
      final s = settingsForElo(elo);
      if (_newGameNeeded) {
        _send('ucinewgame');
        _newGameNeeded = false;
      }
      _send('setoption name MultiPV value ${s.multiPV}');
      _send('setoption name UCI_LimitStrength value ${s.limitStrength}');
      if (s.limitStrength) {
        final lo = _eloMin ?? 1320, hi = _eloMax ?? 3190;
        _send('setoption name UCI_Elo value ${s.uciElo.clamp(lo, hi)}');
      }
      await _isReady();
      _send('position fen $fen');
      final completer = Completer<String?>();
      _pending = _Pending(completer, s.weakness);
      _send(s.weakness > 0
          ? 'go depth ${1 + ((1 - s.weakness) * 3).round()} movetime ${s.movetime}'
          : 'go movetime ${s.movetime}');
      return completer.future.timeout(Duration(milliseconds: s.movetime) + searchSlack, onTimeout: () {
        _pending = null;
        _send('stop');
        return null;
      });
    }

    // serialise requests
    final p = _chain.then<String?>((_) => run(), onError: (Object _) => run());
    _chain = p.then<Object?>((v) => v, onError: (Object _) => null);
    return p;
  }

  @override
  void stop() {
    if (_pending != null) _send('stop');
  }

  @override
  void resetGame() => _newGameNeeded = true;

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _pending = null;
    _ready = null;
    _transport.dispose();
  }
}
