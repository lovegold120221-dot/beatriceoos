import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'ui/viewmodels/auth_viewmodel.dart';
import 'ui/features/auth/auth_wrapper.dart';
import 'ui/features/chat/chat_screen.dart';
import 'ui/features/settings/settings_screen.dart';
import 'ui/features/profile/profile_screen.dart';

class AppRouter {
  AppRouter._();

  static GoRouter get router => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AuthWrapper(),
        routes: [
          GoRoute(
            path: 'chat',
            builder: (context, state) => const ChatScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
}