import 'package:flutter/material.dart';

/// Beatrice design system — mirrors the web app's visual language.
///
/// Palette extracted from the web app's CSS:
///   - Background: pure black (#000 / #070707)
///   - Surface:    #121214 (drawers), #1a1a1e (cards)
///   - Accent:     #00D4AA (teal — Beatrice brand)
///   - Green:      #a4e776 (listening / success)
///   - Cyan:       #46bec3 (speaking / secondary accent)
///   - Gradient:   #a4e776 → #46bec3 (mic button, send button)
///   - Text:       white / #888 (secondary) / #666 (muted)
class AppTheme {
  AppTheme._();

  // ── Brand colours ──────────────────────────────────────────────
  static const Color primary = Color(0xFF00D4AA);
  static const Color green = Color(0xFFa4e776);
  static const Color cyan = Color(0xFF46bec3);
  static const Color red = Color(0xFFef4444);

  // ── Surfaces ───────────────────────────────────────────────────
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF070707);
  static const Color surfaceElevated = Color(0xFF121214);
  static const Color card = Color(0xFF1a1a1e);
  static const Color cardUser = Color(0xFF232d3f);

  // ── Text ───────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textMuted = Color(0xFF666666);

  // ── Borders / dividers ─────────────────────────────────────────
  static const Color border = Color(0x20FFFFFF); // rgba(255,255,255,0.12)
  static const Color borderSubtle = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

  // ── Orb colours (matches web MainVisual) ───────────────────────
  static const Color orbCenter = Color(0xFFf7dfce);
  static const Color orbMid = Color(0xFF9e7562);
  static const Color orbOuter = Color(0xFF251814);

  /// The signature green→cyan diagonal gradient used on the mic button
  /// and send button.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green, cyan],
  );

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: cyan,
        surface: surface,
        error: red,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 24,
        ),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: textMuted, fontSize: 12),
      ),
      iconTheme: const IconThemeData(color: textPrimary, size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cyan),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? primary : textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.3)
              : const Color(0x20FFFFFF);
        }),
      ),
      dividerTheme: const DividerThemeData(color: borderSubtle, thickness: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  /// Light theme — kept for completeness but Beatrice is a dark-first app.
  static ThemeData get light => dark;
}