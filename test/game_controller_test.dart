// The game controller (ported from Game.ts) running against the real 3D board model and a scripted bot.

import 'dart:async';

import 'package:chess3d/chess/rules.dart';
import 'package:chess3d/chess/types.dart';
import 'package:chess3d/chess/uci_engine.dart';
import 'package:chess3d/game/game_controller.dart';
import 'package:chess3d/game/settings.dart';
import 'package:chess3d/game/storage.dart';
import 'package:chess3d/scene/board_model.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeEngine implements BotEngine {
  final List<String?> script;
  Future<String?> Function(String fen, int elo)? handler;
  int resets = 0;
  int stops = 0;
  bool disposed = false;
  final List<String> fens = [];
  final List<int> elos = [];
  FakeEngine([List<String?>? script]) : script = script ?? [];

  @override
  Future<String?> bestMove(String fen, int elo) {
    fens.add(fen);
    elos.add(elo);
    if (handler != null) return handler!(fen, elo);
    return Future.value(script.isEmpty ? null : script.removeAt(0));
  }

  @override
  void stop() => stops++;
  @override
  void resetGame() => resets++;
  @override
  void dispose() => disposed = true;
}

class Rig {
  final BoardModel board = BoardModel()..animations = false;
  final FakeEngine engine;
  final MemoryStore store = MemoryStore();
  final SilentSfx sfx = SilentSfx();
  late final GameController game;

  Rig([List<String?>? bot]) : engine = FakeEngine(bot) {
    game = GameController(board: board, engine: engine, store: store, sfx: sfx, thinkMinimum: Duration.zero);
  }

  GameSnapshot get s => game.snapshot;

  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await pumpEventQueue();
      if (!game.snapshot.busy && !game.snapshot.thinking) return;
    }
  }

  /// Taps from-square then to-square and waits for everything to finish.
  Future<void> play(String from, String to) async {
    game.tap(from);
    game.tap(to);
    await settle();
  }

  void expectBoardMatchesRules() {
    expect(board.snapshot().toSet(), game.chess.pieces().toSet());
  }
}

const botWhite = GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1200);
const botBlack = GameConfig(mode: GameMode.bot, humanColor: Side.b, elo: 1500);
const local = GameConfig(mode: GameMode.local, humanColor: Side.w, elo: 1200);

void main() {
  group('starting a game', () {
    test('the 3D board shows the standard start position', () {
      final r = Rig();
      r.game.start(botWhite);
      expect(r.s.active, isTrue);
      expect(r.s.turn, Side.w);
      expect(r.s.fen, Chess.startFen);
      expect(r.board.pieceCount, 32);
      r.expectBoardMatchesRules();
      expect(r.engine.resets, 1);
    });

    test('playing White: camera looks from White\'s side; playing Black: from Black\'s side', () {
      final r = Rig([null]);
      r.game.start(botWhite);
      expect(r.board.viewSide(), Side.w);
      final r2 = Rig([null]);
      r2.game.start(botBlack);
      expect(r2.board.viewSide(), Side.b);
    });

    test('nothing is active before start, and the menu can be left and resumed', () {
      final r = Rig();
      expect(r.s.active, isFalse);
      r.game.start(local);
      r.game.leave();
      expect(r.s.active, isFalse);
      r.game.resume();
      expect(r.s.active, isTrue);
    });
  });

  group('selecting and moving', () {
    test('tapping your own piece selects it, lifts it and shows its legal targets', () {
      final r = Rig();
      r.game.start(local);
      r.game.tap('e2');
      expect(r.s.selected, 'e2');
      expect(r.board.pieceOn('e2')!.pos.y, greaterThan(0.464));
      expect(r.board.markers.selected, 'e2');
      expect(r.board.markers.targets.map((t) => t.square).toSet(), {'e3', 'e4'});
      expect(r.board.markers.targets.any((t) => t.capture), isFalse);
    });

    test('capture targets are marked as captures', () {
      final r = Rig();
      r.game.start(local);
      r.game.debugLoadFen('4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1');
      r.game.tap('e4');
      final caps = r.board.markers.targets.where((t) => t.capture).map((t) => t.square).toList();
      expect(caps, ['d5']);
    });

    test('tapping an enemy piece or an empty square without a selection does nothing', () {
      final r = Rig();
      r.game.start(local);
      r.game.tap('e7');
      r.game.tap('e4');
      expect(r.s.selected, isNull);
    });

    test('tapping a different own piece changes the selection', () {
      final r = Rig();
      r.game.start(local);
      r.game.tap('e2');
      r.game.tap('d2');
      expect(r.s.selected, 'd2');
      expect(r.board.pieceOn('e2')!.pos.y, closeTo(0.464, 1e-9));
    });

    test('tapping an illegal square deselects', () {
      final r = Rig();
      r.game.start(local);
      r.game.tap('e2');
      r.game.tap('e5');
      expect(r.s.selected, isNull);
      expect(r.board.markers.targets, isEmpty);
      expect(r.s.history, isEmpty);
    });

    test('a legal move is played on the board and in the rules, with SAN', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      expect(r.s.history, ['e4']);
      expect(r.s.turn, Side.b);
      r.expectBoardMatchesRules();
      expect(r.board.markers.last, ('e2', 'e4'));
      expect(r.sfx.played, ['move']);
    });

    test('taps are ignored while the other side is to move (bot thinking)', () async {
      final r = Rig();
      final gate = Completer<String?>();
      r.engine.handler = (_, __) => gate.future;
      r.game.start(botWhite);
      await r.play('e2', 'e4');
      expect(r.s.thinking, isTrue);
      r.game.tap('d7');
      expect(r.s.selected, isNull);
      gate.complete('e7e5');
      await r.settle();
      expect(r.s.history, ['e4', 'e5']);
    });

    test('the floor square under the finger is used when a tall piece hides the target', () async {
      final r = Rig();
      r.game.start(local);
      r.game.tap('g1');
      // finger lands on the selected knight itself while the floor under it is f3
      r.game.tap('g1', 'f3');
      await r.settle();
      expect(r.s.history, ['Nf3']);
    });

    test('but not when the tap is on another of your own pieces', () {
      final r = Rig();
      r.game.start(local);
      r.game.tap('g1');
      r.game.tap('h1', 'f3'); // own rook, floor says f3: selection switches to the rook instead of moving
      expect(r.s.history, isEmpty);
      expect(r.s.selected, 'h1');
    });
  });

  group('bot', () {
    test('answers a human move with the engine\'s move', () async {
      final r = Rig(['e7e5']);
      r.game.start(botWhite);
      await r.play('e2', 'e4');
      expect(r.s.history, ['e4', 'e5']);
      expect(r.s.turn, Side.w);
      expect(r.engine.elos.single, 1200);
      expect(r.engine.fens.single, contains(' b '));
      r.expectBoardMatchesRules();
    });

    test('moves first when the human plays Black', () async {
      final r = Rig(['e2e4']);
      r.game.start(botBlack);
      await r.settle();
      expect(r.s.history, ['e4']);
      expect(r.s.turn, Side.b);
      expect(r.engine.elos.single, 1500);
      r.expectBoardMatchesRules();
    });

    test('an illegal bot move is replaced by a random legal one and flagged', () async {
      final r = Rig(['e7e2']);
      r.game.start(botWhite);
      await r.play('e2', 'e4');
      expect(r.s.history.length, 2);
      expect(r.s.engineError, isTrue);
      r.expectBoardMatchesRules();
    });

    test('an engine that throws falls back to a random legal move', () async {
      final r = Rig();
      r.engine.handler = (_, __) => Future<String?>.error(StateError('engine crashed'));
      r.game.start(botWhite);
      await r.play('d2', 'd4');
      expect(r.s.history.length, 2);
      expect(r.s.engineError, isTrue);
    });

    test('an engine that returns nothing falls back to a random legal move', () async {
      final r = Rig([null]);
      r.game.start(botWhite);
      await r.play('d2', 'd4');
      expect(r.s.history.length, 2);
    });

    test('the bot can promote', () async {
      final r = Rig(['a2a1q']);
      r.game.start(botWhite);
      r.game.debugLoadFen('7k/8/8/8/8/5K2/p7/8 w - - 0 1');
      await r.play('f3', 'f2');
      expect(r.s.history.last, 'a1=Q');
      expect(r.board.pieceOn('a1')!.type, PT.q);
      r.expectBoardMatchesRules();
    });

    test('undo while the bot is thinking cancels its answer', () async {
      final r = Rig();
      final gate = Completer<String?>();
      r.engine.handler = (_, __) => gate.future;
      r.game.start(botWhite);
      await r.play('e2', 'e4');
      expect(r.s.thinking, isTrue);
      r.game.undo();
      expect(r.engine.stops, greaterThan(0));
      gate.complete('e7e5'); // stale answer must be ignored
      await r.settle();
      expect(r.s.history, isEmpty);
      expect(r.s.fen, Chess.startFen);
      r.expectBoardMatchesRules();
    });

    test('a new game while the bot is thinking ignores the old answer', () async {
      final r = Rig();
      final gate = Completer<String?>();
      r.engine.handler = (_, __) => gate.future;
      r.game.start(botWhite);
      await r.play('e2', 'e4');
      r.game.start(local);
      gate.complete('e7e5');
      await r.settle();
      expect(r.s.history, isEmpty);
    });
  });

  group('promotion', () {
    test('tapping the last rank asks which piece, then promotes on the board', () async {
      final r = Rig();
      r.game.start(local);
      r.game.debugLoadFen('8/P6k/8/8/8/8/7K/8 w - - 0 1');
      r.game.tap('a7');
      r.game.tap('a8');
      expect(r.s.promotion, isNotNull);
      expect(r.s.promotion!.from, 'a7');
      expect(r.s.promotion!.to, 'a8');
      expect(r.s.history, isEmpty);
      r.game.choosePromotion(PT.n);
      await r.settle();
      expect(r.s.promotion, isNull);
      expect(r.board.pieceOn('a8')!.type, PT.n);
      expect(r.s.history.single, 'a8=N');
      r.expectBoardMatchesRules();
    });

    test('cancelling leaves the pawn where it was', () {
      final r = Rig();
      r.game.start(local);
      r.game.debugLoadFen('8/P6k/8/8/8/8/7K/8 w - - 0 1');
      r.game.tap('a7');
      r.game.tap('a8');
      r.game.cancelPromotion();
      expect(r.s.promotion, isNull);
      expect(r.s.selected, isNull);
      expect(r.s.history, isEmpty);
      expect(r.board.pieceOn('a7')!.type, PT.p);
    });

    test('a pawn or king is not a valid choice', () {
      final r = Rig();
      r.game.start(local);
      r.game.debugLoadFen('8/P6k/8/8/8/8/7K/8 w - - 0 1');
      r.game.tap('a7');
      r.game.tap('a8');
      r.game.choosePromotion(PT.k);
      r.game.choosePromotion(PT.p);
      expect(r.s.promotion, isNotNull);
    });

    test('taps are ignored while the promotion picker is open', () {
      final r = Rig();
      r.game.start(local);
      r.game.debugLoadFen('8/P6k/8/8/8/8/7K/8 w - - 0 1');
      r.game.tap('a7');
      r.game.tap('a8');
      r.game.tap('h2');
      expect(r.s.promotion, isNotNull);
    });
  });

  group('special moves through the UI', () {
    test('castling moves both pieces', () async {
      final r = Rig();
      r.game.start(local);
      r.game.debugLoadFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      await r.play('e1', 'g1');
      expect(r.s.history.single, 'O-O');
      expect(r.board.pieceOn('f1')!.type, PT.r);
      expect(r.board.pieceOn('g1')!.type, PT.k);
      expect(r.board.pieceOn('h1'), isNull);
      r.expectBoardMatchesRules();
      await r.play('e8', 'c8');
      expect(r.board.pieceOn('d8')!.type, PT.r);
      expect(r.board.pieceOn('a8'), isNull);
      r.expectBoardMatchesRules();
    });

    test('en passant removes the right pawn', () async {
      final r = Rig();
      r.game.start(local);
      for (final m in [['e2', 'e4'], ['a7', 'a6'], ['e4', 'e5'], ['d7', 'd5']]) {
        await r.play(m[0], m[1]);
      }
      await r.play('e5', 'd6');
      expect(r.s.history.last, 'exd6');
      expect(r.board.pieceOn('d5'), isNull);
      r.expectBoardMatchesRules();
      expect(r.s.captured[Side.b], [PT.p]);
    });
  });

  group('game end', () {
    Future<Rig> foolsMate() async {
      final r = Rig();
      r.game.start(local);
      await r.play('f2', 'f3');
      await r.play('e7', 'e5');
      await r.play('g2', 'g4');
      await r.play('d8', 'h4');
      return r;
    }

    test('checkmate: Black wins, sounds played, no more moves', () async {
      final r = await foolsMate();
      expect(r.s.status, GameStatus.checkmate);
      expect(r.s.winner, Side.b);
      expect(r.s.check, isTrue);
      expect(r.sfx.played.last, 'end');
      r.game.tap('a2');
      expect(r.s.selected, isNull);
    });

    test('the finished game is not kept as a saved game', () async {
      final r = await foolsMate();
      expect(r.store.get(saveKey), isNull);
    });

    test('check is announced with its own sound and a marker on the king', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      await r.play('f7', 'f5');
      await r.play('d1', 'h5');
      expect(r.s.check, isTrue);
      expect(r.sfx.played.last, 'check');
      expect(r.board.markers.check, 'e8');
    });

    test('stalemate', () {
      final r = Rig();
      r.game.start(local);
      r.game.debugLoadFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(r.s.status, GameStatus.stalemate);
      expect(r.s.winner, isNull);
    });

    test('resign in a bot game: the human loses', () {
      final r = Rig();
      r.game.start(botWhite);
      r.game.resign();
      expect(r.s.status, GameStatus.resigned);
      expect(r.s.winner, Side.b);
      expect(r.s.reason, 'White resigned');
      expect(r.s.canUndo, isFalse);
    });

    test('resign in a 2 player game: the side to move loses', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      r.game.resign();
      expect(r.s.winner, Side.w);
      expect(r.s.reason, 'Black resigned');
    });

    test('agreed draw', () {
      final r = Rig();
      r.game.start(local);
      r.game.agreeDraw();
      expect(r.s.status, GameStatus.draw);
      expect(r.s.reason, 'Draw agreed');
      expect(r.s.winner, isNull);
    });

    test('after the end resign / draw do nothing', () async {
      final r = await foolsMate();
      r.game.resign();
      r.game.agreeDraw();
      expect(r.s.status, GameStatus.checkmate);
    });

    test('rematch starts a fresh game with the same settings', () async {
      final r = await foolsMate();
      r.game.start(r.s.config);
      expect(r.s.history, isEmpty);
      expect(r.s.status, GameStatus.playing);
      r.expectBoardMatchesRules();
    });
  });

  group('undo', () {
    test('2 players: one move back', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      await r.play('e7', 'e5');
      r.game.undo();
      expect(r.s.history, ['e4']);
      expect(r.s.turn, Side.b);
      r.expectBoardMatchesRules();
    });

    test('against the bot: your move and the bot\'s answer are taken back', () async {
      final r = Rig(['e7e5']);
      r.game.start(botWhite);
      await r.play('e2', 'e4');
      r.game.undo();
      expect(r.s.history, isEmpty);
      expect(r.s.turn, Side.w);
      expect(r.s.fen, Chess.startFen);
      r.expectBoardMatchesRules();
    });

    test('undo restores a captured piece on the board', () async {
      final r = Rig();
      r.game.start(local);
      for (final m in [['e2', 'e4'], ['d7', 'd5'], ['e4', 'd5']]) {
        await r.play(m[0], m[1]);
      }
      expect(r.board.pieceCount, 31);
      r.game.undo();
      expect(r.board.pieceCount, 32);
      r.expectBoardMatchesRules();
    });

    test('nothing to undo at the start', () {
      final r = Rig();
      r.game.start(local);
      expect(r.s.canUndo, isFalse);
      r.game.undo();
      expect(r.s.history, isEmpty);
    });

    test('undo after a draw agreement reopens the game', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      r.game.agreeDraw();
      r.game.undo();
      expect(r.s.status, GameStatus.playing);
    });
  });

  group('captured pieces and material', () {
    test('snapshot lists the pieces each side has lost', () async {
      final r = Rig();
      r.game.start(local);
      for (final m in [['e2', 'e4'], ['d7', 'd5'], ['e4', 'd5'], ['d8', 'd5']]) {
        await r.play(m[0], m[1]);
      }
      expect(r.s.captured[Side.b], [PT.p]); // Black lost a pawn
      expect(r.s.captured[Side.w], [PT.p]); // White lost a pawn
    });
  });

  group('2 player auto-turn view', () {
    test('the camera follows whoever moves next', () async {
      final r = Rig();
      r.game.autoFlip = true;
      r.game.start(local);
      expect(r.board.viewSide(), Side.w);
      await r.play('e2', 'e4');
      expect(r.board.viewSide(), Side.b);
      await r.play('e7', 'e5');
      expect(r.board.viewSide(), Side.w);
    });

    test('without it the camera stays put', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      expect(r.board.viewSide(), Side.w);
    });
  });

  group('saving and resuming', () {
    test('a running game is saved after every move', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      await r.play('e7', 'e5');
      final saved = GameController.loadSaved(r.store)!;
      expect(saved.moves, ['e2e4', 'e7e5']);
      expect(saved.config, local);
    });

    test('resuming restores the exact position on the board', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      await r.play('g8', 'f6');
      final saved = GameController.loadSaved(r.store)!;

      final r2 = Rig();
      r2.game.start(saved.config, moves: saved.moves);
      expect(r2.s.history, ['e4', 'Nf6']);
      expect(r2.s.fen, r.s.fen);
      r2.expectBoardMatchesRules();
    });

    test('resuming a bot game where it is the bot\'s turn makes the bot move', () async {
      final r = Rig(['e7e5']);
      r.game.start(botWhite, moves: ['e2e4']);
      await r.settle();
      expect(r.s.history, ['e4', 'e5']);
    });

    test('a corrupted save is ignored instead of crashing', () {
      final store = MemoryStore();
      for (final bad in ['not json', '[]', '{"config":{},"moves":"x"}', '{"config":{"mode":"bot"},"moves":["e2e5"]}', '{"moves":[]}']) {
        store.set(saveKey, bad);
        expect(GameController.loadSaved(store), isNull, reason: bad);
      }
    });

    test('a save with an illegal move in the middle is ignored', () {
      final store = MemoryStore()..set(saveKey, '{"config":{"mode":"local","humanColor":"w","elo":1200},"moves":["e2e4","e2e4"]}');
      expect(GameController.loadSaved(store), isNull);
    });

    test('starting with an illegal move list falls back to a new game', () {
      final r = Rig();
      r.game.start(local, moves: ['e2e5']);
      expect(r.s.fen, Chess.startFen);
    });

    test('clearSaved removes it', () async {
      final r = Rig();
      r.game.start(local);
      await r.play('e2', 'e4');
      GameController.clearSaved(r.store);
      expect(GameController.loadSaved(r.store), isNull);
    });
  });

  group('settings', () {
    test('sound and labels are applied', () {
      final r = Rig();
      r.game.applySettings(const Settings(sound: false, labels: false, autoFlip: true));
      expect(r.board.labelsVisible, isFalse);
      expect(r.game.autoFlip, isTrue);
    });
  });
}
