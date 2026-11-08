// Connects the UCI client to the on-device Stockfish engine (the `stockfish` plugin, native code via FFI).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart';

import '../chess/uci_engine.dart';

class StockfishTransport implements UciTransport {
  Stockfish? _sf;
  StreamSubscription<String>? _sub;
  final StreamController<String> _out = StreamController<String>.broadcast();
  Future<void>? _starting;

  @override
  Stream<String> get lines => _out.stream;

  @override
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final sf = Stockfish();
    _sf = sf;
    // wait until the native engine reports it is ready
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (sf.state.value != StockfishState.ready) {
      if (sf.state.value == StockfishState.error) throw StateError('Stockfish failed to start');
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('Stockfish did not become ready');
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    _sub = sf.stdout.listen((chunk) {
      // the plugin may deliver several lines in one chunk
      for (final line in chunk.split('\n')) {
        if (line.trim().isNotEmpty) _out.add(line);
      }
    });
  }

  @override
  void send(String command) {
    final sf = _sf;
    if (sf == null) return;
    sf.stdin = command;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    try {
      _sf?.dispose();
    } catch (e) {
      debugPrint('stockfish dispose: $e');
    }
    _sf = null;
    _starting = null;
  }
}
