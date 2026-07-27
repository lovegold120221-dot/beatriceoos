import '../../data/repositories/auth_repository.dart';
import '../models/user_profile.dart';

class AuthUseCase {
  final AuthRepository _repository;

  AuthUseCase(this._repository);

  Future<UserProfile?> getCurrentUser() async {
    return _repository.currentUser != null
        ? UserProfile(
            uid: _repository.currentUser!.uid,
            email: _repository.currentUser!.email,
            displayName: _repository.currentUser!.displayName,
            photoURL: _repository.currentUser!.photoURL,
            provider: _repository.currentUser!.providerData.firstOrNull?.providerId,
          )
        : null;
  }

  Future<UserProfile?> signInAnonymously() async {
    return _repository.signInAnonymously();
  }

  Future<UserProfile?> signInWithEmail(String email, String password) async {
    return _repository.signInWithEmail(email, password);
  }

  Future<UserProfile?> createAccount(String email, String password) async {
    return _repository.createAccount(email, password);
  }

  Future<UserProfile?> signInWithGoogle() async {
    return _repository.signInWithGoogle();
  }

  Future<void> signOut() async {
    return _repository.signOut();
  }
}