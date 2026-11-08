// Verifies the chess rules engine: move generation against the published perft node counts, every special move,
// game-end detection, SAN and undo.

import 'package:chess3d/chess/rules.dart';
import 'package:chess3d/chess/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('perft (move generation node counts)', () {
    // https://www.chessprogramming.org/Perft_Results
    const cases = <String, List<int>>{
      'start': [20, 400, 8902],
      'kiwipete': [48, 2039, 97862],
      'position3': [14, 191, 2812],
      'position4': [6, 264, 9467],
      'position5': [44, 1486, 62379],
      'position6': [46, 2079, 89890],
    };
    const fens = <String, String>{
      'start': Chess.startFen,
      'kiwipete': 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      'position3': '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
      'position4': 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
      'position5': 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
      'position6': 'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
    };
    for (final e in cases.entries) {
      for (var d = 1; d <= e.value.length; d++) {
        test('${e.key} depth $d = ${e.value[d - 1]}', () {
          expect(Chess(fens[e.key]).perft(d), e.value[d - 1]);
        });
      }
    }
    test('start position depth 4 = 197281', () {
      expect(Chess().perft(4), 197281);
    });
    test('perft leaves the position unchanged', () {
      final c = Chess(fens['kiwipete']);
      final before = c.fen();
      c.perft(2);
      expect(c.fen(), before);
    });
  });

  group('FEN', () {
    test('start position round trips', () {
      expect(Chess().fen(), Chess.startFen);
    });
    test('arbitrary positions round trip', () {
      for (final f in [
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - - 3 40',
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
      ]) {
        expect(Chess(f).fen(), f);
      }
    });
    test('en passant square only appears after a double push', () {
      final c = Chess();
      c.move('e2', 'e4');
      expect(c.epSquare, 'e3');
      c.move('a7', 'a6');
      expect(c.epSquare, isNull);
    });
  });

  group('basic moves', () {
    test('white moves first, 20 legal moves, turns alternate', () {
      final c = Chess();
      expect(c.turn, Side.w);
      expect(c.legalMoves().length, 20);
      c.move('e2', 'e4');
      expect(c.turn, Side.b);
      expect(c.legalMoves().length, 20);
    });
    test('illegal moves are refused and change nothing', () {
      final c = Chess();
      final fen = c.fen();
      expect(c.move('e2', 'e5'), isNull); // pawn cannot jump three
      expect(c.move('e7', 'e5'), isNull); // not Black's turn
      expect(c.move('a1', 'a3'), isNull); // rook blocked by own pawn
      expect(c.move('e4', 'e5'), isNull); // no piece there
      expect(c.move('z9', 'e5'), isNull); // not a square
      expect(c.fen(), fen);
    });
    test('knights jump', () {
      final c = Chess();
      expect(c.move('g1', 'f3'), isNotNull);
      expect(c.get('f3'), const Piece(Side.w, PT.n));
      expect(c.get('g1'), isNull);
    });
    test('legalMoves(from) filters by square', () {
      final c = Chess();
      expect(c.legalMoves(from: 'e2').map((m) => m.toName).toSet(), {'e3', 'e4'});
      expect(c.legalMoves(from: 'b1').map((m) => m.toName).toSet(), {'a3', 'c3'});
      expect(c.legalMoves(from: 'a1'), isEmpty);
    });
  });

  group('special moves', () {
    test('kingside castling moves king and rook', () {
      final c = Chess('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final m = c.move('e1', 'g1');
      expect(m, isNotNull);
      expect(m!.isKingside, isTrue);
      expect(m.san, 'O-O');
      expect(c.get('g1'), const Piece(Side.w, PT.k));
      expect(c.get('f1'), const Piece(Side.w, PT.r));
      expect(c.get('h1'), isNull);
      expect(c.get('e1'), isNull);
      expect(c.castlingRights, 'kq');
    });
    test('queenside castling for Black', () {
      final c = Chess('r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1');
      final m = c.move('e8', 'c8');
      expect(m!.isQueenside, isTrue);
      expect(m.san, 'O-O-O');
      expect(c.get('c8'), const Piece(Side.b, PT.k));
      expect(c.get('d8'), const Piece(Side.b, PT.r));
      expect(c.get('a8'), isNull);
    });
    test('cannot castle through check, out of check, or after the king moved', () {
      // f1 attacked by the rook on f8
      expect(Chess('5r1k/8/8/8/8/8/8/4K2R w K - 0 1').move('e1', 'g1'), isNull);
      // king in check
      expect(Chess('4r2k/8/8/8/8/8/8/4K2R w K - 0 1').move('e1', 'g1'), isNull);
      // right lost after moving the king and returning
      final c = Chess('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      c.move('e1', 'e2');
      c.move('a8', 'a7');
      c.move('e2', 'e1');
      c.move('a7', 'a8');
      expect(c.move('e1', 'g1'), isNull);
    });
    test('cannot castle with a piece in between', () {
      expect(Chess('r3k2r/8/8/8/8/8/8/R3KB1R w KQkq - 0 1').move('e1', 'g1'), isNull);
    });
    test('moving a rook removes only that side\'s castling right', () {
      final c = Chess('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      c.move('h1', 'h2');
      expect(c.castlingRights, 'Qkq');
    });
    test('capturing a rook on its home square removes the right', () {
      final c = Chess('r3k2r/8/8/8/8/8/6B1/R3K2R w KQkq - 0 1');
      c.move('g2', 'a8');
      expect(c.castlingRights, 'KQk');
    });
    test('en passant captures the pawn that passed', () {
      final c = Chess('rnbqkbnr/pppp1ppp/8/8/3Pp3/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 3');
      final m = c.move('e4', 'd3');
      expect(m, isNotNull);
      expect(m!.isEp, isTrue);
      expect(m.captured, PT.p);
      expect(c.get('d4'), isNull); // the captured pawn is gone
      expect(c.get('d3'), const Piece(Side.b, PT.p));
    });
    test('en passant is only possible immediately', () {
      final c = Chess();
      c.move('e2', 'e4');
      c.move('a7', 'a6');
      c.move('e4', 'e5');
      c.move('d7', 'd5');
      expect(c.legalMoves(from: 'e5').any((m) => m.isEp), isTrue);
      c.move('h2', 'h3');
      c.move('h7', 'h6');
      expect(c.legalMoves(from: 'e5').any((m) => m.isEp), isFalse);
    });
    test('promotion: four choices, default queen, pawn replaced', () {
      final c = Chess('8/P6k/8/8/8/8/7K/8 w - - 0 1');
      final promos = c.legalMoves(from: 'a7');
      expect(promos.length, 4);
      expect(promos.map((m) => m.promotion).toSet(), {PT.q, PT.r, PT.b, PT.n});
      final m = c.move('a7', 'a8');
      expect(m!.promotion, PT.q);
      expect(c.get('a8'), const Piece(Side.w, PT.q));
      expect(c.get('a7'), isNull);
    });
    test('under-promotion to a knight', () {
      final c = Chess('8/P6k/8/8/8/8/7K/8 w - - 0 1');
      expect(c.move('a7', 'a8', 'n'), isNotNull);
      expect(c.get('a8'), const Piece(Side.w, PT.n));
    });
    test('promotion by capture', () {
      final c = Chess('1n5k/P7/8/8/8/8/7K/8 w - - 0 1');
      final m = c.move('a7', 'b8', 'r');
      expect(m!.captured, PT.n);
      expect(m.promotion, PT.r);
      expect(c.get('b8'), const Piece(Side.w, PT.r));
    });
  });

  group('check, pins and game end', () {
    test('a pinned piece cannot leave the line', () {
      final c = Chess('4k3/4r3/8/8/8/8/4B3/4K3 w - - 0 1');
      expect(c.legalMoves(from: 'e2'), isEmpty);
    });
    test('must answer check', () {
      final c = Chess('4k3/8/8/8/8/8/4r3/R3K3 w - - 0 1');
      expect(c.isCheck, isTrue);
      final moves = c.legalMoves();
      // only king moves (or capturing the checker) are legal
      expect(moves.every((m) => m.piece == PT.k || m.toName == 'e2'), isTrue);
    });
    test('fool\'s mate is checkmate', () {
      final c = Chess();
      for (final mv in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        expect(c.moveUci(mv), isNotNull, reason: mv);
      }
      expect(c.isCheck, isTrue);
      expect(c.isCheckmate, isTrue);
      expect(c.isStalemate, isFalse);
      expect(c.history.last.san, 'Qh4#');
    });
    test('scholar\'s mate', () {
      final c = Chess.fromUci(['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5f7']);
      expect(c.isCheckmate, isTrue);
      expect(c.turn, Side.b);
    });
    test('stalemate', () {
      final c = Chess('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(c.isCheck, isFalse);
      expect(c.isStalemate, isTrue);
      expect(c.isCheckmate, isFalse);
    });
    test('insufficient material', () {
      expect(Chess('8/8/8/4k3/8/8/3K4/8 w - - 0 1').isInsufficientMaterial, isTrue);
      expect(Chess('8/8/8/4k3/8/8/3KB3/8 w - - 0 1').isInsufficientMaterial, isTrue);
      expect(Chess('8/8/8/4k3/8/8/3KN3/8 w - - 0 1').isInsufficientMaterial, isTrue);
      expect(Chess('8/8/8/4k3/8/8/3KP3/8 w - - 0 1').isInsufficientMaterial, isFalse);
      expect(Chess('8/8/8/4k3/8/8/3KR3/8 w - - 0 1').isInsufficientMaterial, isFalse);
      expect(Chess('8/8/8/4k3/8/8/3KNN2/8 w - - 0 1').isInsufficientMaterial, isFalse);
      expect(Chess().isInsufficientMaterial, isFalse);
    });
    test('threefold repetition', () {
      final c = Chess();
      expect(c.isThreefoldRepetition, isFalse);
      for (var i = 0; i < 2; i++) {
        c.move('g1', 'f3');
        c.move('g8', 'f6');
        c.move('f3', 'g1');
        c.move('f6', 'g8');
      }
      expect(c.isThreefoldRepetition, isTrue);
    });
    test('fifty-move rule counts half moves', () {
      expect(Chess('8/8/8/4k3/8/8/3K4/R7 w - - 99 80').isDrawByFiftyMoves, isFalse);
      expect(Chess('8/8/8/4k3/8/8/3K4/R7 w - - 100 80').isDrawByFiftyMoves, isTrue);
    });
    test('a pawn move or capture resets the half move clock', () {
      final c = Chess();
      c.move('g1', 'f3');
      expect(c.halfmoveClock, 1);
      c.move('e7', 'e5');
      expect(c.halfmoveClock, 0);
    });
  });

  group('SAN', () {
    test('disambiguation by file and rank', () {
      final c = Chess('4k3/8/8/8/8/8/4K3/R6R w - - 0 1');
      expect(c.move('a1', 'd1')!.san, 'Rad1');
      final d = Chess('8/R7/8/7k/8/8/8/R3K3 w - - 0 1');
      expect(d.move('a1', 'a4')!.san, 'R1a4');
    });
    test('captures, checks and promotion', () {
      final c = Chess('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      expect(c.move('a7', 'a8', 'q')!.san, 'a8=Q+');
      final d = Chess.fromUci(['e2e4', 'd7d5']);
      expect(d.move('e4', 'd5')!.san, 'exd5');
    });
    test('game from the start has correct SAN list', () {
      final c = Chess.fromUci(['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5']);
      expect(c.history.map((m) => m.san).toList(), ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']);
    });
  });

  group('undo', () {
    test('restores the exact position, including castling, ep and captured pieces', () {
      final fens = <String>[];
      final c = Chess();
      final line = ['e2e4', 'd7d5', 'e4d5', 'g8f6', 'f1b5', 'c7c6', 'd5c6', 'b8c6', 'g1f3', 'c8g4', 'e1g1'];
      for (final u in line) {
        fens.add(c.fen());
        expect(c.moveUci(u), isNotNull, reason: u);
      }
      for (var i = line.length - 1; i >= 0; i--) {
        expect(c.undo(), isNotNull);
        expect(c.fen(), fens[i], reason: 'after undoing ${line[i]}');
      }
      expect(c.undo(), isNull);
      expect(c.fen(), Chess.startFen);
    });
    test('undo of promotion and en passant', () {
      final c = Chess('rnbqkbnr/pppp1ppp/8/8/3Pp3/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 3');
      final before = c.fen();
      c.move('e4', 'd3');
      c.undo();
      expect(c.fen(), before);
      final p = Chess('1n5k/P7/8/8/8/8/7K/8 w - - 0 1');
      final pf = p.fen();
      p.move('a7', 'b8', 'q');
      p.undo();
      expect(p.fen(), pf);
    });
  });

  group('pieces()', () {
    test('lists every piece with its square', () {
      final ps = Chess().pieces();
      expect(ps.length, 32);
      expect(ps.where((p) => p.side == Side.w).length, 16);
      expect(ps.where((p) => p.side == Side.b).length, 16);
    });
    test('kingSquare', () {
      final c = Chess();
      expect(c.kingSquare(Side.w), 'e1');
      expect(c.kingSquare(Side.b), 'e8');
    });
  });
}
