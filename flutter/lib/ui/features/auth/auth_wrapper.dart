import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/auth_viewmodel.dart';
import 'splash_screen.dart';
import 'auth_page.dart';
import '../chat/chat_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

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