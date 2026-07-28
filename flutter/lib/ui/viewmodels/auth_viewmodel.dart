import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logger.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/use_cases/auth_use_case.dart';

/// Holds authentication state and reacts to Firebase auth changes.
///
/// Previously `initialize()` was never called and `isLoading` defaulted to
/// `true`, so the app was stuck on the splash screen forever. Now
/// `AuthWrapper` calls [initialize] on mount, `isLoading` starts `false`, and
/// a subscription to [AuthUseCase.authStateChanges] keeps state reactive.
class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._authUseCase);

  final AuthUseCase _authUseCase;
  StreamSubscription<UserProfile?>? _authSub;

  UserProfile? _user;
  bool _isLoading = false; // bootstrap only — true while initialize() runs
  bool _isBusy = false; // true while a sign-in/sign-up/sign-out action runs
  bool _isAuthenticated = false;
  String? _errorMessage;

  UserProfile? get user => _user;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;

  /// Bootstrap auth state. Subscribe to the auth stream so future sign-in /
  /// sign-out events are reflected automatically, then resolve the current
  /// user. Safe to call multiple times.
  Future<void> initialize() async {
    if (_authSub != null) return;
    _isLoading = true;
    notifyListeners();

    _authSub = _authUseCase.authStateChanges().listen(
      _onAuthChanged,
      onError: (Object error, StackTrace stack) {
        appLogger.w('Auth stream error', error: error, stackTrace: stack);
      },
    );

    try {
      final user = await _authUseCase.getCurrentUser();
      _onAuthChanged(user);
    } catch (e, s) {
      appLogger.w('Auth initialize failed', error: e, stackTrace: s);
      _errorMessage = _humanize(e);
      _isLoading = false;
      notifyListeners();
    }
  }

  void _onAuthChanged(UserProfile? user) {
    _user = user;
    _isAuthenticated = user != null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> signInAnonymously() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final user = await _authUseCase.signInAnonymously();
      _onAuthChanged(user);
      return user != null;
    } catch (e, s) {
      appLogger.w('signInAnonymously failed', error: e, stackTrace: s);
      _errorMessage = _humanize(e);
      _isBusy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signInWithEmail(String email, String password) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final user = await _authUseCase.signInWithEmail(email, password);
      _onAuthChanged(user);
      return user != null;
    } catch (e, s) {
      appLogger.w('signInWithEmail failed', error: e, stackTrace: s);
      _errorMessage = _humanize(e);
      _isBusy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> createAccount(String email, String password) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final user = await _authUseCase.createAccount(email, password);
      _onAuthChanged(user);
      return user != null;
    } catch (e, s) {
      appLogger.w('createAccount failed', error: e, stackTrace: s);
      _errorMessage = _humanize(e);
      _isBusy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _authUseCase.signOut();
    } catch (e, s) {
      appLogger.w('signOut failed', error: e, stackTrace: s);
      _errorMessage = _humanize(e);
      notifyListeners();
      return;
    }
    _onAuthChanged(null);
  }

  /// Turn a raw exception into a short user-facing message.
  String _humanize(Object error) {
    final text = error.toString();
    // Trim common Dart/Firebase prefixes for a cleaner UI message.
    final cleaned = text.replaceFirst(RegExp(r'^\[?\w*Exception\]?\s*'), '').trim();
    return cleaned.isEmpty ? 'Something went wrong. Please try again.' : cleaned;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}