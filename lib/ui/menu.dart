// Main menu: mode, colour, bot strength, start / continue.

import 'package:flutter/material.dart';

import '../chess/elo.dart';
import '../game/game_controller.dart';
import '../game/settings.dart';
import 'theme.dart';

const List<int> eloPresets = [400, 800, 1200, 1600, 2000, 2400, 2800, 3200];

class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.settings,
    required this.onSettings,
    required this.saved,
    required this.hasActive,
    required this.onStart,
    required this.onContinue,
    required this.onResumeSaved,
    required this.onOpenSettings,
  });

  final Settings settings;
  final ValueChanged<Settings> onSettings;
  final SavedGame? saved;
  final bool hasActive;
  final void Function(Settings settings) onStart;
  final VoidCallback onContinue;
  final VoidCallback onResumeSaved;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final bot = settings.mode == GameMode.bot;
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.4), radius: 1.1, colors: [Color(0x5914100D), Color(0xCC0A0806)]),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: C.panel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: C.line),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 20))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset('assets/icon/icon.png', width: 64, height: 64),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('3D Chess', style: TextStyle(fontSize: 28, color: C.gold2, letterSpacing: 0.3)),
                        Text('Staunton set · works offline', style: TextStyle(color: C.muted, fontSize: 13)),
                      ]),
                    ),
                    GlassIconButton(icon: '⚙', tooltip: 'Settings', onPressed: onOpenSettings),
                  ]),
                  const SizedBox(height: 16),
                  _Seg(
                    key: const Key('mode-seg'),
                    items: const [('\u{1F916} Play the bot', GameMode.bot), ('\u{1F465} 2 players · 1 device', GameMode.local)],
                    value: settings.mode,
                    onChanged: (m) => onSettings(settings.copyWith(mode: m)),
                  ),
                  const SizedBox(height: 16),
                  if (bot) ...[
                    const _Heading('Your colour'),
                    const SizedBox(height: 8),
                    _Seg(
                      key: const Key('color-seg'),
                      small: true,
                      items: const [
                        ('♔ White', HumanColor.white),
                        ('\u{1F3B2} Random', HumanColor.random),
                        ('♚ Black', HumanColor.black),
                      ],
                      value: settings.humanColor,
                      onChanged: (c) => onSettings(settings.copyWith(humanColor: c)),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(child: _Heading('Bot strength')),
                      Text('${settings.elo} Elo', key: const Key('elo-label'), style: const TextStyle(color: C.gold2, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(eloName(settings.elo), overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 13)),
                      ),
                    ]),
                    Slider(
                      key: const Key('elo-slider'),
                      min: eloMin.toDouble(),
                      max: eloMax.toDouble(),
                      divisions: (eloMax - eloMin) ~/ 50,
                      value: settings.elo.clamp(eloMin, eloMax).toDouble(),
                      onChanged: (v) => onSettings(settings.copyWith(elo: v.round())),
                    ),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in eloPresets)
                        InkWell(
                          key: Key('elo-$e'),
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSettings(settings.copyWith(elo: e)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: (settings.elo - e).abs() < 25 ? C.gold : C.line),
                            ),
                            child: Text('$e', style: TextStyle(fontSize: 13, color: (settings.elo - e).abs() < 25 ? C.gold2 : C.muted)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Stockfish runs on your device. Elo is approximate.', style: TextStyle(color: C.muted, fontSize: 12.5)),
                  ] else
                    const Text(
                      'Pass the phone or tablet back and forth — no internet needed. Turn on “Auto-turn view” in settings to spin the board to the player whose turn it is.',
                      style: TextStyle(color: C.muted, fontSize: 14, height: 1.4),
                    ),
                  const SizedBox(height: 16),
                  GoldButton(key: const Key('start'), label: '▶ Start new game', onPressed: () => onStart(settings)),
                  if (!hasActive && saved != null) ...[
                    const SizedBox(height: 10),
                    GhostButton(
                      key: const Key('resume-saved'),
                      label: '↺ Continue saved game (${saved!.config.mode == GameMode.bot ? 'bot ${saved!.config.elo}' : '2 players'})',
                      onPressed: onResumeSaved,
                    ),
                  ],
                  if (hasActive) ...[
                    const SizedBox(height: 10),
                    GhostButton(key: const Key('continue'), label: '↺ Back to current game', onPressed: onContinue),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: const TextStyle(fontSize: 13, letterSpacing: 1, color: C.muted, fontWeight: FontWeight.w600));
}

class _Seg<T> extends StatelessWidget {
  const _Seg({super.key, required this.items, required this.value, required this.onChanged, this.small = false});
  final List<(String, T)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0x59000000), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (final (label, v) in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(v),
                child: Ink(
                  padding: EdgeInsets.symmetric(vertical: small ? 10 : 12, horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: v == value ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.gold2, C.gold]) : null,
                  ),
                  child: Center(
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: v == value ? C.onGold : C.muted)),
                  ),
                ),
              ),
            ),
        ]),
      );
}
