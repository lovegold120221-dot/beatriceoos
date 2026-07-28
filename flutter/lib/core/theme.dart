import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _primary = Color(0xFF4F46E5);
  static const Color _surface = Color(0xFF1A1A2E);
  static const Color _surfaceLight = Color(0xFF16213E);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFF94A3B8);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: _surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 24,
        ),
        bodyLarge: TextStyle(
          color: _textPrimary,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: _textSecondary,
          fontSize: 14,
        ),
      ),
      iconTheme: const IconThemeData(color: _textPrimary, size: 24),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: _textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _surfaceLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: _textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: _surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 24,
        ),
        bodyLarge: TextStyle(
          color: _textPrimary,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: _textSecondary,
          fontSize: 14,
        ),
      ),
      iconTheme: const IconThemeData(color: _textPrimary, size: 24),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: _textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _surfaceLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: _textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
