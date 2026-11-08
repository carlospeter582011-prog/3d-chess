// In-game HUD: status bar, player cards with captured pieces, move list and control buttons.
// Narrow screens: overlays above / below the board. Wide screens: a side panel.

import 'package:flutter/material.dart';

import '../chess/types.dart';
import '../game/game_controller.dart';
import '../game/settings.dart';
import '../scene/board_scene.dart';
import 'glyphs.dart';
import 'theme.dart';

const _capturedOrder = [PT.q, PT.r, PT.b, PT.n, PT.p];

/// Material balance from [c]'s point of view (positive = ahead).
int materialBalance(GameSnapshot s, Side c) {
  int sum(List<PT> l) => l.fold(0, (a, t) => a + t.value);
  final mine = sum(s.captured[c.other]!); // what I captured = what the other side lost
  final theirs = sum(s.captured[c]!);
  return mine - theirs;
}

/// The status line shown at the top.
({String text, String tone}) statusText(GameSnapshot s) {
  final bot = s.config.mode == GameMode.bot;
  final human = s.config.humanColor;
  if (s.status != GameStatus.playing) {
    final w = s.winner?.label;
    final text = switch (s.status) {
      GameStatus.checkmate => 'Checkmate · $w wins',
      GameStatus.resigned => '${s.reason} · $w wins',
      _ => 'Draw · ${s.reason}',
    };
    return (text: text, tone: 'over');
  }
  if (s.thinking) return (text: 'Bot is thinking…', tone: 'think');
  if (s.check) {
    return (text: bot ? (s.turn == human ? 'Your king is in check!' : 'Check!') : '${s.turn.label} is in check!', tone: 'check');
  }
  if (bot) return (text: s.turn == human ? 'Your move' : '…', tone: '');
  return (text: '${s.turn.label} to move', tone: '');
}

class _Captured extends StatelessWidget {
  const _Captured({required this.lost, required this.color});
  final List<PT> lost;
  final Side color; // colour of the pieces that were lost
  @override
  Widget build(BuildContext context) {
    final sorted = [...lost]..sort((a, b) => _capturedOrder.indexOf(a).compareTo(_capturedOrder.indexOf(b)));
    return Text(
      sorted.map((t) => glyph[t]!).join(),
      style: TextStyle(
        fontSize: 20,
        height: 1,
        letterSpacing: -2,
        color: color == Side.w ? C.white : C.black,
        shadows: color == Side.w
            ? const [Shadow(blurRadius: 2, color: Colors.black)]
            : const [Shadow(blurRadius: 2, color: Color(0x8CFFFFFF))],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.s, required this.side, required this.label, this.sub});
  final GameSnapshot s;
  final Side side;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final lost = s.captured[side.other]!; // pieces this player has captured
    final diff = materialBalance(s, side);
    final active = s.status == GameStatus.playing && s.turn == side;
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? C.gold : C.line, width: active ? 1.5 : 1),
      ),
      child: Row(children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: side == Side.w ? const Color(0xFFF1DFB8) : const Color(0xFF2A1B12),
            border: Border.all(color: const Color(0x66FFFFFF)),
          ),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (sub != null) Text(sub!, style: const TextStyle(color: C.muted, fontSize: 12)),
        ]),
        const Spacer(),
        Flexible(child: _Captured(lost: lost, color: side.other)),
        if (diff > 0) ...[
          const SizedBox(width: 8),
          Text('+$diff', style: const TextStyle(color: C.ok, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ]),
    );
  }
}

class _MoveList extends StatefulWidget {
  const _MoveList({required this.history, required this.vertical});
  final List<String> history;
  final bool vertical;
  @override
  State<_MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<_MoveList> {
  final ScrollController _c = ScrollController();

  @override
  void didUpdateWidget(_MoveList old) {
    super.didUpdateWidget(old);
    if (old.history.length != widget.history.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_c.hasClients) _c.jumpTo(_c.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.history;
    final items = <Widget>[];
    for (var i = 0; i < h.length; i += 2) {
      items.add(Text.rich(
        TextSpan(children: [
          TextSpan(text: '${i ~/ 2 + 1}. ', style: const TextStyle(color: C.muted)),
          TextSpan(text: '${h[i]} ${i + 1 < h.length ? h[i + 1] : ''}'),
        ]),
        style: const TextStyle(fontSize: 14),
      ));
    }
    final empty = h.isEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
      alignment: Alignment.centerLeft,
      child: empty
          ? const Text('Moves appear here', style: TextStyle(color: C.muted))
          : widget.vertical
              ? SingleChildScrollView(controller: _c, child: Wrap(spacing: 14, runSpacing: 6, children: items))
              : SingleChildScrollView(
                  controller: _c,
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [for (final w in items) Padding(padding: const EdgeInsets.only(right: 12), child: w)]),
                ),
    );
  }
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({super.key, required this.icon, required this.label, required this.onPressed, this.on = false});
  final String icon, label;
  final VoidCallback? onPressed;
  final bool on;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Ink(
              height: 54,
              decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? C.gold : C.line)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(icon, style: TextStyle(fontSize: 19, height: 1, color: on ? C.gold2 : C.text, fontWeight: FontWeight.bold)),
                Text(label, style: const TextStyle(fontSize: 11, color: C.muted)),
              ]),
            ),
          ),
        ),
      );
}

enum ConfirmKind { resign, draw, rematch }

class Hud extends StatefulWidget {
  const Hud({
    super.key,
    required this.game,
    required this.snapshot,
    required this.board,
    required this.onMenu,
    required this.onSettings,
    this.wide = false,
  });

  final GameController game;
  final GameSnapshot snapshot;
  final BoardScene board;
  final VoidCallback onMenu, onSettings;
  final bool wide;

  @override
  State<Hud> createState() => _HudState();
}

class _HudState extends State<Hud> {
  bool topView = false;

  String _confirmTitle(ConfirmKind k) {
    final s = widget.snapshot;
    final bot = s.config.mode == GameMode.bot;
    switch (k) {
      case ConfirmKind.resign:
        return bot ? 'Resign?' : '${s.turn.label} resigns?';
      case ConfirmKind.draw:
        return 'Both players agree to a draw?';
      case ConfirmKind.rematch:
        return 'Start a rematch?';
    }
  }

  Future<void> _confirm(ConfirmKind k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: C.panelSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: C.line)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_confirmTitle(k), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false))),
              const SizedBox(width: 8),
              Expanded(child: GoldButton(key: const Key('confirm-yes'), label: 'Yes', onPressed: () => Navigator.of(ctx).pop(true))),
            ]),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    switch (k) {
      case ConfirmKind.resign:
        widget.game.resign();
      case ConfirmKind.draw:
        widget.game.agreeDraw();
      case ConfirmKind.rematch:
        widget.game.start(widget.snapshot.config);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final bot = s.config.mode == GameMode.bot;
    final human = s.config.humanColor;
    final opp = bot ? human.other : Side.b;
    final me = bot ? human : Side.w;
    final st = statusText(s);
    final over = s.status != GameStatus.playing;

    final statusBox = Expanded(
      child: Container(
        key: const Key('status'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: switch (st.tone) { 'check' => const Color(0xE6A0281C), _ => C.panel },
          gradient: st.tone == 'over' ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.gold2, C.gold]) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: st.tone == 'check' ? const Color(0x80FF7864) : (st.tone == 'over' ? Colors.transparent : C.line)),
        ),
        child: Text(
          st.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: switch (st.tone) { 'check' => Colors.white, 'over' => C.onGold, 'think' => C.gold2, _ => C.text },
          ),
        ),
      ),
    );

    final top = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        GlassIconButton(icon: '☰', tooltip: 'Menu', onPressed: widget.onMenu),
        const SizedBox(width: 8),
        statusBox,
        const SizedBox(width: 8),
        GlassIconButton(icon: '⚙', tooltip: 'Settings', onPressed: widget.onSettings),
      ]),
      const SizedBox(height: 8),
      _PlayerCard(
        s: s,
        side: opp,
        label: bot ? 'Bot · ${s.config.elo}' : opp.label,
        sub: bot ? opp.label : null,
      ),
      const SizedBox(height: 8),
      if (widget.wide) Flexible(child: _MoveList(history: s.history, vertical: true)) else _MoveList(history: s.history, vertical: false),
    ]);

    final controls = Row(children: [
      for (final w in <Widget>[
        _CtrlButton(key: const Key('btn-undo'), icon: '↶', label: 'Undo', onPressed: s.canUndo ? widget.game.undo : null),
        _CtrlButton(key: const Key('btn-flip'), icon: '⟳', label: 'Flip', onPressed: widget.board.flipView),
        _CtrlButton(
          key: const Key('btn-top'),
          icon: '⬒',
          label: 'Top',
          on: topView,
          onPressed: () {
            final next = !topView;
            setState(() => topView = next);
            widget.board.resetCamera(animate: true, side: widget.board.viewSide(), top: next);
          },
        ),
        _CtrlButton(
          key: const Key('btn-reset'),
          icon: '◎',
          label: 'Reset',
          onPressed: () {
            setState(() => topView = false);
            widget.board.resetCamera(animate: true, side: bot ? human : widget.board.viewSide());
          },
        ),
        if (over)
          _CtrlButton(key: const Key('btn-rematch'), icon: '♻', label: 'Rematch', onPressed: () => _confirm(ConfirmKind.rematch))
        else if (bot)
          _CtrlButton(key: const Key('btn-resign'), icon: '⚑', label: 'Resign', onPressed: () => _confirm(ConfirmKind.resign))
        else ...[
          _CtrlButton(key: const Key('btn-draw'), icon: '½', label: 'Draw', onPressed: () => _confirm(ConfirmKind.draw)),
          _CtrlButton(key: const Key('btn-resign'), icon: '⚑', label: 'Resign', onPressed: () => _confirm(ConfirmKind.resign)),
        ],
      ])
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: w)),
    ]);

    final bottom = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PlayerCard(s: s, side: me, label: bot ? 'You' : me.label, sub: bot ? me.label : null),
      const SizedBox(height: 8),
      controls,
    ]);

    if (widget.wide) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1C1510), Color(0xFF120D09)]),
          border: Border(left: BorderSide(color: C.line)),
        ),
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(children: [
            Expanded(child: top),
            const SizedBox(height: 12),
            bottom,
          ]),
        ),
      );
    }

    // narrow: overlays; the gap in the middle lets touches reach the board
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [top, bottom]),
      ),
    );
  }
}
