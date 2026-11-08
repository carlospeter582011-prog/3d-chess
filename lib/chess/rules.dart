// A complete, dependency-free chess rules engine.
//
// Replaces chess.js from the web version. Supports: all piece moves, castling, en passant, promotion, check,
// checkmate, stalemate, threefold repetition, fifty-move rule, insufficient material, FEN, SAN and undo.
// It is verified by perft tests (move-generation node counts) in test/rules_test.dart.

import 'types.dart';

const int _castleWK = 1;
const int _castleWQ = 2;
const int _castleBK = 4;
const int _castleBQ = 8;

class Move {
  final int from;
  final int to;
  final PT piece;
  final Side side;
  final PT? captured;
  final PT? promotion;
  final bool isEp;
  final bool isKingside;
  final bool isQueenside;
  final bool isDoublePush;

  /// Standard algebraic notation, filled in for moves played through [Chess.move].
  String san = '';

  Move(
    this.from,
    this.to,
    this.piece,
    this.side, {
    this.captured,
    this.promotion,
    this.isEp = false,
    this.isKingside = false,
    this.isQueenside = false,
    this.isDoublePush = false,
  });

  bool get isCapture => captured != null;
  bool get isPromotion => promotion != null;
  bool get isCastle => isKingside || isQueenside;
  String get fromName => sqName(from);
  String get toName => sqName(to);

  /// Long algebraic / UCI form, e.g. "e2e4" or "e7e8q".
  String get uci => '$fromName$toName${promotion?.ch ?? ''}';

  @override
  String toString() => san.isEmpty ? uci : san;
}

class _Undo {
  final Move move;
  final int movedCode;
  final int capturedCode;
  final int captureSquare;
  final int castling;
  final int ep;
  final int halfmove;
  final int fullmove;
  const _Undo(this.move, this.movedCode, this.capturedCode, this.captureSquare, this.castling, this.ep,
      this.halfmove, this.fullmove);
}

class Chess {
  static const String startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  // Board: 64 ints, 0 = empty, otherwise (black ? 8 : 0) | (PT.index + 1).
  final List<int> _board = List<int>.filled(64, 0);
  final List<int> _kingSq = [-1, -1];
  Side _turn = Side.w;
  int _castling = 0;
  int _ep = -1;
  int _halfmove = 0;
  int _fullmove = 1;

  final List<_Undo> _stack = [];
  final List<Move> _moves = [];
  final List<String> _keys = [];

  Chess([String? fen]) {
    load(fen ?? startFen);
  }

  /// Builds a game by playing UCI moves ("e2e4", "e7e8q") from the start position.
  /// Throws a [FormatException] on an illegal move.
  factory Chess.fromUci(List<String> ucis, [String? fen]) {
    final c = Chess(fen);
    for (final u in ucis) {
      if (c.moveUci(u) == null) throw FormatException('illegal move $u');
    }
    return c;
  }

  // ------------------------------------------------------------------ helpers
  static int _code(Side s, PT t) => (s == Side.b ? 8 : 0) | (t.index + 1);
  static Side _codeSide(int c) => c & 8 != 0 ? Side.b : Side.w;
  static PT _codeType(int c) => PT.values[(c & 7) - 1];

  static final List<int> _mask = () {
    final m = List<int>.filled(64, 15);
    m[0] = 15 & ~_castleWQ;
    m[4] = 15 & ~(_castleWK | _castleWQ);
    m[7] = 15 & ~_castleWK;
    m[56] = 15 & ~_castleBQ;
    m[60] = 15 & ~(_castleBK | _castleBQ);
    m[63] = 15 & ~_castleBK;
    return m;
  }();

  // ------------------------------------------------------------------ state
  Side get turn => _turn;
  int get halfmoveClock => _halfmove;
  int get fullmoveNumber => _fullmove;
  String get castlingRights {
    final b = StringBuffer();
    if (_castling & _castleWK != 0) b.write('K');
    if (_castling & _castleWQ != 0) b.write('Q');
    if (_castling & _castleBK != 0) b.write('k');
    if (_castling & _castleBQ != 0) b.write('q');
    return b.isEmpty ? '-' : b.toString();
  }

  /// Square behind a pawn that just made a double push, or null.
  String? get epSquare => _ep < 0 ? null : sqName(_ep);

  /// Moves played through [move] / [moveUci], oldest first.
  List<Move> get history => List.unmodifiable(_moves);

  List<String> get uciHistory => _moves.map((m) => m.uci).toList();

  Piece? pieceAt(int sq) {
    final c = _board[sq];
    return c == 0 ? null : Piece(_codeSide(c), _codeType(c));
  }

  /// Piece on a square given by name ("e4"), or null.
  Piece? get(String square) => pieceAt(sqIndex(square));

  /// Every piece on the board.
  List<PlacedPiece> pieces() {
    final out = <PlacedPiece>[];
    for (var r = 7; r >= 0; r--) {
      for (var f = 0; f < 8; f++) {
        final c = _board[r * 8 + f];
        if (c != 0) out.add(PlacedPiece(sqName(r * 8 + f), _codeSide(c), _codeType(c)));
      }
    }
    return out;
  }

  String? kingSquare(Side s) => _kingSq[s.index] < 0 ? null : sqName(_kingSq[s.index]);

  // ------------------------------------------------------------------ FEN
  void load(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) throw FormatException('bad FEN: $fen');
    final rows = parts[0].split('/');
    if (rows.length != 8) throw FormatException('bad FEN rows: $fen');
    _board.fillRange(0, 64, 0);
    _kingSq[0] = -1;
    _kingSq[1] = -1;
    for (var i = 0; i < 8; i++) {
      final rank = 7 - i;
      var file = 0;
      for (final ch in rows[i].split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          file += n;
        } else {
          final t = ptFromChar(ch);
          if (t == null || file > 7) throw FormatException('bad FEN piece "$ch": $fen');
          final side = ch == ch.toUpperCase() ? Side.w : Side.b;
          _board[rank * 8 + file] = _code(side, t);
          if (t == PT.k) _kingSq[side.index] = rank * 8 + file;
          file++;
        }
      }
      if (file != 8) throw FormatException('bad FEN row length: $fen');
    }
    if (_kingSq[0] < 0 || _kingSq[1] < 0) throw FormatException('FEN needs both kings: $fen');
    _turn = parts[1] == 'b' ? Side.b : Side.w;
    final c = parts.length > 2 ? parts[2] : '-';
    _castling = 0;
    if (c.contains('K')) _castling |= _castleWK;
    if (c.contains('Q')) _castling |= _castleWQ;
    if (c.contains('k')) _castling |= _castleBK;
    if (c.contains('q')) _castling |= _castleBQ;
    _ep = parts.length > 3 && parts[3] != '-' && isValidSquare(parts[3]) ? sqIndex(parts[3]) : -1;
    _halfmove = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
    _fullmove = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
    _stack.clear();
    _moves.clear();
    _keys
      ..clear()
      ..add(_positionKey());
  }

  String fen() {
    final rows = <String>[];
    for (var r = 7; r >= 0; r--) {
      final b = StringBuffer();
      var empty = 0;
      for (var f = 0; f < 8; f++) {
        final c = _board[r * 8 + f];
        if (c == 0) {
          empty++;
        } else {
          if (empty > 0) {
            b.write(empty);
            empty = 0;
          }
          b.write(Piece(_codeSide(c), _codeType(c)).fen);
        }
      }
      if (empty > 0) b.write(empty);
      rows.add(b.toString());
    }
    return '${rows.join('/')} ${_turn.ch} $castlingRights ${_ep < 0 ? '-' : sqName(_ep)} $_halfmove $_fullmove';
  }

  // ------------------------------------------------------------------ attacks
  static const List<List<int>> _knightD = [
    [1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]
  ];
  static const List<List<int>> _kingD = [
    [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]
  ];
  static const List<List<int>> _diagD = [
    [1, 1], [1, -1], [-1, 1], [-1, -1]
  ];
  static const List<List<int>> _lineD = [
    [1, 0], [-1, 0], [0, 1], [0, -1]
  ];

  /// Is [sq] attacked by any piece of side [by]?
  bool _attacked(int sq, Side by) {
    final f = sq & 7, r = sq >> 3;
    // pawns
    final pr = by == Side.w ? r - 1 : r + 1;
    if (pr >= 0 && pr < 8) {
      final pawn = _code(by, PT.p);
      if (f > 0 && _board[pr * 8 + f - 1] == pawn) return true;
      if (f < 7 && _board[pr * 8 + f + 1] == pawn) return true;
    }
    // knights
    final knight = _code(by, PT.n);
    for (final d in _knightD) {
      final nf = f + d[0], nr = r + d[1];
      if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8 && _board[nr * 8 + nf] == knight) return true;
    }
    // king
    final king = _code(by, PT.k);
    for (final d in _kingD) {
      final nf = f + d[0], nr = r + d[1];
      if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8 && _board[nr * 8 + nf] == king) return true;
    }
    // sliders
    final bishop = _code(by, PT.b), rook = _code(by, PT.r), queen = _code(by, PT.q);
    for (final d in _diagD) {
      var nf = f + d[0], nr = r + d[1];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final c = _board[nr * 8 + nf];
        if (c != 0) {
          if (c == bishop || c == queen) return true;
          break;
        }
        nf += d[0];
        nr += d[1];
      }
    }
    for (final d in _lineD) {
      var nf = f + d[0], nr = r + d[1];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final c = _board[nr * 8 + nf];
        if (c != 0) {
          if (c == rook || c == queen) return true;
          break;
        }
        nf += d[0];
        nr += d[1];
      }
    }
    return false;
  }

  bool _inCheck(Side s) => _kingSq[s.index] >= 0 && _attacked(_kingSq[s.index], s.other);

  bool get isCheck => _inCheck(_turn);

  // ------------------------------------------------------------------ move generation
  void _addPawnMove(List<Move> out, int from, int to, Side side, PT? captured, bool promo, {bool ep = false}) {
    if (promo) {
      for (final p in const [PT.q, PT.r, PT.b, PT.n]) {
        out.add(Move(from, to, PT.p, side, captured: captured, promotion: p));
      }
    } else {
      out.add(Move(from, to, PT.p, side, captured: captured, isEp: ep));
    }
  }

  List<Move> _pseudo({int? only}) {
    final out = <Move>[];
    final side = _turn;
    final enemy = side.other;
    final start = only ?? 0;
    final end = only == null ? 64 : only + 1;
    for (var sq = start; sq < end; sq++) {
      final c = _board[sq];
      if (c == 0 || _codeSide(c) != side) continue;
      final type = _codeType(c);
      final f = sq & 7, r = sq >> 3;
      switch (type) {
        case PT.p:
          final dir = side == Side.w ? 1 : -1;
          final startRank = side == Side.w ? 1 : 6;
          final promoRank = side == Side.w ? 7 : 0;
          final r1 = r + dir;
          if (r1 < 0 || r1 > 7) break;
          final t = r1 * 8 + f;
          if (_board[t] == 0) {
            _addPawnMove(out, sq, t, side, null, r1 == promoRank);
            if (r == startRank) {
              final t2 = (r + 2 * dir) * 8 + f;
              if (_board[t2] == 0) out.add(Move(sq, t2, PT.p, side, isDoublePush: true));
            }
          }
          for (final df in const [-1, 1]) {
            final nf = f + df;
            if (nf < 0 || nf > 7) continue;
            final tt = r1 * 8 + nf;
            final tc = _board[tt];
            if (tc != 0 && _codeSide(tc) == enemy) {
              _addPawnMove(out, sq, tt, side, _codeType(tc), r1 == promoRank);
            } else if (tc == 0 && tt == _ep) {
              _addPawnMove(out, sq, tt, side, PT.p, false, ep: true);
            }
          }
          break;
        case PT.n:
          for (final d in _knightD) {
            final nf = f + d[0], nr = r + d[1];
            if (nf < 0 || nf > 7 || nr < 0 || nr > 7) continue;
            final tt = nr * 8 + nf;
            final tc = _board[tt];
            if (tc == 0) {
              out.add(Move(sq, tt, PT.n, side));
            } else if (_codeSide(tc) == enemy) {
              out.add(Move(sq, tt, PT.n, side, captured: _codeType(tc)));
            }
          }
          break;
        case PT.b:
          _slide(out, sq, PT.b, side, _diagD);
          break;
        case PT.r:
          _slide(out, sq, PT.r, side, _lineD);
          break;
        case PT.q:
          _slide(out, sq, PT.q, side, _diagD);
          _slide(out, sq, PT.q, side, _lineD);
          break;
        case PT.k:
          for (final d in _kingD) {
            final nf = f + d[0], nr = r + d[1];
            if (nf < 0 || nf > 7 || nr < 0 || nr > 7) continue;
            final tt = nr * 8 + nf;
            final tc = _board[tt];
            if (tc == 0) {
              out.add(Move(sq, tt, PT.k, side));
            } else if (_codeSide(tc) == enemy) {
              out.add(Move(sq, tt, PT.k, side, captured: _codeType(tc)));
            }
          }
          _castleMoves(out, sq, side);
          break;
      }
    }
    return out;
  }

  void _slide(List<Move> out, int sq, PT type, Side side, List<List<int>> dirs) {
    final f = sq & 7, r = sq >> 3;
    for (final d in dirs) {
      var nf = f + d[0], nr = r + d[1];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final tt = nr * 8 + nf;
        final tc = _board[tt];
        if (tc == 0) {
          out.add(Move(sq, tt, type, side));
        } else {
          if (_codeSide(tc) != side) out.add(Move(sq, tt, type, side, captured: _codeType(tc)));
          break;
        }
        nf += d[0];
        nr += d[1];
      }
    }
  }

  void _castleMoves(List<Move> out, int sq, Side side) {
    final home = side == Side.w ? 4 : 60;
    if (sq != home) return;
    final enemy = side.other;
    final rook = _code(side, PT.r);
    final kRight = side == Side.w ? _castleWK : _castleBK;
    final qRight = side == Side.w ? _castleWQ : _castleBQ;
    if (_castling & (kRight | qRight) == 0) return;
    if (_attacked(home, enemy)) return;
    if (_castling & kRight != 0 &&
        _board[home + 1] == 0 &&
        _board[home + 2] == 0 &&
        _board[home + 3] == rook &&
        !_attacked(home + 1, enemy) &&
        !_attacked(home + 2, enemy)) {
      out.add(Move(home, home + 2, PT.k, side, isKingside: true));
    }
    if (_castling & qRight != 0 &&
        _board[home - 1] == 0 &&
        _board[home - 2] == 0 &&
        _board[home - 3] == 0 &&
        _board[home - 4] == rook &&
        !_attacked(home - 1, enemy) &&
        !_attacked(home - 2, enemy)) {
      out.add(Move(home, home - 2, PT.k, side, isQueenside: true));
    }
  }

  /// All legal moves for the side to move, optionally only from one square.
  List<Move> legalMoves({String? from}) {
    final side = _turn;
    final out = <Move>[];
    for (final m in _pseudo(only: from == null ? null : sqIndex(from))) {
      _make(m);
      if (!_attacked(_kingSq[side.index], side.other)) out.add(m);
      _unmake();
    }
    return out;
  }

  // ------------------------------------------------------------------ make / unmake
  void _make(Move m) {
    final side = m.side;
    final code = _board[m.from];
    final capSq = m.isEp ? m.to + (side == Side.w ? -8 : 8) : m.to;
    final capCode = _board[capSq];
    _stack.add(_Undo(m, code, capCode, capSq, _castling, _ep, _halfmove, _fullmove));
    _board[capSq] = 0;
    _board[m.from] = 0;
    _board[m.to] = m.promotion != null ? _code(side, m.promotion!) : code;
    if (m.isKingside) {
      final rk = side == Side.w ? 0 : 56;
      _board[rk + 5] = _board[rk + 7];
      _board[rk + 7] = 0;
    } else if (m.isQueenside) {
      final rk = side == Side.w ? 0 : 56;
      _board[rk + 3] = _board[rk];
      _board[rk] = 0;
    }
    if (m.piece == PT.k) _kingSq[side.index] = m.to;
    _castling &= _mask[m.from] & _mask[m.to];
    _ep = m.isDoublePush ? (m.from + m.to) ~/ 2 : -1;
    if (m.piece == PT.p || capCode != 0) {
      _halfmove = 0;
    } else {
      _halfmove++;
    }
    if (side == Side.b) _fullmove++;
    _turn = side.other;
  }

  void _unmake() {
    final u = _stack.removeLast();
    final m = u.move;
    final side = m.side;
    _turn = side;
    _castling = u.castling;
    _ep = u.ep;
    _halfmove = u.halfmove;
    _fullmove = u.fullmove;
    _board[m.to] = 0;
    _board[m.from] = u.movedCode;
    _board[u.captureSquare] = u.capturedCode;
    if (m.isKingside) {
      final rk = side == Side.w ? 0 : 56;
      _board[rk + 7] = _board[rk + 5];
      _board[rk + 5] = 0;
    } else if (m.isQueenside) {
      final rk = side == Side.w ? 0 : 56;
      _board[rk] = _board[rk + 3];
      _board[rk + 3] = 0;
    }
    if (m.piece == PT.k) _kingSq[side.index] = m.from;
  }

  /// Counts the leaf nodes of the legal move tree - used to verify the move generator.
  int perft(int depth) {
    if (depth == 0) return 1;
    final moves = legalMoves();
    if (depth == 1) return moves.length;
    var n = 0;
    for (final m in moves) {
      _make(m);
      n += perft(depth - 1);
      _unmake();
    }
    return n;
  }

  // ------------------------------------------------------------------ playing
  /// Plays a legal move and returns it (with its SAN), or null when the move is illegal.
  /// For a promotion without [promotion] a queen is chosen.
  Move? move(String from, String to, [String? promotion]) {
    if (!isValidSquare(from) || !isValidSquare(to)) return null;
    final f = sqIndex(from), t = sqIndex(to);
    final all = legalMoves();
    Move? mv;
    for (final m in all) {
      if (m.from != f || m.to != t) continue;
      if (m.isPromotion) {
        final want = (promotion == null || promotion.isEmpty) ? 'q' : promotion.toLowerCase();
        if (m.promotion!.ch != want) continue;
      }
      mv = m;
      break;
    }
    if (mv == null) return null;
    final base = _sanBase(mv, all);
    _make(mv);
    _moves.add(mv);
    var suffix = '';
    if (_inCheck(_turn)) suffix = legalMoves().isEmpty ? '#' : '+';
    mv.san = base + suffix;
    _keys.add(_positionKey());
    return mv;
  }

  /// Plays a move given in UCI form ("e2e4", "e7e8q").
  Move? moveUci(String uci) {
    if (uci.length < 4) return null;
    return move(uci.substring(0, 2), uci.substring(2, 4), uci.length > 4 ? uci.substring(4, 5) : null);
  }

  /// Takes back the last move played through [move]; returns it, or null when there is none.
  Move? undo() {
    if (_moves.isEmpty) return null;
    _unmake();
    _keys.removeLast();
    return _moves.removeLast();
  }

  String _sanBase(Move m, List<Move> legal) {
    if (m.isKingside) return 'O-O';
    if (m.isQueenside) return 'O-O-O';
    final b = StringBuffer();
    final fromFile = 'abcdefgh'[m.from & 7];
    if (m.piece == PT.p) {
      if (m.isCapture) b.write('${fromFile}x');
    } else {
      b.write(m.piece.ch.toUpperCase());
      final others = legal.where((o) => o.piece == m.piece && o.to == m.to && o.from != m.from).toList();
      if (others.isNotEmpty) {
        final sameFile = others.any((o) => (o.from & 7) == (m.from & 7));
        final sameRank = others.any((o) => (o.from >> 3) == (m.from >> 3));
        if (!sameFile) {
          b.write(fromFile);
        } else if (!sameRank) {
          b.write((m.from >> 3) + 1);
        } else {
          b.write('$fromFile${(m.from >> 3) + 1}');
        }
      }
      if (m.isCapture) b.write('x');
    }
    b.write(m.toName);
    if (m.isPromotion) b.write('=${m.promotion!.ch.toUpperCase()}');
    return b.toString();
  }

  // ------------------------------------------------------------------ status
  bool get isCheckmate => isCheck && legalMoves().isEmpty;
  bool get isStalemate => !isCheck && legalMoves().isEmpty;
  bool get isDrawByFiftyMoves => _halfmove >= 100;

  bool get isInsufficientMaterial {
    final minors = <int>[]; // square indices of bishops/knights
    var bishopsOnly = true;
    for (var sq = 0; sq < 64; sq++) {
      final c = _board[sq];
      if (c == 0) continue;
      final t = _codeType(c);
      if (t == PT.k) continue;
      if (t == PT.p || t == PT.r || t == PT.q) return false;
      minors.add(sq);
      if (t != PT.b) bishopsOnly = false;
    }
    if (minors.length <= 1) return true; // K v K, K+B v K, K+N v K
    if (!bishopsOnly) return false;
    // only bishops left: a draw when they all stand on the same colour of square
    final color = ((minors.first >> 3) + (minors.first & 7)) & 1;
    return minors.every((s) => (((s >> 3) + (s & 7)) & 1) == color);
  }

  /// Same position (placement, side to move, castling, legal en passant) seen at least three times.
  bool get isThreefoldRepetition {
    final key = _keys.last;
    var n = 0;
    for (final k in _keys) {
      if (k == key) n++;
    }
    return n >= 3;
  }

  String _positionKey() {
    final b = StringBuffer();
    for (final c in _board) {
      b.writeCharCode(c + 65);
    }
    b.write(_turn.ch);
    b.write(_castling);
    if (_ep >= 0 && legalMoves().any((m) => m.isEp)) b.write(_ep);
    return b.toString();
  }
}
