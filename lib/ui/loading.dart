import 'package:flutter/material.dart';

import 'theme.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, required this.done, required this.total, required this.error, required this.onRetry});
  final int done, total;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -0.3), radius: 1.1, colors: [Color(0xFF2B2118), Color(0xFF0D0A07)])),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/icon/icon.png', width: 96, height: 96)),
          const SizedBox(height: 14),
          const Text('3D Chess', style: TextStyle(fontSize: 32, color: C.gold2)),
          const SizedBox(height: 14),
          if (error != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(error!, key: const Key('load-error'), textAlign: TextAlign.center, style: const TextStyle(color: C.bad)),
            ),
            const SizedBox(height: 14),
            SizedBox(width: 160, child: GoldButton(label: 'Try again', onPressed: onRetry)),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                width: 280,
                height: 8,
                child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, backgroundColor: const Color(0x1AFFFFFF), color: C.gold),
              ),
            ),
            const SizedBox(height: 10),
            Text('Loading 3D pieces… $done/$total', key: const Key('load-text')),
          ],
        ]),
      );
}
