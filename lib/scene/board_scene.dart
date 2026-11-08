// What the game controller needs from the 3D board, plus the board geometry constants shared by everything.
//
// Geometry (identical to the web version): one board square == 1.0 world unit, file a is at -x and rank 1 at +z
// (White sits on the +z side), the playing surface of the supplied board model is at y = 0.464.

import '../chess/types.dart';
import 'math3.dart';

const double surfaceY = 0.464;

/// World position of the centre of a square at height [y].
V3 sqToWorld(String sq, [double y = surfaceY]) {
  final file = sq.codeUnitAt(0) - 97;
  final rank = sq.codeUnitAt(1) - 49;
  return V3(file - 3.5, y, 3.5 - rank);
}

/// Square under a point of the table, or null when it is off the board.
String? worldToSq(double x, double z) {
  final file = (x + 4).floor();
  final rank = (4 - z).floor();
  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
  return '${String.fromCharCode(97 + file)}${rank + 1}';
}

/// A legal destination shown with a dot (or a ring when it captures).
class TargetMarker {
  final String square;
  final bool capture;
  const TargetMarker(this.square, {this.capture = false});
}

/// The coloured squares / dots drawn on the board.
class MarkerSet {
  final String? selected;
  final List<TargetMarker> targets;
  final (String, String)? last;
  final String? check;
  const MarkerSet({this.selected, this.targets = const [], this.last, this.check});
  static const MarkerSet none = MarkerSet();
}

abstract class BoardScene {
  /// When false, moves are applied instantly (tests, reduced motion).
  bool animations = true;

  /// Rebuilds every piece from a position (new game, undo, resume).
  void setPosition(List<PlacedPiece> placed);

  /// What is on the board right now (compare with the rules engine in tests).
  List<PlacedPiece> snapshot();

  /// Slides a piece; resolves when the animation has finished.
  /// [capture] is the square of the piece that is taken (differs from [to] for en passant).
  Future<void> movePiece(String from, String to, {String? capture, PT? promotion});

  void lift(String sq);
  void unlift();
  void setMarkers(MarkerSet markers);
  void setLabelsVisible(bool v);

  // camera
  void resetCamera({bool animate = true, Side side = Side.w, bool top = false});
  void flipView();
  Side viewSide();
  void setAutoRotate(bool v);
}
