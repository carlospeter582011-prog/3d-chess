// Menu, HUD and dialogs as widgets.

import 'package:chess3d/chess/types.dart';
import 'package:chess3d/chess/uci_engine.dart';
import 'package:chess3d/game/game_controller.dart';
import 'package:chess3d/game/settings.dart';
import 'package:chess3d/game/storage.dart';
import 'package:chess3d/scene/board_model.dart';
import 'package:chess3d/ui/dialogs.dart';
import 'package:chess3d/ui/hud.dart';
import 'package:chess3d/ui/menu.dart';
import 'package:chess3d/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoEngine implements BotEngine {
  @override
  Future<String?> bestMove(String fen, int elo) async => null;
  @override
  void stop() {}
  @override
  void resetGame() {}
  @override
  void dispose() {}
}

GameController newGame() => GameController(
      board: BoardModel()..animations = false,
      engine: _NoEngine(),
      store: MemoryStore(),
      sfx: SilentSfx(),
      thinkMinimum: Duration.zero,
    );

Widget host(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: child));

void useTallScreen(WidgetTester t) {
  t.view.physicalSize = const Size(450, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  group('Menu', () {
    Widget menu({
      required ValueNotifier<Settings> settings,
      required List<Settings> started,
      SavedGame? saved,
      bool hasActive = false,
      VoidCallback? onContinue,
      VoidCallback? onResumeSaved,
    }) =>
        host(ValueListenableBuilder<Settings>(
          valueListenable: settings,
          builder: (_, s, __) => MenuScreen(
            settings: s,
            onSettings: (n) => settings.value = n,
            saved: saved,
            hasActive: hasActive,
            onStart: started.add,
            onContinue: onContinue ?? () {},
            onResumeSaved: onResumeSaved ?? () {},
            onOpenSettings: () {},
          ),
        ));

    testWidgets('shows bot options by default and starts with the chosen settings', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      final started = <Settings>[];
      await t.pumpWidget(menu(settings: settings, started: started));
      expect(find.text('3D Chess'), findsOneWidget);
      expect(find.byKey(const Key('elo-slider')), findsOneWidget);
      expect(find.text('1200 Elo'), findsOneWidget);
      await t.tap(find.byKey(const Key('elo-2000')));
      await t.pump();
      expect(find.text('2000 Elo'), findsOneWidget);
      await t.tap(find.text('♚ Black'));
      await t.pump();
      await t.tap(find.byKey(const Key('start')));
      expect(started.single.elo, 2000);
      expect(started.single.humanColor, HumanColor.black);
      expect(started.single.mode, GameMode.bot);
    });

    testWidgets('2 players hides the bot strength controls', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      await t.pumpWidget(menu(settings: settings, started: []));
      await t.tap(find.textContaining('2 players'));
      await t.pump();
      expect(settings.value.mode, GameMode.local);
      expect(find.byKey(const Key('elo-slider')), findsNothing);
      expect(find.byKey(const Key('color-seg')), findsNothing);
    });

    testWidgets('slider changes the Elo within 400..3200', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      await t.pumpWidget(menu(settings: settings, started: []));
      final slider = find.byKey(const Key('elo-slider'));
      await t.drag(slider, const Offset(-2000, 0));
      await t.pump();
      expect(settings.value.elo, 400);
      await t.drag(slider, const Offset(4000, 0));
      await t.pump();
      expect(settings.value.elo, 3200);
    });

    testWidgets('a saved game offers to continue; an active game offers to go back', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      var resumed = 0, continued = 0;
      await t.pumpWidget(menu(
        settings: settings,
        started: [],
        saved: const SavedGame(GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1500), ['e2e4']),
        onResumeSaved: () => resumed++,
      ));
      expect(find.byKey(const Key('resume-saved')), findsOneWidget);
      await t.tap(find.byKey(const Key('resume-saved')));
      expect(resumed, 1);

      await t.pumpWidget(menu(settings: settings, started: [], hasActive: true, onContinue: () => continued++));
      expect(find.byKey(const Key('resume-saved')), findsNothing);
      await t.tap(find.byKey(const Key('continue')));
      expect(continued, 1);
    });

    testWidgets('no continue buttons on a fresh install', (t) async {
      useTallScreen(t);
      await t.pumpWidget(menu(settings: ValueNotifier(const Settings()), started: []));
      expect(find.byKey(const Key('resume-saved')), findsNothing);
      expect(find.byKey(const Key('continue')), findsNothing);
    });
  });

  group('HUD helpers', () {
    test('status text', () {
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1200));
      expect(statusText(g.snapshot).text, 'Your move');
      final g2 = newGame();
      g2.start(const GameConfig(mode: GameMode.local));
      expect(statusText(g2.snapshot).text, 'White to move');
      g2.debugLoadFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(statusText(g2.snapshot).text, 'Draw · Stalemate');
      g2.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      expect(statusText(g2.snapshot).text, 'Checkmate · White wins');
      g2.debugLoadFen('4k3/8/8/8/8/8/4r3/R3K3 w - - 0 1');
      expect(statusText(g2.snapshot).tone, 'check');
      expect(statusText(g2.snapshot).text, 'White is in check!');
    });

    test('material balance counts captured piece values', () async {
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      g.debugLoadFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      expect(materialBalance(g.snapshot, Side.w), 0);
      g.tap('e2');
      g.tap('e4');
      await Future<void>.delayed(Duration.zero);
      g.tap('d7');
      g.tap('d5');
      await Future<void>.delayed(Duration.zero);
      g.tap('e4');
      g.tap('d5');
      await Future<void>.delayed(Duration.zero);
      expect(materialBalance(g.snapshot, Side.w), 1);
      expect(materialBalance(g.snapshot, Side.b), -1);
    });
  });

  group('HUD', () {
    Widget hud(GameController g, {VoidCallback? onMenu}) => host(ListenableBuilder(
          listenable: g,
          builder: (_, __) => Hud(
            game: g,
            snapshot: g.snapshot,
            board: g.board,
            onMenu: onMenu ?? () {},
            onSettings: () {},
          ),
        ));

    testWidgets('shows the status, both players and the move list', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1800));
      await t.pumpWidget(hud(g));
      expect(find.text('Your move'), findsOneWidget);
      expect(find.text('Bot · 1800'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Moves appear here'), findsOneWidget);
      g.tap('e2');
      g.tap('e4');
      await t.pump();
      await t.pump();
      expect(find.textContaining('1. e4'), findsOneWidget);
    });

    testWidgets('undo is disabled at the start', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      await t.pumpWidget(hud(g));
      expect(g.snapshot.canUndo, isFalse);
      g.tap('e2');
      g.tap('e4');
      await t.pump();
      await t.pump();
      expect(g.snapshot.canUndo, isTrue);
      await t.tap(find.byKey(const Key('btn-undo')));
      await t.pump();
      expect(g.snapshot.history, isEmpty);
    });

    testWidgets('resign asks for confirmation and then ends the game', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1200));
      await t.pumpWidget(hud(g));
      await t.tap(find.byKey(const Key('btn-resign')));
      await t.pumpAndSettle();
      expect(find.text('Resign?'), findsOneWidget);
      expect(g.snapshot.status, GameStatus.playing);
      await t.tap(find.byKey(const Key('confirm-yes')));
      await t.pumpAndSettle();
      expect(g.snapshot.status, GameStatus.resigned);
      expect(find.textContaining('Black wins'), findsOneWidget);
    });

    testWidgets('2 players has draw and resign buttons; menu button calls back', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      var menu = 0;
      await t.pumpWidget(hud(g, onMenu: () => menu++));
      expect(find.byKey(const Key('btn-draw')), findsOneWidget);
      expect(find.byKey(const Key('btn-resign')), findsOneWidget);
      await t.tap(find.byTooltip('Menu'));
      expect(menu, 1);
    });

    testWidgets('flip button turns the camera to the other side', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      await t.pumpWidget(hud(g));
      expect(g.board.viewSide(), Side.w);
      await t.tap(find.byKey(const Key('btn-flip')));
      expect(g.board.viewSide(), Side.b);
    });

    testWidgets('after the game the rematch button replaces resign', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      g.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      await t.pumpWidget(hud(g));
      expect(find.byKey(const Key('btn-rematch')), findsOneWidget);
      expect(find.byKey(const Key('btn-resign')), findsNothing);
    });

    testWidgets('wide layout renders without overflow', (t) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      await t.pumpWidget(host(Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 340,
          child: ListenableBuilder(
            listenable: g,
            builder: (_, __) => Hud(game: g, snapshot: g.snapshot, board: g.board, onMenu: () {}, onSettings: () {}, wide: true),
          ),
        ),
      )));
      expect(t.takeException(), isNull);
    });
  });

  group('dialogs', () {
    testWidgets('promotion picker offers queen, rook, bishop, knight', (t) async {
      useTallScreen(t);
      PT? chosen;
      await t.pumpWidget(host(PromotionDialog(side: Side.w, onChoose: (p) => chosen = p, onCancel: () {})));
      for (final k in ['q', 'r', 'b', 'n']) {
        expect(find.byKey(Key('promo-$k')), findsOneWidget);
      }
      expect(find.byKey(const Key('promo-k')), findsNothing);
      expect(find.byKey(const Key('promo-p')), findsNothing);
      await t.tap(find.byKey(const Key('promo-n')));
      expect(chosen, PT.n);
    });

    test('result titles', () async {
      final bot = newGame()..start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1200));
      bot.resign();
      expect(resultTitle(bot.snapshot), 'Bot wins');
      final local = newGame()..start(const GameConfig(mode: GameMode.local));
      local.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      expect(resultTitle(local.snapshot), 'White wins!');
      local.debugLoadFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(resultTitle(local.snapshot), 'Draw');
    });

    testWidgets('result dialog buttons', (t) async {
      useTallScreen(t);
      final g = newGame()..start(const GameConfig(mode: GameMode.local));
      g.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      var rematch = 0, menu = 0, close = 0;
      await t.pumpWidget(host(ResultDialog(snapshot: g.snapshot, onRematch: () => rematch++, onMenu: () => menu++, onClose: () => close++)));
      expect(find.text('White wins!'), findsOneWidget);
      await t.tap(find.byKey(const Key('rematch')));
      await t.tap(find.text('Menu'));
      await t.tap(find.text('View board'));
      expect([rematch, menu, close], [1, 1, 1]);
    });

    testWidgets('settings dialog reports changes immediately', (t) async {
      useTallScreen(t);
      var current = const Settings();
      await t.pumpWidget(host(SettingsDialog(settings: current, onChanged: (s) => current = s)));
      await t.tap(find.byKey(const Key('set-sound')));
      await t.pump();
      expect(current.sound, isFalse);
      await t.tap(find.byKey(const Key('set-labels')));
      await t.pump();
      expect(current.labels, isFalse);
      await t.tap(find.byKey(const Key('set-flip')));
      await t.pump();
      expect(current.autoFlip, isTrue);
    });
  });
}

