// The link between the Dart scene model and the native Filament renderer.
//
// Dart owns all state (pieces, camera, tweens). Each time something changes it sends one compact Float32List
// (see BoardModel.buildFrame) and the native side draws it into a Flutter Texture.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

sealed class SceneEvent {
  const SceneEvent();
}

class SceneProgress extends SceneEvent {
  final int done, total;
  const SceneProgress(this.done, this.total);
}

class SceneLoaded extends SceneEvent {
  const SceneLoaded();
}

class SceneError extends SceneEvent {
  final String message;
  const SceneError(this.message);
}

abstract class SceneRenderer {
  /// Loading progress / completion / failure reported by the native side.
  Stream<SceneEvent> get events;

  /// Creates the native scene and its output texture. Returns the Flutter texture id.
  Future<int> create({required int width, required int height, required bool shadows});

  /// Changes the size of the output texture (physical pixels).
  Future<void> resize(int width, int height);

  Future<void> setShadows(bool on);

  /// Sends one frame. Implementations may drop an older frame when a newer one arrives.
  void sendFrame(Float32List frame);

  Future<void> dispose();
}

class ChannelSceneRenderer implements SceneRenderer {
  ChannelSceneRenderer() {
    _ch.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _ch = MethodChannel('chess3d/scene');
  final StreamController<SceneEvent> _events = StreamController<SceneEvent>.broadcast();
  bool _sending = false;
  Float32List? _pending;
  bool _created = false;

  @override
  Stream<SceneEvent> get events => _events.stream;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'progress':
        final a = call.arguments as Map;
        _events.add(SceneProgress(a['done'] as int, a['total'] as int));
      case 'loaded':
        _events.add(const SceneLoaded());
      case 'error':
        final a = call.arguments;
        _events.add(SceneError(a is Map ? '${a['message']}' : '$a'));
    }
    return null;
  }

  @override
  Future<int> create({required int width, required int height, required bool shadows}) async {
    final id = await _ch.invokeMethod<int>('create', {'width': width, 'height': height, 'shadows': shadows});
    _created = true;
    return id!;
  }

  @override
  Future<void> resize(int width, int height) async {
    await _ch.invokeMethod<void>('resize', {'width': width, 'height': height});
  }

  @override
  Future<void> setShadows(bool on) async {
    await _ch.invokeMethod<void>('setShadows', {'on': on});
  }

  @override
  void sendFrame(Float32List frame) {
    if (!_created) return;
    if (_sending) {
      _pending = frame; // keep only the newest
      return;
    }
    _sending = true;
    unawaited(_ch.invokeMethod<void>('frame', frame).whenComplete(() {
      _sending = false;
      final p = _pending;
      if (p != null) {
        _pending = null;
        sendFrame(p);
      }
    }).catchError((Object _) {}));
  }

  @override
  Future<void> dispose() async {
    _created = false;
    _ch.setMethodCallHandler(null);
    try {
      await _ch.invokeMethod<void>('dispose');
    } catch (_) {}
    await _events.close();
  }
}
