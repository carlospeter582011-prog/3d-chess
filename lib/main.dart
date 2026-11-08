import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'chess/uci_engine.dart';
import 'platform/native_services.dart';
import 'platform/stockfish_transport.dart';
import 'scene/board_model.dart';
import 'scene/scene_renderer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final store = ChannelStore();
  await store.load();
  final sfx = ChannelSfx();
  unawaited(sfx.init());
  runApp(ChessApp(
    deps: AppDeps(
      model: BoardModel(),
      renderer: ChannelSceneRenderer(),
      engine: UciEngine(StockfishTransport()),
      store: store,
      sfx: sfx,
    ),
  ));
}
