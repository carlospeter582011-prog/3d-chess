// The UCI client talking to a fake engine.

import 'dart:async';

import 'package:chess3d/chess/uci_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTransport implements UciTransport {
  final StreamController<String> _c = StreamController<String>.broadcast(sync: true);
  final List<String> sent = [];
  bool started = false;
  bool disposed = false;

  /// What the fake engine answers to "go".
  List<String> goReply = ['info depth 10 multipv 1 score cp 50 pv e2e4 e7e5', 'bestmove e2e4 ponder e7e5'];
  bool answerGo = true;
  bool answerUci = true;

  @override
  Stream<String> get lines => _c.stream;

  @override
  Future<void> start() async => started = true;

  @override
  void send(String command) {
    sent.add(command);
    scheduleMicrotask(() {
      if (command == 'uci' && answerUci) {
        _c.add('id name FakeFish');
        _c.add('option name UCI_Elo type spin default 1320 min 1320 max 3190');
        _c.add('uciok');
      } else if (command == 'isready') {
        _c.add('readyok');
      } else if (command.startsWith('go') && answerGo) {
        for (final l in goReply) {
          _c.add(l);
        }
      }
    });
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  test('handshake, options and a normal search', () async {
    final t = FakeTransport();
    final e = UciEngine(t);
    final mv = await e.bestMove('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 2000);
    expect(mv, 'e2e4');
    expect(t.started, isTrue);
    expect(t.sent.first, 'uci');
    expect(t.sent, contains('ucinewgame'));
    expect(t.sent, contains('setoption name MultiPV value 1'));
    expect(t.sent, contains('setoption name UCI_LimitStrength value true'));
    expect(t.sent, contains('setoption name UCI_Elo value 2000'));
    expect(t.sent.any((s) => s.startsWith('position fen rnbqkbnr/')), isTrue);
    final go = t.sent.firstWhere((s) => s.startsWith('go'));
    expect(go, startsWith('go movetime '));
    e.dispose();
    expect(t.disposed, isTrue);
  });

  test('full strength turns limiting off', () async {
    final t = FakeTransport();
    final e = UciEngine(t);
    await e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 3200);
    expect(t.sent, contains('setoption name UCI_LimitStrength value false'));
    expect(t.sent.where((s) => s.contains('UCI_Elo')), isEmpty);
    e.dispose();
  });

  test('UCI_Elo is clamped to the range the engine reports', () async {
    final t = FakeTransport();
    final e = UciEngine(t);
    await e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 3190);
    expect(t.sent, contains('setoption name UCI_Elo value 3190'));
    e.dispose();
  });

  test('"ucinewgame" is sent once per game, again after resetGame', () async {
    final t = FakeTransport();
    final e = UciEngine(t);
    await e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 2000);
    await e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 2000);
    expect(t.sent.where((s) => s == 'ucinewgame').length, 1);
    e.resetGame();
    await e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 2000);
    expect(t.sent.where((s) => s == 'ucinewgame').length, 2);
    e.dispose();
  });

  test('very low Elo asks for several candidates and picks among them with the weakness model', () async {
    final t = FakeTransport()
      ..goReply = [
        'info depth 3 multipv 1 score cp 80 pv e2e4',
        'info depth 3 multipv 2 score cp 20 pv d2d4',
        'info depth 3 multipv 3 score cp -60 pv a2a3',
        'bestmove e2e4',
      ];
    var n = 0;
    final seq = [0.0, 0.9999]; // "make a mistake", then pick the last candidate
    final e = UciEngine(t, random: () => seq[n++ % 2]);
    final mv = await e.bestMove('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 400);
    expect(t.sent, contains('setoption name MultiPV value 6'));
    final go = t.sent.firstWhere((s) => s.startsWith('go'));
    expect(go, contains('depth '));
    expect(go, contains('movetime 120'));
    expect(mv, 'a2a3');
    e.dispose();
  });

  test('mate scores are ranked above any centipawn score', () async {
    final t = FakeTransport()
      ..goReply = [
        'info depth 3 multipv 1 score cp 900 pv a2a3',
        'info depth 3 multipv 2 score mate 2 pv h2h4',
        'bestmove a2a3',
      ];
    final e = UciEngine(t, random: () => 0.99); // "no mistake": play the best-scored candidate
    final mv = await e.bestMove('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 400);
    expect(mv, 'h2h4');
    e.dispose();
  });

  test('a silent engine gives up with null instead of hanging', () async {
    final t = FakeTransport()..answerGo = false;
    final e = UciEngine(t, searchSlack: const Duration(milliseconds: 50));
    final mv = await e.bestMove('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 400);
    expect(mv, isNull);
    expect(t.sent, contains('stop'));
    e.dispose();
  });

  test('"bestmove (none)" returns null', () async {
    final t = FakeTransport()..goReply = ['bestmove (none)'];
    final e = UciEngine(t);
    expect(await e.bestMove('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', 2000), isNull);
    e.dispose();
  });

  test('an engine that never answers "uci" fails with an error and can be retried', () async {
    final t = FakeTransport()..answerUci = false;
    final e = UciEngine(t, initTimeout: const Duration(milliseconds: 50));
    await expectLater(e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 2000), throwsA(isA<TimeoutException>()));
    t.answerUci = true;
    expect(await e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 2000), 'e2e4');
    e.dispose();
  });

  test('queued requests are served one at a time, in order', () async {
    final t = FakeTransport();
    final e = UciEngine(t);
    final a = e.bestMove('8/8/8/4k3/8/8/3K4/8 w - - 0 1', 2000);
    final b = e.bestMove('8/8/8/4k3/8/8/3K4/8 b - - 0 1', 2000);
    expect(await a, 'e2e4');
    expect(await b, 'e2e4');
    final positions = t.sent.where((s) => s.startsWith('position')).toList();
    expect(positions.length, 2);
    expect(positions[0], contains(' w '));
    expect(positions[1], contains(' b '));
    e.dispose();
  });
}
