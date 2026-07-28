import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Splash screen matching the web app: pure black background, mic icon,
/// "Beatrice" title, "Powered by Eburon AI" subtitle.
class SplashScreen extends StatelessWidget {
  final VoidCallback? onReady;

  const SplashScreen({super.key, this.onReady});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none_rounded,
                size: 80, color: AppTheme.textPrimary.withValues(alpha: 0.8)),
            const SizedBox(height: 24),
            const Text(
              'Beatrice',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'POWERED BY EBURON AI',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}