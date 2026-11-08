import '../chess/types.dart';

/// Chess glyphs. U+FE0E forces the text (not emoji) form of the pawn on Android.
const Map<PT, String> glyph = {
  PT.k: '♚',
  PT.q: '♛',
  PT.r: '♜',
  PT.b: '♝',
  PT.n: '♞',
  PT.p: '♟︎',
};
