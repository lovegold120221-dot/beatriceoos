import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/auth_viewmodel.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    return regex.hasMatch(email);
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final authViewModel = context.read<AuthViewModel>();

    if (_isSignUp) {
      await authViewModel.createAccount(email, password);
    } else {
      await authViewModel.signInWithEmail(email, password);
    }
    // No manual navigation: AuthWrapper reacts to auth state and swaps us out.
  }

  Future<void> _handleGuest() async {
    await context.read<AuthViewModel>().signInAnonymously();
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final busy = authViewModel.isBusy;
    final error = authViewModel.errorMessage;

    return Scaffold(
      backgroundColor: const Color(0xFF070707),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic,
                      size: 64, color: Colors.white.withValues(alpha: 0.8)),
                  const SizedBox(height: 16),
                  const Text(
                    'Beatrice',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sign in to continue',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 2,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (error != null && error.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(error,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                      hintText: 'you@example.com',
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'Enter your email';
                      if (!_isValidEmail(v)) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                      hintText: '••••••••',
                    ),
                    validator: (value) {
                      final v = value ?? '';
                      if (v.isEmpty) return 'Enter your password';
                      if (v.length < 6) return 'At least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: busy ? null : _handleSubmit,
                      child: busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              _isSignUp ? 'Create Account' : 'Sign In',
                              style: const TextStyle(fontSize: 14),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: busy ? null : _handleGuest,
                    child: const Text(
                      'Continue as guest',
                      style: TextStyle(color: Color(0xFF00D4AA), fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Already have an account? '
                            : "Don't have an account? ",
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                        child: Text(
                          _isSignUp ? 'Sign In' : 'Sign Up',
                          style: const TextStyle(
                              color: Color(0xFF00D4AA), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}