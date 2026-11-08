// The 3D board widget: shows the native Filament texture, turns touches into camera moves / taps, drives the
// per-frame update (tweens, camera damping) and draws the a-h / 1-8 coordinate labels on top.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'board_model.dart';
import 'board_scene.dart';
import 'math3.dart';
import 'scene_renderer.dart';

class SceneView extends StatefulWidget {
  const SceneView({
    super.key,
    required this.model,
    required this.renderer,
    required this.onTap,
    required this.onEvent,
    this.shadows = true,
  });

  final BoardModel model;
  final SceneRenderer renderer;

  /// Tap on the board: the piece/square under the finger and the floor square under it.
  final void Function(String square, String? ground) onTap;

  /// Loading progress / completion / failure from the native renderer.
  final void Function(SceneEvent event) onEvent;
  final bool shadows;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  StreamSubscription<SceneEvent>? _sub;
  int? _textureId;
  bool _creating = false;
  bool _ready = false;
  int _texW = 0, _texH = 0;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  // pointer tracking
  final Map<int, Offset> _pointers = {};
  Offset? _downPos;
  DateTime _downTime = DateTime.now();
  bool _multi = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.renderer.events.listen((e) {
      if (e is SceneLoaded) {
        _ready = true;
        widget.model.modelsReady = true;
        widget.model.resetCamera(animate: false);
        widget.model.requestRender();
      }
      widget.onEvent(e);
    });
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(SceneView old) {
    super.didUpdateWidget(old);
    if (old.shadows != widget.shadows && _textureId != null) {
      unawaited(widget.renderer.setShadows(widget.shadows));
      widget.model.requestRender();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final changed = widget.model.tick(dt);
    if (changed) {
      _frame.value++;
      if (_ready) widget.renderer.sendFrame(widget.model.buildFrame());
    }
  }

  Future<void> _ensureTexture(double w, double h, double dpr) async {
    final cap = widget.shadows ? 2.0 : 1.25;
    final scale = math.min(dpr, cap);
    final pw = math.max(2, (w * scale).round()), ph = math.max(2, (h * scale).round());
    if (_textureId == null) {
      if (_creating) return;
      _creating = true;
      try {
        _texW = pw;
        _texH = ph;
        final id = await widget.renderer.create(width: pw, height: ph, shadows: widget.shadows);
        if (!mounted) return;
        setState(() => _textureId = id);
      } catch (e) {
        widget.onEvent(SceneError('Could not start the 3D renderer: $e'));
      } finally {
        _creating = false;
      }
    } else if (pw != _texW || ph != _texH) {
      _texW = pw;
      _texH = ph;
      await widget.renderer.resize(pw, ph);
      widget.model.requestRender();
    }
  }

  // ------------------------------------------------------------------ touch
  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _downPos = e.localPosition;
      _downTime = DateTime.now();
      _multi = false;
      widget.model.setAutoRotate(false);
    } else {
      _multi = true;
    }
  }

  void _move(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    final cam = widget.model.camera;
    if (_pointers.length == 1) {
      final d = e.localPosition - prev;
      cam.rotateByPixels(d.dx, d.dy);
    } else if (_pointers.length == 2) {
      final ids = _pointers.keys.toList();
      final a0 = _pointers[ids[0]]!, b0 = _pointers[ids[1]]!;
      final cur = Map<int, Offset>.from(_pointers)..[e.pointer] = e.localPosition;
      final a1 = cur[ids[0]]!, b1 = cur[ids[1]]!;
      final d0 = (a0 - b0).distance, d1 = (a1 - b1).distance;
      if (d0 > 1) cam.zoomByRatio(d1 / d0);
      final c0 = (a0 + b0) / 2, c1 = (a1 + b1) / 2;
      final dc = c1 - c0;
      cam.panByPixels(dc.dx, dc.dy);
    }
    _pointers[e.pointer] = e.localPosition;
    widget.model.requestRender();
  }

  void _up(PointerUpEvent e) {
    final was = _pointers.remove(e.pointer);
    final down = _downPos;
    if (_pointers.isEmpty && down != null && was != null) {
      _downPos = null;
      final moved = (e.localPosition - down).distance;
      final quick = DateTime.now().difference(_downTime).inMilliseconds < 600;
      if (!_multi && moved < 9 && quick) _tap(e.localPosition);
    }
  }

  void _cancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) _downPos = null;
  }

  void _tap(Offset p) {
    final m = widget.model;
    final sq = m.pick(p.dx, p.dy);
    if (sq != null) widget.onTap(sq, m.pickGround(p.dx, p.dy));
  }

  void _scroll(PointerSignalEvent e) {
    // mouse wheel (emulator / ChromeOS / desktop)
    if (e is PointerScrollEvent) {
      widget.model.camera.zoomByRatio(math.exp(-e.scrollDelta.dy / 300));
      widget.model.requestRender();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      if (w.isFinite && h.isFinite && w > 0 && h > 0) {
        widget.model.setViewSize(w, h);
        unawaited(_ensureTexture(w, h, dpr));
      }
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        onPointerSignal: _scroll,
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Color(0xFF15110E)),
          if (_textureId != null) Texture(textureId: _textureId!, filterQuality: FilterQuality.medium),
          if (_ready)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: LabelsPainter(widget.model, _frame)),
              ),
            ),
        ]),
      );
    });
  }
}

/// a-h and 1-8 around the board, drawn from the projected 3D positions so they follow the camera.
class LabelsPainter extends CustomPainter {
  LabelsPainter(this.model, Listenable repaint) : super(repaint: repaint);
  final BoardModel model;

  static const double _fontSize = 48;
  static final Map<String, TextPainter> _cache = {};

  static TextPainter _tp(String text) => _cache.putIfAbsent(text, () {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(fontSize: _fontSize, fontWeight: FontWeight.w600, color: Color(0xD9F0DEBE)),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        return tp;
      });

  /// World positions and texts of the 32 labels (testable).
  static List<({String text, V3 pos})> labelPositions() {
    final out = <({String text, V3 pos})>[];
    const y = surfaceY + 0.004;
    for (var i = 0; i < 8; i++) {
      final letter = String.fromCharCode(97 + i);
      out.add((text: letter, pos: V3(i - 3.5, y, 4.3)));
      out.add((text: letter, pos: V3(i - 3.5, y, -4.3)));
      out.add((text: '${i + 1}', pos: V3(-4.3, y, 3.5 - i)));
      out.add((text: '${i + 1}', pos: V3(4.3, y, 3.5 - i)));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!model.labelsVisible) return;
    final cam = model.camera;
    final w = size.width, h = size.height;
    final tanHalf = math.tan(degToRad(cam.fov) / 2);
    final fwd = cam.basis.forward;
    final eye = cam.eye;
    for (final l in labelPositions()) {
      final s = cam.project(l.pos, w, h);
      if (s == null) continue;
      final depth = (l.pos - eye).dot(fwd);
      final pxPerUnit = h / (2 * tanHalf * depth);
      final scale = pxPerUnit * 0.42 / _fontSize * 0.85;
      final tp = _tp(l.text);
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.scale(scale);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(LabelsPainter old) => true;
}
