import 'package:flutter/material.dart';
import '../../domain/use_cases/auth_use_case.dart';
import '../../domain/models/user_profile.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthUseCase _authUseCase;

  AuthViewModel(this._authUseCase);

  UserProfile? _user;
  bool _isLoading = true;
  bool _isAuthenticated = false;

  UserProfile? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    final user = await _authUseCase.getCurrentUser();
    _user = user;
    _isAuthenticated = user != null;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> signInAnonymously() async {
    _isLoading = true;
    notifyListeners();

    final user = await _authUseCase.signInAnonymously();
    _user = user;
    _isAuthenticated = user != null;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    await _authUseCase.signOut();
    _user = null;
    _isAuthenticated = false;
    _isLoading = false;
    notifyListeners();
  }
}