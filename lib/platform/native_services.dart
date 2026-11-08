// Android services reached through a MethodChannel: persistent key-value storage (SharedPreferences) and sound
// (SoundPool). Both are tiny, so no extra pub packages are needed.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game/storage.dart';
import 'sfx_synth.dart';

const MethodChannel _services = MethodChannel('chess3d/services');

class ChannelStore implements KeyValueStore {
  final Map<String, String> _cache = {};

  @override
  Future<void> load() async {
    try {
      final all = await _services.invokeMapMethod<String, String>('storeGetAll');
      _cache
        ..clear()
        ..addAll(all ?? const {});
    } catch (e) {
      debugPrint('storage load failed: $e');
    }
  }

  @override
  String? get(String key) => _cache[key];

  @override
  void set(String key, String value) {
    _cache[key] = value;
    unawaited(_services.invokeMethod<void>('storeSet', {'key': key, 'value': value}).catchError((Object e) {
      debugPrint('storage write failed: $e');
    }));
  }

  @override
  void remove(String key) {
    _cache.remove(key);
    unawaited(_services.invokeMethod<void>('storeRemove', {'key': key}).catchError((Object e) {
      debugPrint('storage remove failed: $e');
    }));
  }
}

class ChannelSfx implements Sfx {
  bool _muted = false;
  bool _loaded = false;

  /// Generates the sounds and gives them to the native SoundPool.
  Future<void> init() async {
    try {
      for (final name in soundNames) {
        final wav = toWav(synthesize(name));
        await _services.invokeMethod<void>('sfxLoad', {'name': name, 'wav': wav});
      }
      _loaded = true;
    } catch (e) {
      debugPrint('sound init failed: $e');
    }
  }

  void _play(String name) {
    if (_muted || !_loaded) return;
    unawaited(_services.invokeMethod<void>('sfxPlay', {'name': name}).catchError((Object _) {}));
  }

  @override
  void setMuted(bool muted) => _muted = muted;
  @override
  void move() => _play('move');
  @override
  void capture() => _play('capture');
  @override
  void check() => _play('check');
  @override
  void end() => _play('end');
}
