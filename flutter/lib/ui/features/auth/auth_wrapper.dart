import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/auth_viewmodel.dart';
import 'splash_screen.dart';
import 'auth_page.dart';
import '../chat/chat_screen.dart';

/// Root gate. Boots [AuthViewModel.initialize] once, then reacts to auth
/// state changes (splash → auth page → chat) instead of swapping screens via
/// imperative navigation.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Bootstrap auth on first mount (idempotent inside the view-model).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthViewModel>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();

    if (authViewModel.isLoading) {
      return const SplashScreen();
    }

    if (authViewModel.isAuthenticated) {
      return const ChatScreen();
    }

    return const AuthPage();
  }
}