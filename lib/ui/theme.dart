// Colours and small shared widgets, matching the look of the web version (dark wood + gold).

import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF14100D);
  static const panel = Color(0xD61A140F); // rgba(26,20,15,.84)
  static const panelSolid = Color(0xFF1D1610);
  static const line = Color(0x24FFE2AA); // rgba(255,226,170,.14)
  static const gold = Color(0xFFE3B45E);
  static const gold2 = Color(0xFFF3D08A);
  static const text = Color(0xFFF4EAD8);
  static const muted = Color(0xFFA99B83);
  static const ok = Color(0xFF5FCF8E);
  static const bad = Color(0xFFEF6A52);
  static const onGold = Color(0xFF1A1208);
  static const white = Color(0xFFF6E9C8);
  static const black = Color(0xFF3A2619);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(primary: C.gold, secondary: C.gold2, surface: C.panelSolid, error: C.bad),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    sliderTheme: const SliderThemeData(activeTrackColor: C.gold, thumbColor: C.gold, inactiveTrackColor: Color(0x33FFFFFF)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.gold : const Color(0xFF3A2F25)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

/// Frosted dark panel.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.radius = 12, this.borderColor, this.fill});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? borderColor;
  final Color? fill;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: fill ?? C.panel,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor ?? C.line),
        ),
        child: child,
      );
}

class GoldButton extends StatelessWidget {
  const GoldButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.gold2, C.gold]),
                boxShadow: const [BoxShadow(color: Color(0x40E3B45E), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Center(child: Text(label, style: const TextStyle(color: C.onGold, fontWeight: FontWeight.w700, fontSize: 16))),
            ),
          ),
        ),
      );
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0x0DFFFFFF),
                border: Border.all(color: C.line),
              ),
              child: Center(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            ),
          ),
        ),
      );
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip});
  final String icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
              child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
            ),
          ),
        ),
      );
}

/// Dark modal card with a scrim; used for result / promotion overlays.
class ModalCard extends StatelessWidget {
  const ModalCard({super.key, required this.child, this.onDismiss});
  final Widget child;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Container(
          color: const Color(0x8C000000),
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: C.panelSolid,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: C.line),
                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 20))],
                ),
                child: Material(color: Colors.transparent, child: child),
              ),
            ),
          ),
        ),
      );
}
