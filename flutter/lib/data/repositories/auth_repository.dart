import 'package:firebase_auth/firebase_auth.dart';
import '../../domain/models/user_profile.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserProfile?> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    final user = credential.user;
    if (user == null) return null;
    return UserProfile(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoURL: user.photoURL,
      provider: user.providerData.firstOrNull?.providerId,
    );
  }

  Future<UserProfile?> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) return null;
    return _toProfile(user);
  }

  Future<UserProfile?> createAccount(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) return null;
    return _toProfile(user);
  }

  Future<UserProfile?> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    final credential = await _auth.signInWithPopup(provider);
    final user = credential.user;
    if (user == null) return null;
    return _toProfile(user);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  UserProfile _toProfile(User user) {
    return UserProfile(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName ?? user.email?.split('@').first,
      photoURL: user.photoURL,
      provider: user.providerData.firstOrNull?.providerId,
    );
  }
}