// The 3D board as pure Dart: piece objects, tweens, markers, camera, picking, and the compact per-frame
// buffer that is sent to the native Filament renderer. Everything here is unit-tested without a GPU.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../chess/types.dart';
import 'board_scene.dart';
import 'math3.dart';
import 'orbit_camera.dart';

/// Kinds of flat marker the renderer can draw.
class MarkerKind {
  static const int selected = 0;
  static const int last = 1;
  static const int check = 2;
  static const int dot = 3;
  static const int capture = 4;
  static const List<String> models = ['marker_sel', 'marker_last', 'marker_check', 'marker_dot', 'marker_cap'];

  /// How many of each kind can be visible at once.
  static const List<int> pool = [1, 2, 1, 32, 16];
}

/// Slots: every visible piece owns one renderer instance, numbered (typeIdx*2 + colorIdx) * 16 + instance.
class Slots {
  /// How many instances of each piece type exist per colour (original set + promotions).
  static const Map<PT, int> pool = {PT.k: 1, PT.q: 9, PT.r: 10, PT.b: 10, PT.n: 10, PT.p: 8};

  static int make(PT type, Side side, int instance) => (type.index * 2 + side.index) * 16 + instance;
  static PT typeOf(int slot) => PT.values[(slot >> 4) >> 1];
  static Side sideOf(int slot) => Side.values[(slot >> 4) & 1];
  static int instanceOf(int slot) => slot & 15;
}

class PieceObj {
  final int id;
  final Side side;
  final PT type;
  final int slot;
  String square;
  V3 pos;
  final double rotY;
  double rotZ = 0;
  double scale = 1;
  PieceObj(this.id, this.side, this.type, this.slot, this.square, this.pos, this.rotY);
}

class _Tween {
  double t = 0;
  double delay;
  final double dur;
  final void Function(double k) update;
  final Completer<void> done = Completer<void>();
  _Tween(this.dur, this.update, this.delay);
}

class BoardModel implements BoardScene {
  BoardModel() {
    camera.animations = true;
  }

  final OrbitCamera camera = OrbitCamera();

  @override
  bool animations = true;

  final Map<String, PieceObj> _pieces = {};
  final List<PieceObj> _all = [];
  final Set<int> _usedSlots = {};
  final List<_Tween> _tweens = [];
  int _nextId = 1;
  int _generation = 0;
  PieceObj? _lifted;
  MarkerSet _markers = MarkerSet.none;
  bool labelsVisible = true;
  bool dirty = true;
  double viewWidth = 1, viewHeight = 1;
  bool modelsReady = false;

  /// Piece heights, as in the web version (used for the tap volumes).
  static const Map<PT, double> heights = {PT.k: 1.5, PT.q: 1.3, PT.b: 1.1, PT.n: 1.0, PT.r: 0.82, PT.p: 0.74};
  static const double hitRadius = 0.3;

  // ------------------------------------------------------------------ viewport
  void setViewSize(double w, double h) {
    viewWidth = math.max(1, w);
    viewHeight = math.max(1, h);
    camera.setViewport(viewWidth, viewHeight, boardReady: modelsReady);
    dirty = true;
  }

  void requestRender() => dirty = true;

  // ------------------------------------------------------------------ pieces
  int _allocate(Side side, PT type) {
    final max = Slots.pool[type]!;
    for (var i = 0; i < max; i++) {
      final s = Slots.make(type, side, i);
      if (!_usedSlots.contains(s)) return s;
    }
    return -1;
  }

  PieceObj? _makePiece(Side side, PT type, String square) {
    final slot = _allocate(side, type);
    if (slot < 0) return null; // more pieces of one kind than the renderer pool holds (impossible in real games)
    _usedSlots.add(slot);
    // Knights and bishops face the opponent (models face +z, White's opponent is on -z)
    final rotY = (type == PT.n || type == PT.b) && side == Side.w ? math.pi : 0.0;
    final p = PieceObj(_nextId++, side, type, slot, square, sqToWorld(square), rotY);
    _pieces[square] = p;
    _all.add(p);
    return p;
  }

  void _removePiece(PieceObj p) {
    _all.remove(p);
    _usedSlots.remove(p.slot);
    if (identical(_pieces[p.square], p)) _pieces.remove(p.square);
    if (identical(_lifted, p)) _lifted = null;
  }

  @override
  void setPosition(List<PlacedPiece> placed) {
    _generation++;
    for (final t in _tweens) {
      if (!t.done.isCompleted) t.done.complete();
    }
    _tweens.clear();
    _lifted = null;
    _pieces.clear();
    _all.clear();
    _usedSlots.clear();
    for (final pc in placed) {
      _makePiece(pc.side, pc.type, pc.square);
    }
    dirty = true;
  }

  @override
  List<PlacedPiece> snapshot() => [
        for (final p in _all)
          // read the real world position, not just the bookkeeping
          PlacedPiece(worldToSq(p.pos.x, p.pos.z) ?? '??', p.side, p.type),
      ];

  /// The piece currently registered on a square (tests).
  PieceObj? pieceOn(String sq) => _pieces[sq];

  int get pieceCount => _all.length;

  /// All piece objects, including those in motion (tests / debugging).
  List<PieceObj> get pieceObjects => List.unmodifiable(_all);

  // ------------------------------------------------------------------ tweens
  Future<void> _tween(double dur, void Function(double k) update, {double delay = 0}) {
    if (!animations) {
      update(1);
      dirty = true;
      return Future<void>.value();
    }
    final t = _Tween(dur, update, delay);
    _tweens.add(t);
    return t.done.future;
  }

  bool get isAnimating => _tweens.isNotEmpty;

  @override
  Future<void> movePiece(String from, String to, {String? capture, PT? promotion}) async {
    final p = _pieces[from];
    if (p == null) throw StateError('no piece on $from');
    final gen = _generation;
    unlift();
    final a = sqToWorld(from), b = sqToWorld(to);
    final dist = a.distanceTo(b);
    final arc = p.type == PT.n ? 0.9 : 0.28;
    final dur = math.min(700.0, 280 + dist * 70);
    final victim = capture == null ? null : _pieces[capture];
    if (victim != null) _pieces.remove(capture);
    p.square = to;
    _pieces.remove(from);
    // the destination is only claimed at the end so snapshot() shows the final state
    final moving = _tween(dur, (k) {
      final e = easeInOut(k);
      p.pos = V3(a.x + (b.x - a.x) * e, surfaceY + math.sin(math.pi * e) * arc, a.z + (b.z - a.z) * e);
    });
    var victimFuture = Future<void>.value();
    if (victim != null) {
      final vp = victim.pos;
      victimFuture = _tween(320, (k) {
        victim.pos = V3(vp.x, vp.y + k * 0.7, vp.z);
        victim.scale = math.max(0.0001, 1 - k);
        victim.rotZ = k * 0.9;
      }, delay: dur * 0.6);
    }
    await Future.wait([moving, victimFuture]);
    if (gen != _generation) return; // the position was replaced while we were animating
    p.pos = b;
    _pieces[to] = p;
    if (victim != null) _removePiece(victim);
    if (promotion != null) {
      _removePiece(p);
      _makePiece(p.side, promotion, to);
    }
    dirty = true;
  }

  // ------------------------------------------------------------------ selection feedback
  @override
  void lift(String sq) {
    unlift();
    final p = _pieces[sq];
    if (p == null) return;
    p.pos = V3(p.pos.x, surfaceY + 0.22, p.pos.z);
    _lifted = p;
    dirty = true;
  }

  @override
  void unlift() {
    final l = _lifted;
    if (l != null) {
      l.pos = V3(l.pos.x, surfaceY, l.pos.z);
      _lifted = null;
      dirty = true;
    }
  }

  @override
  void setMarkers(MarkerSet markers) {
    _markers = markers;
    dirty = true;
  }

  MarkerSet get markers => _markers;

  @override
  void setLabelsVisible(bool v) {
    labelsVisible = v;
    dirty = true;
  }

  // ------------------------------------------------------------------ camera
  @override
  void resetCamera({bool animate = true, Side side = Side.w, bool top = false}) {
    camera.reset(animate: animate && animations, whiteSide: side == Side.w, top: top);
    dirty = true;
  }

  @override
  void flipView() {
    camera.animations = animations;
    camera.flip();
    dirty = true;
  }

  @override
  Side viewSide() => camera.fromWhiteSide ? Side.w : Side.b;

  @override
  void setAutoRotate(bool v) {
    camera.autoRotate = v;
    dirty = true;
  }

  // ------------------------------------------------------------------ per-frame update
  /// Advances tweens and camera by [dt] seconds. Returns true when something on screen changed.
  bool tick(double dt) {
    dt = math.min(0.25, math.max(0.0, dt));
    var changed = dirty;
    dirty = false;
    camera.animations = animations;
    if (_tweens.isNotEmpty) {
      changed = true;
      for (final tw in List<_Tween>.of(_tweens)) {
        if (tw.delay > 0) {
          tw.delay -= dt * 1000;
          continue;
        }
        tw.t += dt * 1000;
        final k = math.min(1.0, tw.t / tw.dur);
        tw.update(k);
        if (k >= 1) {
          _tweens.remove(tw);
          if (!tw.done.isCompleted) tw.done.complete();
        }
      }
    }
    if (camera.update(dt)) changed = true;
    return changed;
  }

  // ------------------------------------------------------------------ renderer frame
  /// Layout of the buffer (all float32):
  ///   [0..2] eye, [3..5] target, [6] vertical fov in degrees, [7] aspect
  ///   [8] P, then P x 7:  slot, x, y, z, rotY, rotZ, scale
  ///   then M, then M x 4: kind, x, y, z
  static const int headerSize = 9;
  static const int pieceStride = 7;
  static const int markerStride = 4;

  Float32List buildFrame() {
    final out = <double>[];
    final eye = camera.eye, t = camera.target;
    out.addAll([eye.x, eye.y, eye.z, t.x, t.y, t.z, camera.fov, camera.aspect]);
    out.add(_all.length.toDouble());
    for (final p in _all) {
      out.addAll([p.slot.toDouble(), p.pos.x, p.pos.y, p.pos.z, p.rotY, p.rotZ, p.scale]);
    }
    final marks = markerList();
    out.add(marks.length.toDouble());
    for (final m in marks) {
      out.addAll([m.kind.toDouble(), m.pos.x, m.pos.y, m.pos.z]);
    }
    return Float32List.fromList(out);
  }

  /// Flat markers with their world positions (y offsets as in the web version).
  List<({int kind, V3 pos})> markerList() {
    final res = <({int kind, V3 pos})>[];
    final mk = _markers;
    final last = mk.last;
    if (last != null) {
      res.add((kind: MarkerKind.last, pos: sqToWorld(last.$1, surfaceY + 0.004)));
      res.add((kind: MarkerKind.last, pos: sqToWorld(last.$2, surfaceY + 0.004)));
    }
    if (mk.check != null) res.add((kind: MarkerKind.check, pos: sqToWorld(mk.check!, surfaceY + 0.006)));
    if (mk.selected != null) res.add((kind: MarkerKind.selected, pos: sqToWorld(mk.selected!, surfaceY + 0.008)));
    final seen = <String>{};
    for (final t in mk.targets) {
      if (!seen.add(t.square)) continue;
      res.add((kind: t.capture ? MarkerKind.capture : MarkerKind.dot, pos: sqToWorld(t.square, surfaceY + 0.012)));
    }
    return res;
  }

  // ------------------------------------------------------------------ picking
  /// Distance along the ray to a vertical cylinder (axis through [c], from [y0] to [y1]), or null.
  static double? rayCylinder(V3 o, V3 d, V3 c, double r, double y0, double y1) {
    var tMin = 0.0, tMax = double.infinity;
    // slab in y
    if (d.y.abs() < 1e-12) {
      if (o.y < y0 || o.y > y1) return null;
    } else {
      var ta = (y0 - o.y) / d.y, tb = (y1 - o.y) / d.y;
      if (ta > tb) {
        final s = ta;
        ta = tb;
        tb = s;
      }
      tMin = math.max(tMin, ta);
      tMax = math.min(tMax, tb);
    }
    // disc in xz
    final ox = o.x - c.x, oz = o.z - c.z;
    final a = d.x * d.x + d.z * d.z;
    final b = 2 * (ox * d.x + oz * d.z);
    final cc = ox * ox + oz * oz - r * r;
    if (a < 1e-12) {
      if (cc > 0) return null;
    } else {
      final disc = b * b - 4 * a * cc;
      if (disc < 0) return null;
      final sq = math.sqrt(disc);
      final t0 = (-b - sq) / (2 * a), t1 = (-b + sq) / (2 * a);
      tMin = math.max(tMin, t0);
      tMax = math.min(tMax, t1);
    }
    if (tMax < tMin || tMax < 0) return null;
    return tMin;
  }

  /// Square of the piece (or the floor) under a point of the view, in logical pixels.
  String? pick(double sx, double sy) {
    final ray = camera.rayThrough(sx, sy, viewWidth, viewHeight);
    String? best;
    var bestT = double.infinity;
    for (final p in _pieces.values) {
      final h = math.max(heights[p.type]!, 0.9);
      final t = rayCylinder(ray.origin, ray.dir, p.pos, hitRadius, p.pos.y, p.pos.y + h);
      if (t != null && t < bestT) {
        bestT = t;
        best = p.square;
      }
    }
    return best ?? pickGround(sx, sy);
  }

  /// Board square under a point of the view, ignoring pieces.
  String? pickGround(double sx, double sy) {
    final ray = camera.rayThrough(sx, sy, viewWidth, viewHeight);
    if (ray.dir.y.abs() < 1e-9) return null;
    final t = (surfaceY - ray.origin.y) / ray.dir.y;
    if (t <= 0) return null;
    final pt = ray.origin + ray.dir * t;
    return worldToSq(pt.x, pt.z);
  }

  /// Screen position (logical px) of a square centre at height [h] above the surface.
  ({double x, double y})? squareToScreen(String sq, [double h = 0.3]) =>
      camera.project(sqToWorld(sq, surfaceY + h), viewWidth, viewHeight);
}
