// The animated 3D board model: moves, captures, castling, promotion, markers and the renderer frame buffer.

import 'dart:async';
import 'dart:math' as math;

import 'package:chess3d/chess/rules.dart';
import 'package:chess3d/chess/types.dart';
import 'package:chess3d/scene/board_model.dart';
import 'package:chess3d/scene/board_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticks at 60 fps until all animations are done; returns the elapsed seconds.
double settle(BoardModel m, {double max = 5}) {
  var t = 0.0;
  while (m.isAnimating && t < max) {
    m.tick(1 / 60);
    t += 1 / 60;
  }
  return t;
}

BoardModel start({bool animated = false}) {
  final m = BoardModel()..animations = animated;
  m.setPosition(Chess().pieces());
  return m;
}

PlacedPiece pp(String sq, Side s, PT t) => PlacedPiece(sq, s, t);

void main() {
  group('instant moves (animations off)', () {
    test('a pawn move changes the snapshot exactly like the rules engine', () async {
      final chess = Chess();
      final m = start();
      chess.move('e2', 'e4');
      await m.movePiece('e2', 'e4');
      expect(m.snapshot().toSet(), chess.pieces().toSet());
    });

    test('capture removes the victim', () async {
      final chess = Chess.fromUci(['e2e4', 'd7d5']);
      final m = BoardModel()..animations = false;
      m.setPosition(chess.pieces());
      final mv = chess.move('e4', 'd5')!;
      await m.movePiece('e4', 'd5', capture: mv.isCapture ? 'd5' : null);
      expect(m.pieceCount, 31);
      expect(m.snapshot().toSet(), chess.pieces().toSet());
    });

    test('en passant removes the pawn beside, not the one on the target square', () async {
      final chess = Chess('rnbqkbnr/pppp1ppp/8/8/3Pp3/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 3');
      final m = BoardModel()..animations = false;
      m.setPosition(chess.pieces());
      final mv = chess.move('e4', 'd3')!;
      expect(mv.isEp, isTrue);
      await m.movePiece('e4', 'd3', capture: 'd4');
      expect(m.snapshot().toSet(), chess.pieces().toSet());
      expect(m.pieceOn('d4'), isNull);
    });

    test('castling moves king and rook', () async {
      final chess = Chess('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final m = BoardModel()..animations = false;
      m.setPosition(chess.pieces());
      chess.move('e1', 'g1');
      await Future.wait([m.movePiece('e1', 'g1'), m.movePiece('h1', 'f1')]);
      expect(m.snapshot().toSet(), chess.pieces().toSet());
      chess.move('e8', 'c8');
      await Future.wait([m.movePiece('e8', 'c8'), m.movePiece('a8', 'd8')]);
      expect(m.snapshot().toSet(), chess.pieces().toSet());
    });

    test('promotion replaces the pawn by the chosen piece', () async {
      final chess = Chess('1n5k/P7/8/8/8/8/7K/8 w - - 0 1');
      final m = BoardModel()..animations = false;
      m.setPosition(chess.pieces());
      final mv = chess.move('a7', 'b8', 'n')!;
      await m.movePiece('a7', 'b8', capture: 'b8', promotion: mv.promotion);
      expect(m.snapshot().toSet(), chess.pieces().toSet());
      final obj = m.pieceOn('b8')!;
      expect(obj.type, PT.n);
      expect(Slots.typeOf(obj.slot), PT.n);
      expect(m.pieceCount, 3); // two kings + the new knight (the black knight was captured)
    });

    test('moving from an empty square is an error', () async {
      final m = start();
      await expectLater(m.movePiece('e4', 'e5'), throwsStateError);
    });

    test('a full game keeps the board identical to the rules engine move by move', () async {
      final line = [
        'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'e1g1', 'f6e4', 'd2d4', 'e5d4', 'f1e1', 'd7d5', 'c4d5', 'd8d5',
        'b1c3', 'd5a5', 'c3e4', 'f8e7', 'f3d4', 'c6d4', 'd1d4', 'e8g8', 'c1g5', 'e7g5', 'e4g5', 'a5g5',
      ];
      final chess = Chess();
      final m = start();
      for (final u in line) {
        final mv = chess.moveUci(u);
        expect(mv, isNotNull, reason: u);
        final rank = mv!.fromName[1];
        final cap = mv.isEp ? '${mv.toName[0]}$rank' : (mv.isCapture ? mv.toName : null);
        await Future.wait([
          m.movePiece(mv.fromName, mv.toName, capture: cap, promotion: mv.promotion),
          if (mv.isKingside) m.movePiece('h$rank', 'f$rank'),
          if (mv.isQueenside) m.movePiece('a$rank', 'd$rank'),
        ]);
        expect(m.snapshot().toSet(), chess.pieces().toSet(), reason: 'after $u');
      }
    });
  });

  group('animated moves', () {
    Future<double> run(BoardModel m, Future<void> f) async {
      var done = false;
      unawaited(f.then((_) => done = true));
      var t = 0.0;
      while (!done && t < 5) {
        m.tick(1 / 60);
        t += 1 / 60;
        await pumpEventQueue();
      }
      expect(done, isTrue, reason: 'animation never finished');
      return t;
    }

    test('a two-square pawn move takes about 420 ms and ends exactly on the square', () async {
      final m = start(animated: true);
      final t = await run(m, m.movePiece('e2', 'e4'));
      expect(t, closeTo(0.42, 0.03));
      final p = m.pieceOn('e4')!;
      expect(p.pos.x, closeTo(sqToWorld('e4').x, 1e-9));
      expect(p.pos.z, closeTo(sqToWorld('e4').z, 1e-9));
      expect(p.pos.y, closeTo(surfaceY, 1e-9));
    });

    test('long moves are capped at 700 ms', () async {
      final m = BoardModel()..animations = true;
      m.setPosition([pp('a1', Side.w, PT.r)]);
      final t = await run(m, m.movePiece('a1', 'a8'));
      expect(t, closeTo(0.70, 0.03));
    });

    test('pieces lift on the way: pawn arc 0.28, knight arc 0.9', () async {
      double peak(PT type) {
        final m = BoardModel()..animations = true;
        m.setPosition([pp('b1', Side.w, type)]);
        var done = false;
        m.movePiece('b1', 'c3').then((_) => done = true);
        var best = surfaceY;
        for (var i = 0; i < 300 && !done; i++) {
          m.tick(1 / 120);
          best = math.max(best, m.pieceObjects.first.pos.y);
        }
        return best - surfaceY;
      }

      expect(peak(PT.p), closeTo(0.28, 0.02));
      expect(peak(PT.n), closeTo(0.90, 0.02));
    });

    test('the piece does not occupy its target square until it arrives', () async {
      final m = start(animated: true);
      final f = m.movePiece('e2', 'e4');
      m.tick(0.1);
      expect(m.pieceOn('e4'), isNull);
      expect(m.pieceOn('e2'), isNull);
      await run(m, f);
      expect(m.pieceOn('e4'), isNotNull);
    });

    test('a captured piece shrinks and is removed when the move is complete', () async {
      final chess = Chess.fromUci(['e2e4', 'd7d5']);
      final m = BoardModel()..animations = true;
      m.setPosition(chess.pieces());
      final victimObj = m.pieceOn('d5')!;
      chess.move('e4', 'd5');
      final t = await run(m, m.movePiece('e4', 'd5', capture: 'd5'));
      expect(t, greaterThan(0.5)); // victim animation: delay 0.6 * dur + 320 ms
      expect(t, lessThan(0.7));
      expect(victimObj.scale, lessThan(0.01));
      expect(m.pieceCount, 31);
      expect(m.snapshot().toSet(), chess.pieces().toSet());
    });

    test('replacing the position while a move is animating is safe', () async {
      final m = start(animated: true);
      var done = false;
      m.movePiece('e2', 'e4').then((_) => done = true);
      m.tick(0.1);
      m.setPosition(Chess().pieces()); // e.g. undo / new game
      await pumpEventQueue();
      expect(done, isTrue); // the future resolves instead of hanging
      expect(m.snapshot().toSet(), Chess().pieces().toSet());
      expect(m.pieceOn('e2'), isNotNull);
      expect(m.pieceOn('e4'), isNull);
    });
  });

  group('selection lift', () {
    test('lift raises the piece by 0.22 and unlift puts it back', () {
      final m = start();
      m.lift('e2');
      expect(m.pieceOn('e2')!.pos.y, closeTo(surfaceY + 0.22, 1e-9));
      m.lift('d2'); // lifting another one drops the first
      expect(m.pieceOn('e2')!.pos.y, closeTo(surfaceY, 1e-9));
      expect(m.pieceOn('d2')!.pos.y, closeTo(surfaceY + 0.22, 1e-9));
      m.unlift();
      expect(m.pieceOn('d2')!.pos.y, closeTo(surfaceY, 1e-9));
    });
    test('lifting an empty square does nothing', () {
      final m = start();
      m.lift('e4');
      expect(m.snapshot().length, 32);
    });
    test('the lifted piece is still on its square for the snapshot', () {
      final m = start();
      m.lift('e2');
      expect(m.snapshot().toSet(), Chess().pieces().toSet());
    });
  });

  group('markers', () {
    test('heights and order match the web version', () {
      final m = start();
      m.setMarkers(MarkerSet(
        selected: 'e2',
        last: ('d2', 'd4'),
        check: 'e1',
        targets: const [TargetMarker('e3'), TargetMarker('e4'), TargetMarker('d5', capture: true)],
      ));
      final list = m.markerList();
      expect(list.length, 2 + 1 + 1 + 3);
      double y(int kind) => list.firstWhere((e) => e.kind == kind).pos.y - surfaceY;
      expect(y(MarkerKind.last), closeTo(0.004, 1e-9));
      expect(y(MarkerKind.check), closeTo(0.006, 1e-9));
      expect(y(MarkerKind.selected), closeTo(0.008, 1e-9));
      expect(y(MarkerKind.dot), closeTo(0.012, 1e-9));
      expect(y(MarkerKind.capture), closeTo(0.012, 1e-9));
      expect(list.where((e) => e.kind == MarkerKind.dot).length, 2);
      expect(list.where((e) => e.kind == MarkerKind.capture).length, 1);
      final sel = list.firstWhere((e) => e.kind == MarkerKind.selected).pos;
      expect(worldToSq(sel.x, sel.z), 'e2');
    });

    test('duplicate targets (promotion choices) are drawn once', () {
      final m = start();
      m.setMarkers(const MarkerSet(targets: [TargetMarker('a8'), TargetMarker('a8'), TargetMarker('a8'), TargetMarker('a8')]));
      expect(m.markerList().length, 1);
    });

    test('no markers by default', () {
      expect(start().markerList(), isEmpty);
    });

    test('the pools are big enough for the busiest position (queen with 27 moves)', () {
      expect(MarkerKind.pool[MarkerKind.dot], greaterThanOrEqualTo(27));
      expect(MarkerKind.pool[MarkerKind.capture], greaterThanOrEqualTo(16));
      final c = Chess('4k3/8/8/8/3Q4/8/8/4K3 w - - 0 1');
      expect(c.legalMoves(from: 'd4').length, lessThanOrEqualTo(MarkerKind.pool[MarkerKind.dot]));
    });
  });

  group('renderer frame buffer', () {
    test('header holds eye, target, fov and aspect', () {
      final m = BoardModel()..animations = false;
      m.setViewSize(400, 800);
      m.resetCamera(animate: false);
      final f = m.buildFrame();
      expect(f[0], closeTo(m.camera.eye.x, 1e-4));
      expect(f[1], closeTo(m.camera.eye.y, 1e-4));
      expect(f[2], closeTo(m.camera.eye.z, 1e-4));
      expect(f[3], closeTo(m.camera.target.x, 1e-6));
      expect(f[4], closeTo(m.camera.target.y, 1e-6));
      expect(f[6], 50);
      expect(f[7], closeTo(0.5, 1e-6));
    });

    test('length matches pieces and markers', () {
      final m = start();
      m.setMarkers(const MarkerSet(selected: 'e2', targets: [TargetMarker('e3'), TargetMarker('e4')]));
      final f = m.buildFrame();
      expect(f.length, BoardModel.headerSize + 32 * BoardModel.pieceStride + 1 + 3 * BoardModel.markerStride);
      final markerCountIndex = BoardModel.headerSize + 32 * BoardModel.pieceStride;
      expect(f[markerCountIndex], 3);
    });

    test('slot encoding round-trips', () {
      for (final t in PT.values) {
        for (final s in Side.values) {
          for (var i = 0; i < Slots.pool[t]!; i++) {
            final slot = Slots.make(t, s, i);
            expect(Slots.typeOf(slot), t);
            expect(Slots.sideOf(slot), s);
            expect(Slots.instanceOf(slot), i);
            expect(slot, lessThan(6 * 2 * 16));
          }
        }
      }
    });

    test('pool sizes cover the original set plus promotions', () {
      expect(Slots.pool[PT.k], 1);
      expect(Slots.pool[PT.q], 9);
      expect(Slots.pool[PT.r], 10);
      expect(Slots.pool[PT.b], 10);
      expect(Slots.pool[PT.n], 10);
      expect(Slots.pool[PT.p], 8);
    });

    test('a slot is freed when its piece is captured and can be reused', () async {
      final m = BoardModel()..animations = false;
      m.setPosition([pp('a2', Side.w, PT.p), pp('b3', Side.b, PT.p)]);
      final victimSlot = m.pieceOn('b3')!.slot;
      await m.movePiece('a2', 'b3', capture: 'b3');
      m.setPosition([pp('a2', Side.b, PT.p)]);
      expect(m.pieceOn('a2')!.slot, Slots.make(PT.p, Side.b, 0));
      expect(victimSlot, Slots.make(PT.p, Side.b, 0));
    });

    test('nine queens fit (promotion), the tenth is skipped instead of crashing', () {
      final m = BoardModel()..animations = false;
      final qs = [for (var i = 0; i < 10; i++) pp('${'abcdefgh'[i % 8]}${i < 8 ? 1 : 2}', Side.w, PT.q)];
      m.setPosition(qs);
      expect(m.pieceCount, 9);
    });
  });

  group('tick', () {
    test('returns false when nothing changes and true when something does', () {
      final m = start();
      m.tick(1 / 60); // consumes the initial dirty flag
      expect(m.tick(1 / 60), isFalse);
      m.lift('e2');
      expect(m.tick(1 / 60), isTrue);
      expect(m.tick(1 / 60), isFalse);
    });

    test('auto-rotate keeps the camera moving', () {
      final m = start();
      m.setAutoRotate(true);
      m.tick(1 / 60);
      var moved = 0;
      for (var i = 0; i < 30; i++) {
        if (m.tick(1 / 60)) moved++;
      }
      expect(moved, greaterThan(20));
      m.setAutoRotate(false);
    });

    test('viewSide follows the camera', () {
      final m = BoardModel()..animations = false;
      m.setViewSize(800, 600);
      m.resetCamera(animate: false);
      expect(m.viewSide(), Side.w);
      m.flipView();
      expect(m.viewSide(), Side.b);
    });
  });
}
