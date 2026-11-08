// Promotion picker, result card and settings dialog.

import 'package:flutter/material.dart';

import '../chess/types.dart';
import '../game/game_controller.dart';
import '../game/settings.dart';
import 'glyphs.dart';
import 'theme.dart';

const _promoNames = {PT.q: 'Queen', PT.r: 'Rook', PT.b: 'Bishop', PT.n: 'Knight'};

class PromotionDialog extends StatelessWidget {
  const PromotionDialog({super.key, required this.side, required this.onChoose, required this.onCancel});
  final Side side;
  final ValueChanged<PT> onChoose;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ModalCard(
        onDismiss: onCancel,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Promote pawn to…', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 14),
          Row(children: [
            for (final t in const [PT.q, PT.r, PT.b, PT.n])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    key: Key('promo-${t.ch}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChoose(t),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x0FFFFFFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.line),
                      ),
                      child: Column(children: [
                        Text(glyph[t]!,
                            style: TextStyle(
                              fontSize: 44,
                              height: 1.1,
                              color: side == Side.w ? C.white : C.black,
                              shadows: side == Side.w
                                  ? const [Shadow(blurRadius: 2, color: Colors.black)]
                                  : const [Shadow(blurRadius: 2, color: Color(0x8CFFFFFF))],
                            )),
                        Text(_promoNames[t]!, style: const TextStyle(color: C.muted, fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      );
}

String resultTitle(GameSnapshot s) {
  if (s.winner == null) return 'Draw';
  if (s.config.mode == GameMode.bot) return s.winner == s.config.humanColor ? 'You win! \u{1F389}' : 'Bot wins';
  return '${s.winner!.label} wins!';
}

class ResultDialog extends StatelessWidget {
  const ResultDialog({super.key, required this.snapshot, required this.onRematch, required this.onMenu, required this.onClose});
  final GameSnapshot snapshot;
  final VoidCallback onRematch, onMenu, onClose;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final moves = s.history.isEmpty ? '' : ' · ${(s.history.length / 2).ceil()} moves';
    return ModalCard(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(resultTitle(s), key: const Key('result-title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, color: C.gold2)),
        const SizedBox(height: 14),
        Text('${s.reason}$moves', textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: GhostButton(label: 'View board', onPressed: onClose)),
          const SizedBox(width: 8),
          Expanded(child: GhostButton(label: 'Menu', onPressed: onMenu)),
          const SizedBox(width: 8),
          Expanded(child: GoldButton(key: const Key('rematch'), label: 'Rematch', onPressed: onRematch)),
        ]),
      ]),
    );
  }
}

/// Settings sheet. Changes apply immediately through [onChanged].
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.settings, required this.onChanged});
  final Settings settings;
  final ValueChanged<Settings> onChanged;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late Settings s = widget.settings;

  void _set(Settings n) {
    setState(() => s = n);
    widget.onChanged(n);
  }

  Widget _toggle(Key key, String label, String? hint, bool value, ValueChanged<bool> on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (hint != null) Text(hint, style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          Switch(key: key, value: value, onChanged: on),
        ]),
      );

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: C.panelSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: C.line)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Settings', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
              const SizedBox(height: 10),
              _toggle(const Key('set-sound'), 'Sound effects', null, s.sound, (v) => _set(s.copyWith(sound: v))),
              _toggle(const Key('set-labels'), 'Board coordinates', 'a–h and 1–8 around the board', s.labels, (v) => _set(s.copyWith(labels: v))),
              _toggle(const Key('set-flip'), 'Auto-turn view (2 players)', 'Rotates the camera to whoever moves next', s.autoFlip,
                  (v) => _set(s.copyWith(autoFlip: v))),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Graphics', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Low turns off shadows (faster on old phones)', style: TextStyle(color: C.muted, fontSize: 12)),
                    ]),
                  ),
                  DropdownButton<Quality>(
                    key: const Key('set-quality'),
                    value: s.quality,
                    dropdownColor: const Color(0xFF2A2018),
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: Quality.high, child: Text('High')),
                      DropdownMenuItem(value: Quality.low, child: Text('Low')),
                    ],
                    onChanged: (q) {
                      if (q != null) _set(s.copyWith(quality: q));
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              const Text('Drag to orbit · two fingers to pan and zoom.', style: TextStyle(color: C.muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              GoldButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
        ),
      );
}
