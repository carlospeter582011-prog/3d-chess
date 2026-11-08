// Basic chess vocabulary shared by the rules engine, the game controller, the scene and the UI.

enum Side { w, b }

extension SideX on Side {
  Side get other => this == Side.w ? Side.b : Side.w;
  String get ch => this == Side.w ? 'w' : 'b';
  String get label => this == Side.w ? 'White' : 'Black';
}

Side sideFromChar(String c) => c == 'w' ? Side.w : Side.b;

/// Piece types in the same order as the original web app's letters.
enum PT { p, n, b, r, q, k }

extension PTX on PT {
  String get ch => 'pnbrqk'[index];
  String get label => const ['Pawn', 'Knight', 'Bishop', 'Rook', 'Queen', 'King'][index];

  /// Name used by the 3D model files (king_light.glb, ...).
  String get modelName => const ['pawn', 'knight', 'bishop', 'rook', 'queen', 'king'][index];

  /// Material value used for the captured-pieces display.
  int get value => const [1, 3, 3, 5, 9, 0][index];
}

PT? ptFromChar(String c) {
  final i = 'pnbrqk'.indexOf(c.toLowerCase());
  return i < 0 ? null : PT.values[i];
}

class Piece {
  final Side side;
  final PT type;
  const Piece(this.side, this.type);

  /// FEN letter: upper case for White.
  String get fen => side == Side.w ? type.ch.toUpperCase() : type.ch;

  @override
  bool operator ==(Object other) => other is Piece && other.side == side && other.type == type;

  @override
  int get hashCode => Object.hash(side, type);

  @override
  String toString() => '${side.ch}${type.ch}';
}

/// Square index: a1 = 0, b1 = 1, ... h1 = 7, a2 = 8, ... h8 = 63.
String sqName(int sq) => '${'abcdefgh'[sq & 7]}${(sq >> 3) + 1}';

int sqIndex(String name) {
  assert(name.length == 2);
  return (name.codeUnitAt(1) - 49) * 8 + (name.codeUnitAt(0) - 97);
}

bool isValidSquare(String name) =>
    name.length == 2 &&
    name.codeUnitAt(0) >= 97 &&
    name.codeUnitAt(0) <= 104 &&
    name.codeUnitAt(1) >= 49 &&
    name.codeUnitAt(1) <= 56;

/// A piece standing on a square, used to tell the 3D scene what to show.
class PlacedPiece {
  final String square;
  final Side side;
  final PT type;
  const PlacedPiece(this.square, this.side, this.type);

  @override
  bool operator ==(Object other) =>
      other is PlacedPiece && other.square == square && other.side == side && other.type == type;

  @override
  int get hashCode => Object.hash(square, side, type);

  @override
  String toString() => '${side.ch}${type.ch}@$square';
}
