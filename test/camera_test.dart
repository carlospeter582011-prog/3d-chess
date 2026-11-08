import 'dart:math' as math;

import 'package:chess3d/chess/rules.dart';
import 'package:chess3d/chess/types.dart';
import 'package:chess3d/scene/board_model.dart';
import 'package:chess3d/scene/math3.dart';
import 'package:chess3d/scene/orbit_camera.dart';
import 'package:flutter_test/flutter_test.dart';

BoardModel portraitModel() {
  final m = BoardModel()..animations = false;
  m.modelsReady = true;
  m.setViewSize(400, 800);
  m.resetCamera(animate: false);
  return m;
}

BoardModel landscapeModel() {
  final m = BoardModel()..animations = false;
  m.modelsReady = true;
  m.setViewSize(1200, 700);
  m.resetCamera(animate: false);
  return m;
}

void main() {
  group('OrbitCamera', () {
    test('starts above White\'s side looking at the board', () {
      final c = OrbitCamera();
      expect(c.eye.z, greaterThan(0));
      expect(c.eye.y, greaterThan(0));
      expect(c.fromWhiteSide, isTrue);
      expect(c.basis.forward.z, lessThan(0));
    });

    test('fov is wider on portrait screens', () {
      final c = OrbitCamera();
      c.setViewport(400, 800);
      expect(c.fov, 50);
      c.setViewport(1200, 700);
      expect(c.fov, 38);
    });

    test('dragging rotates; polar angle stays between the pole and just above the table', () {
      final c = OrbitCamera()..animations = false;
      final theta0 = c.theta;
      c.rotateByPixels(120, 0);
      for (var i = 0; i < 200; i++) {
        c.update(1 / 60);
      }
      expect(c.theta, isNot(closeTo(theta0, 0.05)));
      c.rotateByPixels(0, 100000);
      for (var i = 0; i < 300; i++) {
        c.update(1 / 60);
      }
      expect(c.phi, closeTo(0.02, 1e-6)); // dragging down looks from straight above
      c.rotateByPixels(0, -100000);
      for (var i = 0; i < 300; i++) {
        c.update(1 / 60);
      }
      expect(c.phi, closeTo(math.pi * 0.49, 1e-6)); // dragging up stops just above the table
      expect(c.eye.y, greaterThan(0)); // never under the table
    });

    test('zoom is limited to 5..40 units', () {
      final c = OrbitCamera()..animations = false;
      for (var i = 0; i < 100; i++) {
        c.zoomByRatio(1.5);
        c.update(1 / 60);
      }
      expect(c.radius, closeTo(5, 1e-9));
      for (var i = 0; i < 200; i++) {
        c.zoomByRatio(0.5);
        c.update(1 / 60);
      }
      expect(c.radius, closeTo(40, 1e-9));
    });

    test('pinch out zooms in, pinch in zooms out', () {
      final c = OrbitCamera();
      c.radius = 20;
      c.zoomByRatio(1.3);
      c.update(1 / 60);
      expect(c.radius, lessThan(20));
      final r = c.radius;
      c.zoomByRatio(0.7);
      c.update(1 / 60);
      expect(c.radius, greaterThan(r));
    });

    test('panning moves the target but keeps it near the table', () {
      final c = OrbitCamera();
      c.panByPixels(100000, 100000);
      for (var i = 0; i < 300; i++) {
        c.update(1 / 60);
      }
      expect(c.target.x.abs(), lessThanOrEqualTo(6));
      expect(c.target.z.abs(), lessThanOrEqualTo(6));
      expect(c.target.y, inInclusiveRange(0, 3));
    });

    test('reset without animation lands on the fit distance, 52 degrees, White\'s side', () {
      final c = OrbitCamera()..animations = false;
      c.setViewport(400, 800);
      c.rotateByPixels(300, 200);
      c.update(0.1);
      c.reset(animate: false);
      expect(c.radius, closeTo(c.fitDistance(), 1e-9));
      expect(c.phi, closeTo(degToRad(52), 1e-9));
      expect(math.cos(c.theta), closeTo(1, 1e-9));
      expect(c.target.y, 0.4);
    });

    test('reset to Black\'s side and top-down view', () {
      final c = OrbitCamera()..animations = false;
      c.reset(animate: false, whiteSide: false);
      expect(c.fromWhiteSide, isFalse);
      expect(c.eye.z, lessThan(0));
      c.reset(animate: false, top: true);
      expect(c.phi, closeTo(0.02, 1e-9));
    });

    test('flip turns half a circle by the shortest way', () {
      final c = OrbitCamera()..animations = false;
      c.flip();
      expect(c.fromWhiteSide, isFalse);
      c.flip();
      expect(c.fromWhiteSide, isTrue);
    });

    test('animated fly-to finishes after 700 ms', () {
      final c = OrbitCamera();
      c.flip();
      expect(c.flying, isTrue);
      var t = 0.0;
      while (c.flying && t < 3) {
        c.update(1 / 60);
        t += 1 / 60;
      }
      expect(t, closeTo(0.7, 0.03));
      expect(c.fromWhiteSide, isFalse);
    });

    test('touching the screen cancels a running fly-to', () {
      final c = OrbitCamera();
      c.flip();
      c.update(0.1);
      c.rotateByPixels(5, 0);
      expect(c.flying, isFalse);
    });

    test('fit distance shows the whole board in portrait and landscape', () {
      for (final size in [const Size2(400, 800), const Size2(1200, 700), const Size2(700, 700)]) {
        final c = OrbitCamera();
        c.setViewport(size.w, size.h);
        c.reset(animate: false);
        // all four outer corners of the board frame must project inside the view
        for (final p in const [V3(-4.6, 0.46, -4.6), V3(4.6, 0.46, -4.6), V3(-4.6, 0.46, 4.6), V3(4.6, 0.46, 4.6)]) {
          final s = c.project(p, size.w, size.h)!;
          expect(s.x, inInclusiveRange(0, size.w), reason: '$size $p x');
          expect(s.y, inInclusiveRange(0, size.h), reason: '$size $p y');
        }
      }
    });

    test('project and rayThrough agree', () {
      final c = OrbitCamera();
      c.setViewport(400, 800);
      c.reset(animate: false);
      const p = V3(1.5, 0.7, -2.0);
      final s = c.project(p, 400, 800)!;
      final ray = c.rayThrough(s.x, s.y, 400, 800);
      final toP = (p - ray.origin).normalized;
      expect(ray.dir.dot(toP), closeTo(1, 1e-9));
    });

    test('points behind the camera do not project', () {
      final c = OrbitCamera();
      expect(c.project(c.eye + (c.eye - c.target), 400, 800), isNull);
    });

    test('screen centre looks at the target', () {
      final c = OrbitCamera();
      c.setViewport(400, 800);
      final ray = c.rayThrough(200, 400, 400, 800);
      expect(ray.dir.dot((c.target - c.eye).normalized), closeTo(1, 1e-9));
    });
  });

  group('picking', () {
    for (final entry in {'portrait': portraitModel, 'landscape': landscapeModel}.entries) {
      test('${entry.key}: the floor square under every square centre is found (all 64)', () {
        final m = entry.value();
        for (final f in 'abcdefgh'.split('')) {
          for (var r = 1; r <= 8; r++) {
            final sq = '$f$r';
            final s = m.squareToScreen(sq, 0)!;
            expect(m.pickGround(s.x, s.y), sq, reason: sq);
          }
        }
      });
    }

    test('on an empty board pick() returns the floor square', () {
      final m = portraitModel();
      m.setPosition(const []);
      for (final sq in ['a1', 'h8', 'd4', 'e5', 'a8', 'h1']) {
        final s = m.squareToScreen(sq, 0)!;
        expect(m.pick(s.x, s.y), sq);
      }
    });

    test('tapping a front-rank piece from White\'s side selects it', () {
      final m = landscapeModel();
      m.setPosition(Chess().pieces());
      for (final sq in ['a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1', 'h1']) {
        final s = m.squareToScreen(sq, 0.4)!;
        expect(m.pick(s.x, s.y), sq, reason: sq);
      }
    });

    test('tapping a Black front-rank piece from Black\'s side selects it', () {
      final m = landscapeModel();
      m.resetCamera(animate: false, side: Side.b);
      m.setPosition(Chess().pieces());
      for (final sq in ['a8', 'b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8']) {
        final s = m.squareToScreen(sq, 0.4)!;
        expect(m.pick(s.x, s.y), sq, reason: sq);
      }
    });

    test('a tall piece in front hides the square behind it, but the floor square is still reported', () {
      final m = landscapeModel();
      m.setPosition(Chess().pieces());
      // tap the floor of e2: the king on e1 stands in front and is hit first
      final s = m.squareToScreen('e2', 0)!;
      expect(m.pickGround(s.x, s.y), 'e2');
    });

    test('rayCylinder: hit, miss, from above, and from inside', () {
      const c = V3(0, 0, 0);
      expect(BoardModel.rayCylinder(const V3(-5, 0.5, 0), const V3(1, 0, 0), c, 0.3, 0, 1), closeTo(4.7, 1e-9));
      expect(BoardModel.rayCylinder(const V3(-5, 0.5, 1), const V3(1, 0, 0), c, 0.3, 0, 1), isNull);
      expect(BoardModel.rayCylinder(const V3(-5, 2, 0), const V3(1, 0, 0), c, 0.3, 0, 1), isNull); // passes above
      expect(BoardModel.rayCylinder(const V3(0, 5, 0), const V3(0, -1, 0), c, 0.3, 0, 1), closeTo(4, 1e-9));
      expect(BoardModel.rayCylinder(const V3(0, 0.5, 0), const V3(1, 0, 0), c, 0.3, 0, 1), closeTo(0, 1e-9));
      expect(BoardModel.rayCylinder(const V3(5, 0.5, 0), const V3(1, 0, 0), c, 0.3, 0, 1), isNull); // pointing away
    });
  });
}

class Size2 {
  final double w, h;
  const Size2(this.w, this.h);
  @override
  String toString() => '${w}x$h';
}
