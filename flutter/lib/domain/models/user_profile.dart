import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;
  final String? provider;

  const UserProfile({
    required this.uid,
    this.email,
    this.displayName,
    this.photoURL,
    this.provider,
  });

  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    String? provider,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      provider: provider ?? this.provider,
    );
  }

  @override
  List<Object?> get props => [uid, email, displayName, photoURL, provider];
}