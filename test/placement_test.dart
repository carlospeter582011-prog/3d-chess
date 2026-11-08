// "Is every piece in the right place?": the starting position on the 3D board, the square <-> world mapping, and
// the dimensions of the supplied GLB models (each piece must stand on the board with the expected height).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chess3d/chess/rules.dart';
import 'package:chess3d/chess/types.dart';
import 'package:chess3d/scene/board_model.dart';
import 'package:chess3d/scene/board_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bounding box of a GLB scene in world units (nodes' TRS / matrix applied to the POSITION accessor bounds).
({List<double> min, List<double> max}) glbBounds(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'glTF', reason: '$path is not a GLB');
  final jsonLen = bd.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLen))) as Map<String, dynamic>;
  final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
  final meshes = (json['meshes'] as List).cast<Map<String, dynamic>>();
  final accessors = (json['accessors'] as List).cast<Map<String, dynamic>>();
  final scene = (json['scenes'] as List)[json['scene'] as int? ?? 0] as Map<String, dynamic>;

  List<double> mul(List<double> a, List<double> b) {
    final r = List<double>.filled(16, 0);
    for (var c = 0; c < 4; c++) {
      for (var rr = 0; rr < 4; rr++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += a[k * 4 + rr] * b[c * 4 + k];
        }
        r[c * 4 + rr] = s;
      }
    }
    return r;
  }

  List<double> local(Map<String, dynamic> n) {
    if (n['matrix'] != null) return (n['matrix'] as List).map((e) => (e as num).toDouble()).toList();
    final t = ((n['translation'] ?? [0, 0, 0]) as List).map((e) => (e as num).toDouble()).toList();
    final q = ((n['rotation'] ?? [0, 0, 0, 1]) as List).map((e) => (e as num).toDouble()).toList();
    final s = ((n['scale'] ?? [1, 1, 1]) as List).map((e) => (e as num).toDouble()).toList();
    final x = q[0], y = q[1], z = q[2], w = q[3];
    return [
      (1 - 2 * (y * y + z * z)) * s[0], (2 * (x * y + z * w)) * s[0], (2 * (x * z - y * w)) * s[0], 0,
      (2 * (x * y - z * w)) * s[1], (1 - 2 * (x * x + z * z)) * s[1], (2 * (y * z + x * w)) * s[1], 0,
      (2 * (x * z + y * w)) * s[2], (2 * (y * z - x * w)) * s[2], (1 - 2 * (x * x + y * y)) * s[2], 0,
      t[0], t[1], t[2], 1,
    ];
  }

  final mn = [double.infinity, double.infinity, double.infinity];
  final mx = [-double.infinity, -double.infinity, -double.infinity];

  void visit(int idx, List<double> parent) {
    final n = nodes[idx];
    final m = mul(parent, local(n));
    if (n['mesh'] != null) {
      for (final prim in (meshes[n['mesh'] as int]['primitives'] as List).cast<Map<String, dynamic>>()) {
        final acc = accessors[(prim['attributes'] as Map)['POSITION'] as int];
        final lo = (acc['min'] as List).map((e) => (e as num).toDouble()).toList();
        final hi = (acc['max'] as List).map((e) => (e as num).toDouble()).toList();
        for (var i = 0; i < 8; i++) {
          final p = [i & 1 == 0 ? lo[0] : hi[0], i & 2 == 0 ? lo[1] : hi[1], i & 4 == 0 ? lo[2] : hi[2]];
          for (var a = 0; a < 3; a++) {
            final v = m[0 + a] * p[0] + m[4 + a] * p[1] + m[8 + a] * p[2] + m[12 + a];
            mn[a] = math.min(mn[a], v);
            mx[a] = math.max(mx[a], v);
          }
        }
      }
    }
    for (final c in ((n['children'] ?? []) as List)) {
      visit(c as int, m);
    }
  }

  const identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  for (final r in (scene['nodes'] as List)) {
    visit(r as int, identity);
  }
  return (min: mn, max: mx);
}

String modelPath(String name) => 'assets/models/$name.glb';

void main() {
  group('starting position', () {
    final pieces = Chess().pieces();
    String at(String sq) {
      final p = pieces.where((e) => e.square == sq).toList();
      return p.isEmpty ? '' : '${p.single.side.ch}${p.single.type.ch}';
    }

    test('White back rank is R N B Q K B N R on rank 1', () {
      expect(['a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1', 'h1'].map(at).toList(),
          ['wr', 'wn', 'wb', 'wq', 'wk', 'wb', 'wn', 'wr']);
    });
    test('Black back rank is R N B Q K B N R on rank 8 (queen on d8, king on e8)', () {
      expect(['a8', 'b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8'].map(at).toList(),
          ['br', 'bn', 'bb', 'bq', 'bk', 'bb', 'bn', 'br']);
    });
    test('pawns on ranks 2 and 7', () {
      for (final f in 'abcdefgh'.split('')) {
        expect(at('${f}2'), 'wp');
        expect(at('${f}7'), 'bp');
      }
    });
    test('ranks 3-6 are empty and there are 32 pieces', () {
      for (final f in 'abcdefgh'.split('')) {
        for (final r in '3456'.split('')) {
          expect(at('$f$r'), '', reason: '$f$r');
        }
      }
      expect(pieces.length, 32);
    });
    test('each side has the right army', () {
      for (final side in Side.values) {
        final mine = pieces.where((p) => p.side == side).map((p) => p.type).toList();
        int n(PT t) => mine.where((x) => x == t).length;
        expect([n(PT.k), n(PT.q), n(PT.r), n(PT.b), n(PT.n), n(PT.p)], [1, 1, 2, 2, 2, 8]);
      }
    });
    test('squares of the same colour: a1 is dark, h1 is light (a1+h8 diagonal)', () {
      bool dark(String s) => ((s.codeUnitAt(0) - 97) + (s.codeUnitAt(1) - 49)) % 2 == 0;
      expect(dark('a1'), isTrue);
      expect(dark('h1'), isFalse);
      expect(dark('a8'), isFalse);
      expect(dark('h8'), isTrue);
    });
  });

  group('square <-> world mapping', () {
    test('white sits on the +z side, file a on the -x side', () {
      final a1 = sqToWorld('a1');
      final h8 = sqToWorld('h8');
      expect(a1.x, -3.5);
      expect(a1.z, 3.5);
      expect(h8.x, 3.5);
      expect(h8.z, -3.5);
      expect(a1.y, surfaceY);
      expect(sqToWorld('e1').x, 0.5);
      expect(sqToWorld('d1').x, -0.5);
      expect(sqToWorld('e2').z, 2.5);
    });
    test('worldToSq inverts sqToWorld for all 64 squares', () {
      for (final f in 'abcdefgh'.split('')) {
        for (var r = 1; r <= 8; r++) {
          final sq = '$f$r';
          final w = sqToWorld(sq);
          expect(worldToSq(w.x, w.z), sq);
          // also anywhere inside the square
          expect(worldToSq(w.x + 0.49, w.z - 0.49), sq);
          expect(worldToSq(w.x - 0.49, w.z + 0.49), sq);
        }
      }
    });
    test('off the board is null', () {
      expect(worldToSq(4.01, 0), isNull);
      expect(worldToSq(-4.01, 0), isNull);
      expect(worldToSq(0, 4.01), isNull);
      expect(worldToSq(0, -4.01), isNull);
    });
    test('surface height equals the supplied board model', () {
      expect(surfaceY, 0.464);
    });
  });

  group('3D board holds the rules engine position', () {
    test('after setPosition every piece stands on the centre of its square', () {
      final chess = Chess();
      final model = BoardModel()..animations = false;
      model.setPosition(chess.pieces());
      expect(model.pieceCount, 32);
      expect(model.snapshot().toSet(), chess.pieces().toSet());
      for (final p in chess.pieces()) {
        final obj = model.pieceOn(p.square)!;
        final w = sqToWorld(p.square);
        expect((obj.pos.x - w.x).abs(), lessThan(1e-9));
        expect((obj.pos.y - surfaceY).abs(), lessThan(1e-9));
        expect((obj.pos.z - w.z).abs(), lessThan(1e-9));
        expect(obj.type, p.type);
        expect(obj.side, p.side);
      }
    });
    test('knights and bishops of White are turned to face Black, all others are not rotated', () {
      final model = BoardModel()..animations = false;
      model.setPosition(Chess().pieces());
      for (final sq in ['b1', 'g1', 'c1', 'f1']) {
        expect(model.pieceOn(sq)!.rotY, closeTo(math.pi, 1e-12), reason: sq);
      }
      for (final sq in ['b8', 'g8', 'c8', 'f8', 'a1', 'd1', 'e1', 'a2', 'e7', 'd8']) {
        expect(model.pieceOn(sq)!.rotY, 0, reason: sq);
      }
    });
    test('every piece owns a distinct renderer slot of the right type and colour', () {
      final model = BoardModel()..animations = false;
      model.setPosition(Chess().pieces());
      final slots = <int>{};
      for (final p in Chess().pieces()) {
        final obj = model.pieceOn(p.square)!;
        expect(slots.add(obj.slot), isTrue, reason: 'duplicate slot on ${p.square}');
        expect(Slots.typeOf(obj.slot), p.type);
        expect(Slots.sideOf(obj.slot), p.side);
        expect(Slots.instanceOf(obj.slot), lessThan(Slots.pool[p.type]!));
      }
    });
    test('the frame buffer reports every piece at its square', () {
      final model = BoardModel()..animations = false;
      model.setPosition(Chess().pieces());
      final f = model.buildFrame();
      expect(f[8], 32);
      final seen = <String>{};
      for (var i = 0; i < 32; i++) {
        final o = BoardModel.headerSize + i * BoardModel.pieceStride;
        final slot = f[o].toInt();
        final sq = worldToSq(f[o + 1], f[o + 3])!;
        final p = Chess().get(sq)!;
        expect(Slots.typeOf(slot), p.type, reason: sq);
        expect(Slots.sideOf(slot), p.side, reason: sq);
        expect(f[o + 2], closeTo(surfaceY, 1e-6));
        seen.add(sq);
      }
      expect(seen.length, 32);
    });
  });

  group('supplied 3D models (assets/models)', () {
    // heights (and base on y = 0) as the web version assumed
    const heights = {'king': 1.5, 'queen': 1.3, 'bishop': 1.1, 'knight': 1.0, 'rook': 0.82, 'pawn': 0.74};

    for (final e in heights.entries) {
      for (final c in ['light', 'dark']) {
        test('${e.key}_$c stands on y = 0 and is ${e.value} tall, inside one square', () {
          final b = glbBounds(modelPath('${e.key}_$c'));
          expect(b.min[1], closeTo(0, 0.01), reason: 'base must touch the board');
          expect(b.max[1], closeTo(e.value, 0.01));
          // centred in its square and narrower than a square
          expect((b.min[0] + b.max[0]) / 2, closeTo(0, 0.03));
          expect((b.min[2] + b.max[2]) / 2, closeTo(0, 0.06)); // the knight's nose points to +z
          expect(b.max[0] - b.min[0], lessThan(0.9));
          expect(b.max[2] - b.min[2], lessThan(0.9));
        });
      }
    }

    test('piece heights are ordered king > queen > bishop > knight > rook > pawn', () {
      double h(String n) => glbBounds(modelPath('${n}_light')).max[1];
      expect(h('king'), greaterThan(h('queen')));
      expect(h('queen'), greaterThan(h('bishop')));
      expect(h('bishop'), greaterThan(h('knight')));
      expect(h('knight'), greaterThan(h('rook')));
      expect(h('rook'), greaterThan(h('pawn')));
    });

    test('the knight model faces +z (its nose is on the +z side)', () {
      for (final c in ['light', 'dark']) {
        final b = glbBounds(modelPath('knight_$c'));
        expect(b.max[2].abs(), greaterThan(b.min[2].abs()));
      }
    });

    test('board: playing surface at y = 0.464, 8 x 8 squares fit inside the frame', () {
      final b = glbBounds(modelPath('board'));
      expect(b.max[1], closeTo(surfaceY, 0.002));
      expect(b.min[0], lessThan(-4));
      expect(b.max[0], greaterThan(4));
      expect(b.min[2], lessThan(-4));
      expect(b.max[2], greaterThan(4));
      expect(b.max[0] + b.min[0], closeTo(0, 0.01)); // centred on the origin
      expect(b.max[2] + b.min[2], closeTo(0, 0.01));
    });

    test('piece heights used for tap volumes match the real models', () {
      for (final t in PT.values) {
        final real = glbBounds(modelPath('${t.modelName}_light')).max[1];
        expect(BoardModel.heights[t], closeTo(real, 0.01), reason: t.label);
      }
    });

    test('all 12 piece models, board, table and markers exist as GLB files', () {
      final names = [
        for (final t in PT.values)
          for (final c in ['light', 'dark']) '${t.modelName}_$c',
        'board',
        'table',
        ...MarkerKind.models,
      ];
      for (final n in names) {
        final f = File(modelPath(n));
        expect(f.existsSync(), isTrue, reason: n);
        expect(String.fromCharCodes(f.readAsBytesSync().sublist(0, 4)), 'glTF', reason: n);
      }
      expect(names.length, 12 + 1 + 1 + 5);
    });

    test('no model requires EXT_texture_webp (Filament cannot decode WebP)', () {
      final dir = Directory('assets/models');
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.glb'))) {
        final bytes = f.readAsBytesSync();
        final jsonLen = ByteData.sublistView(bytes).getUint32(12, Endian.little);
        final json = utf8.decode(bytes.sublist(20, 20 + jsonLen));
        expect(json.contains('EXT_texture_webp'), isFalse, reason: f.path);
        expect(json.contains('image/webp'), isFalse, reason: f.path);
      }
    });
  });
}
