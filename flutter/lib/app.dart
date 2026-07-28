import 'package:flutter/material.dart';
import 'ui/features/auth/auth_wrapper.dart';
import 'ui/features/chat/chat_screen.dart';
import 'ui/features/settings/settings_screen.dart';
import 'ui/features/profile/profile_screen.dart';

class AppRouter {
  AppRouter._();

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const AuthWrapper());
      case '/chat':
        return MaterialPageRoute(builder: (_) => const ChatScreen());
      case '/settings':
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case '/profile':
        return MaterialPageRoute(builder: (_) => const ProfileScreen());
      default:
        return MaterialPageRoute(builder: (_) => const AuthWrapper());
    }
  }
}