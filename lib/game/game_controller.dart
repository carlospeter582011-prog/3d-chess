// Game controller: a port of Game.ts. Owns the rules engine, drives the 3D board and the bot, and publishes an
// immutable [GameSnapshot] to the UI through [ChangeNotifier].

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../chess/rules.dart';
import '../chess/types.dart';
import '../chess/uci_engine.dart';
import '../scene/board_scene.dart';
import 'settings.dart';
import 'storage.dart';

const String saveKey = 'chess3d-save-v1';
const String settingsKey = 'chess3d-settings-v1';

class Promotion {
  final String from, to;
  const Promotion(this.from, this.to);
}

class GameSnapshot {
  final int version;
  final bool active;
  final GameConfig config;
  final String fen;
  final Side turn;
  final List<String> history; // SAN
  final GameStatus status;
  final String reason;
  final Side? winner;
  final bool check;
  final bool thinking;
  final bool busy;
  final String? selected;
  final Promotion? promotion;

  /// Pieces each side has lost.
  final Map<Side, List<PT>> captured;
  final bool canUndo;
  final bool engineError;

  const GameSnapshot({
    required this.version,
    required this.active,
    required this.config,
    required this.fen,
    required this.turn,
    required this.history,
    required this.status,
    required this.reason,
    required this.winner,
    required this.check,
    required this.thinking,
    required this.busy,
    required this.selected,
    required this.promotion,
    required this.captured,
    required this.canUndo,
    required this.engineError,
  });
}

class SavedGame {
  final GameConfig config;
  final List<String> moves; // UCI
  const SavedGame(this.config, this.moves);
}

class GameController extends ChangeNotifier {
  GameController({
    required this.board,
    required this.engine,
    required this.store,
    required this.sfx,
    math.Random? random,
    this.thinkMinimum = const Duration(milliseconds: 450),
  }) : _random = random ?? math.Random() {
    _refresh();
  }

  final BoardScene board;
  final BotEngine engine;
  final KeyValueStore store;
  final Sfx sfx;
  final math.Random _random;

  /// A bot move is never played faster than this, so it does not feel instant.
  final Duration thinkMinimum;

  Chess chess = Chess();
  GameConfig config = const GameConfig();
  late GameSnapshot _snap;
  int _version = 0;
  bool _active = false;
  String? _selected;
  Promotion? _promotion;
  bool _thinking = false;
  bool _busy = false;
  int _epoch = 0;
  Side? _resigned; // side that resigned
  bool _agreedDraw = false;
  bool _engineError = false;
  bool autoFlip = false;
  bool _disposed = false;

  GameSnapshot get snapshot => _snap;
  bool get isBusy => _busy;

  // ------------------------------------------------------------------ snapshot plumbing
  void _refresh() {
    if (_disposed) return;
    final hist = chess.history;
    final captured = <Side, List<PT>>{Side.w: [], Side.b: []};
    for (final m in hist) {
      final c = m.captured;
      if (c != null) captured[m.side.other]!.add(c);
    }
    final st = computeStatus();
    _snap = GameSnapshot(
      version: ++_version,
      active: _active,
      config: config,
      fen: chess.fen(),
      turn: chess.turn,
      history: [for (final m in hist) m.san],
      status: st.status,
      reason: st.reason,
      winner: st.winner,
      check: chess.isCheck,
      thinking: _thinking,
      busy: _busy,
      selected: _selected,
      promotion: _promotion,
      captured: captured,
      canUndo: hist.isNotEmpty && !_busy && st.status != GameStatus.resigned,
      engineError: _engineError,
    );
    notifyListeners();
  }

  ({GameStatus status, String reason, Side? winner}) computeStatus() {
    final c = chess;
    final r = _resigned;
    if (r != null) return (status: GameStatus.resigned, reason: '${r.label} resigned', winner: r.other);
    if (_agreedDraw) return (status: GameStatus.draw, reason: 'Draw agreed', winner: null);
    if (c.isCheckmate) return (status: GameStatus.checkmate, reason: 'Checkmate', winner: c.turn.other);
    if (c.isStalemate) return (status: GameStatus.stalemate, reason: 'Stalemate', winner: null);
    if (c.isInsufficientMaterial) return (status: GameStatus.draw, reason: 'Insufficient material', winner: null);
    if (c.isThreefoldRepetition) return (status: GameStatus.draw, reason: 'Threefold repetition', winner: null);
    if (c.isDrawByFiftyMoves) return (status: GameStatus.draw, reason: 'Fifty-move rule', winner: null);
    return (status: GameStatus.playing, reason: '', winner: null);
  }

  // ------------------------------------------------------------------ settings
  void applySettings(Settings s) {
    autoFlip = s.autoFlip;
    sfx.setMuted(!s.sound);
    board.setLabelsVisible(s.labels);
  }

  // ------------------------------------------------------------------ lifecycle
  List<PlacedPiece> placed() => chess.pieces();

  void syncBoard() {
    board.setPosition(placed());
    _updateMarkers();
  }

  /// Starts a new game, optionally resuming from a list of UCI moves.
  void start(GameConfig cfg, {List<String> moves = const []}) {
    _cancelThinking();
    config = cfg;
    chess = Chess();
    if (moves.isNotEmpty) {
      try {
        chess = Chess.fromUci(moves);
      } on FormatException {
        chess = Chess();
      }
    }
    _resigned = null;
    _agreedDraw = false;
    _selected = null;
    _promotion = null;
    _busy = false;
    _engineError = false;
    _active = true;
    engine.resetGame();
    syncBoard();
    final side = cfg.mode == GameMode.bot ? cfg.humanColor : chess.turn;
    board.setAutoRotate(false);
    board.resetCamera(animate: true, side: side);
    _refresh();
    _save();
    unawaited(_maybeBotMove());
  }

  /// Back to the menu without losing the game.
  void leave() {
    _cancelThinking();
    _active = false;
    _refresh();
  }

  void resume() {
    _active = true;
    _refresh();
    unawaited(_maybeBotMove());
  }

  // ------------------------------------------------------------------ persistence
  void _save() {
    try {
      if (chess.history.isEmpty && !_active) return;
      if (computeStatus().status != GameStatus.playing) {
        store.remove(saveKey);
        return;
      }
      store.set(saveKey, jsonEncode({'config': config.toJson(), 'moves': chess.uciHistory}));
    } catch (e) {
      debugPrint('save failed: $e');
    }
  }

  static SavedGame? loadSaved(KeyValueStore store) {
    try {
      final text = store.get(saveKey);
      if (text == null) return null;
      final j = jsonDecode(text);
      if (j is! Map) return null;
      final cfg = GameConfig.fromJson(j['config']);
      final moves = j['moves'];
      if (cfg == null || moves is! List) return null;
      final list = moves.whereType<String>().toList();
      // validate: a corrupted save must never crash the app
      Chess.fromUci(list);
      return SavedGame(cfg, list);
    } catch (_) {
      return null;
    }
  }

  static void clearSaved(KeyValueStore store) => store.remove(saveKey);

  void _cancelThinking() {
    _epoch++;
    if (_thinking) engine.stop();
    _thinking = false;
  }

  // ------------------------------------------------------------------ input
  bool _isHumanTurn() => config.mode == GameMode.local || chess.turn == config.humanColor;

  List<Move> legalFrom(String sq) => chess.legalMoves(from: sq);

  /// A tap on the board. [sq] is the piece or square under the finger, [ground] the floor square under it.
  void tap(String sq, [String? ground]) {
    if (!_active || _busy || _promotion != null) return;
    if (computeStatus().status != GameStatus.playing || !_isHumanTurn()) return;
    // A tall piece can hide the square behind it. If a piece is selected and the tap landed on a piece that
    // is not a legal destination (e.g. the selected piece itself) while the floor under the finger IS one, move there.
    final sel = _selected;
    if (sel != null && ground != null && ground != sq) {
      final legal = legalFrom(sel);
      final hit = chess.get(sq);
      final ownOther = hit != null && hit.side == chess.turn && sq != sel;
      if (!legal.any((m) => m.toName == sq) && legal.any((m) => m.toName == ground) && !ownOther) sq = ground;
    }
    final piece = chess.get(sq);
    if (sel != null) {
      Move? mv;
      for (final m in legalFrom(sel)) {
        if (m.toName == sq) {
          mv = m;
          break;
        }
      }
      if (mv != null) {
        if (mv.isPromotion) {
          _promotion = Promotion(sel, sq);
          _refresh();
          return;
        }
        unawaited(playMove(sel, sq));
        return;
      }
      if (piece != null && piece.side == chess.turn && sq != sel) {
        _select(sq);
        return;
      }
      _deselect();
      return;
    }
    if (piece != null && piece.side == chess.turn) _select(sq);
  }

  void _select(String sq) {
    _selected = sq;
    board.lift(sq);
    _updateMarkers();
    _refresh();
  }

  void _deselect() {
    _selected = null;
    board.unlift();
    _updateMarkers();
    _refresh();
  }

  void choosePromotion(PT p) {
    final pr = _promotion;
    if (pr == null) return;
    if (p == PT.p || p == PT.k) return;
    _promotion = null;
    unawaited(playMove(pr.from, pr.to, p));
  }

  void cancelPromotion() {
    _promotion = null;
    _deselect();
  }

  void _updateMarkers() {
    final hist = chess.history;
    final last = hist.isEmpty ? null : hist.last;
    final sel = _selected;
    final targets = sel == null
        ? <TargetMarker>[]
        : [for (final m in legalFrom(sel)) TargetMarker(m.toName, capture: m.isCapture)];
    String? check;
    if (chess.isCheck) check = chess.kingSquare(chess.turn);
    board.setMarkers(MarkerSet(
      selected: sel,
      targets: targets,
      last: last == null ? null : (last.fromName, last.toName),
      check: check,
    ));
  }

  // ------------------------------------------------------------------ moves
  Future<Move?> playMove(String from, String to, [PT? promotion]) async {
    _busy = true;
    _selected = null;
    final mv = chess.move(from, to, promotion?.ch);
    if (mv == null) {
      _busy = false;
      _updateMarkers();
      _refresh();
      return null;
    }
    board.setMarkers(MarkerSet(last: (mv.fromName, mv.toName)));
    _refresh();
    final rank = from[1];
    final capSq = mv.isEp ? '${to[0]}$rank' : (mv.isCapture ? to : null);
    final jobs = <Future<void>>[
      board.movePiece(from, to, capture: capSq, promotion: mv.promotion),
      if (mv.isKingside) board.movePiece('h$rank', 'f$rank'),
      if (mv.isQueenside) board.movePiece('a$rank', 'd$rank'),
    ];
    if (mv.isCapture) {
      sfx.capture();
    } else {
      sfx.move();
    }
    await Future.wait(jobs);
    if (_disposed) return mv;
    _busy = false;
    _updateMarkers();
    final st = computeStatus();
    if (st.status != GameStatus.playing) {
      sfx.end();
    } else if (chess.isCheck) {
      sfx.check();
    }
    _refresh();
    _save();
    if (st.status == GameStatus.playing) {
      if (config.mode == GameMode.local && autoFlip) board.resetCamera(animate: true, side: chess.turn);
      unawaited(_maybeBotMove());
    }
    return mv;
  }

  Future<void> _maybeBotMove() async {
    if (!_active || config.mode != GameMode.bot) return;
    if (computeStatus().status != GameStatus.playing) return;
    if (chess.turn == config.humanColor) return;
    final token = ++_epoch;
    _thinking = true;
    _refresh();
    final started = DateTime.now();
    String? uci;
    try {
      uci = await engine.bestMove(chess.fen(), config.elo);
    } catch (e) {
      debugPrint('engine failed, falling back to a random move: $e');
      _engineError = true;
    }
    if (token != _epoch || _disposed) return; // cancelled (undo / new game / leave)
    final legal = chess.legalMoves();
    Move? mv;
    if (uci != null) {
      for (final m in legal) {
        if (m.uci == uci) {
          mv = m;
          break;
        }
      }
    }
    if (mv == null && legal.isNotEmpty) {
      mv = legal[_random.nextInt(legal.length)];
      if (uci != null) _engineError = true; // the engine answered with a move we don't accept
    }
    if (mv == null) {
      _thinking = false;
      _refresh();
      return;
    }
    final wait = thinkMinimum - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (token != _epoch || _disposed) return;
    _thinking = false;
    await playMove(mv.fromName, mv.toName, mv.promotion);
  }

  // ------------------------------------------------------------------ game actions
  void undo() {
    if (_busy || chess.history.isEmpty || _resigned != null) return;
    _cancelThinking();
    _agreedDraw = false;
    chess.undo();
    if (config.mode == GameMode.bot && chess.turn != config.humanColor && chess.history.isNotEmpty) chess.undo();
    _selected = null;
    _promotion = null;
    syncBoard();
    _refresh();
    _save();
    if (config.mode == GameMode.local && autoFlip) board.resetCamera(animate: true, side: chess.turn);
    unawaited(_maybeBotMove());
  }

  void resign() {
    if (computeStatus().status != GameStatus.playing) return;
    _cancelThinking();
    _resigned = config.mode == GameMode.bot ? config.humanColor : chess.turn;
    _selected = null;
    _promotion = null;
    board.unlift();
    _updateMarkers();
    _refresh();
    _save();
    sfx.end();
  }

  void agreeDraw() {
    if (computeStatus().status != GameStatus.playing) return;
    _cancelThinking();
    _agreedDraw = true;
    _selected = null;
    board.unlift();
    _updateMarkers();
    _refresh();
    _save();
    sfx.end();
  }

  /// Developer / test hook: jump to an arbitrary position.
  void debugLoadFen(String fen) {
    _cancelThinking();
    chess = Chess(fen);
    _selected = null;
    _promotion = null;
    _busy = false;
    _resigned = null;
    _agreedDraw = false;
    syncBoard();
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    engine.dispose();
    super.dispose();
  }
}
