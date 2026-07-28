import '../../data/repositories/auth_repository.dart';
import '../models/user_profile.dart';

class AuthUseCase {
  final AuthRepository _repository;

  AuthUseCase(this._repository);

  /// Reactive stream of the current user profile (emits null on sign-out).
  Stream<UserProfile?> authStateChanges() =>
      _repository.authStateChanges().map(_toProfile);

  Future<UserProfile?> getCurrentUser() async {
    final user = _repository.currentUser;
    return user != null ? _toProfile(user) : null;
  }

  Future<UserProfile?> signInAnonymously() {
    return _repository.signInAnonymously();
  }

  Future<UserProfile?> signInWithEmail(String email, String password) {
    return _repository.signInWithEmail(email, password);
  }

  Future<UserProfile?> createAccount(String email, String password) {
    return _repository.createAccount(email, password);
  }

  Future<UserProfile?> signInWithGoogle() {
    return _repository.signInWithGoogle();
  }

  Future<void> signOut() {
    return _repository.signOut();
  }

  UserProfile? _toProfile(user) {
    if (user == null) return null;
    return UserProfile(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoURL: user.photoURL,
      provider: user.providerData.firstOrNull?.providerId,
    );
  }
}