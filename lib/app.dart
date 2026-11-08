// App root: wires the scene, the game controller, settings and all screens together.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chess/types.dart';
import 'chess/uci_engine.dart';
import 'game/game_controller.dart';
import 'game/settings.dart';
import 'game/storage.dart';
import 'scene/board_model.dart';
import 'scene/scene_renderer.dart';
import 'scene/scene_view.dart';
import 'ui/dialogs.dart';
import 'ui/hud.dart';
import 'ui/loading.dart';
import 'ui/menu.dart';
import 'ui/theme.dart';

/// Everything the app needs from the outside world (replaced by fakes in tests).
class AppDeps {
  AppDeps({required this.model, required this.renderer, required this.engine, required this.store, required this.sfx});
  final BoardModel model;
  final SceneRenderer renderer;
  final BotEngine engine;
  final KeyValueStore store;
  final Sfx sfx;
}

class ChessApp extends StatelessWidget {
  const ChessApp({super.key, required this.deps});
  final AppDeps deps;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '3D Chess',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AppRoot(deps: deps),
      );
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.deps});
  final AppDeps deps;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  late final GameController game;
  late Settings settings;
  SavedGame? saved;
  bool ready = false;
  int done = 0, total = 13;
  String? error;
  int attempt = 0;
  bool showResult = false;
  bool _wasActive = false;
  GameStatus _lastStatus = GameStatus.playing;
  final math.Random _rnd = math.Random();

  AppDeps get d => widget.deps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    settings = Settings.decode(d.store.get(settingsKey));
    saved = GameController.loadSaved(d.store);
    game = GameController(board: d.model, engine: d.engine, store: d.store, sfx: d.sfx);
    game.applySettings(settings);
    game.addListener(_onGame);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    game.removeListener(_onGame);
    game.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) d.model.requestRender();
  }

  void _onGame() {
    final s = game.snapshot;
    // result card when a game ends; attract-mode rotation only while the menu is up
    final over = s.status != GameStatus.playing && s.active;
    if (over && (_lastStatus == GameStatus.playing || !_wasActive)) showResult = true;
    if (!over) showResult = false;
    _lastStatus = s.status;
    if (s.active != _wasActive) {
      _wasActive = s.active;
      d.model.setAutoRotate(!s.active);
    }
    if (mounted) setState(() {});
  }

  void _onSceneEvent(SceneEvent e) {
    switch (e) {
      case SceneProgress(:final done, :final total):
        setState(() {
          this.done = done;
          this.total = total;
        });
      case SceneLoaded():
        game.applySettings(settings);
        game.syncBoard();
        d.model.setAutoRotate(!game.snapshot.active);
        setState(() {
          ready = true;
          error = null;
        });
      case SceneError(:final message):
        setState(() => error = message);
    }
  }

  void _updateSettings(Settings s) {
    setState(() => settings = s);
    d.store.set(settingsKey, s.encode());
    game.applySettings(s);
  }

  void _start(Settings s) {
    final human = switch (s.humanColor) {
      HumanColor.white => Side.w,
      HumanColor.black => Side.b,
      HumanColor.random => _rnd.nextBool() ? Side.w : Side.b,
    };
    GameController.clearSaved(d.store);
    saved = null;
    game.start(GameConfig(mode: s.mode, humanColor: human, elo: s.elo));
  }

  void _resumeSaved() {
    final sv = saved;
    if (sv == null) return;
    game.start(sv.config, moves: sv.moves);
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(settings: settings, onChanged: _updateSettings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = game.snapshot;
    final active = snap.active;
    return Scaffold(
      backgroundColor: C.bg,
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900 && c.maxWidth / c.maxHeight >= 1.25;
        final panel = (active && wide && ready) ? 340.0 : 0.0;
        return Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            right: panel,
            child: SceneView(
              key: ValueKey('scene-$attempt'),
              model: d.model,
              renderer: d.renderer,
              shadows: settings.quality == Quality.high,
              onTap: game.tap,
              onEvent: _onSceneEvent,
            ),
          ),
          if (ready && !active)
            Positioned.fill(
              child: MenuScreen(
                settings: settings,
                onSettings: _updateSettings,
                saved: saved,
                hasActive: snap.history.isNotEmpty && snap.status == GameStatus.playing,
                onStart: _start,
                onContinue: game.resume,
                onResumeSaved: _resumeSaved,
                onOpenSettings: _openSettings,
              ),
            ),
          if (ready && active)
            wide
                ? Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 340,
                    child: Hud(game: game, snapshot: snap, board: d.model, onMenu: game.leave, onSettings: _openSettings, wide: true),
                  )
                : Positioned.fill(
                    child: Hud(game: game, snapshot: snap, board: d.model, onMenu: game.leave, onSettings: _openSettings),
                  ),
          if (ready && active && snap.promotion != null)
            Positioned.fill(
              child: PromotionDialog(side: snap.turn, onChoose: game.choosePromotion, onCancel: game.cancelPromotion),
            ),
          if (ready && active && showResult)
            Positioned.fill(
              child: ResultDialog(
                snapshot: snap,
                onClose: () => setState(() => showResult = false),
                onMenu: () {
                  setState(() => showResult = false);
                  game.leave();
                },
                onRematch: () {
                  setState(() => showResult = false);
                  game.start(snap.config);
                },
              ),
            ),
          if (!ready)
            Positioned.fill(
              child: LoadingScreen(
                done: done,
                total: total,
                error: error,
                onRetry: () => setState(() {
                  error = null;
                  done = 0;
                  attempt++;
                }),
              ),
            ),
        ]);
      }),
    );
  }
}
