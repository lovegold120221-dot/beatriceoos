import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/user_profile.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<User?> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    return credential.user;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> saveSettings(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings_backup', _serialize(data));

    try {
      await _firestore.collection('settings').doc('current').set(data);
    } catch (_) {
      // Silently handle Firestore unavailability
    }
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('current').get();
      if (doc.exists) return doc.data();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final backup = prefs.getString('settings_backup');
    if (backup != null) return _deserialize(backup);

    return null;
  }

  Future<void> saveConversation(List<Map<String, dynamic>> turns) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conversation_memory', _serialize(turns));

    try {
      await _firestore.collection('memory').doc('conversation').set({
        'turns': turns,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadConversation() async {
    try {
      final doc = await _firestore.collection('memory').doc('conversation').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['turns'] is List) return List<Map<String, dynamic>>.from(data['turns']);
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final backup = prefs.getString('conversation_memory');
    if (backup != null) return List<Map<String, dynamic>>.from(_deserialize(backup) ?? []);

    return [];
  }

  String _serialize(dynamic data) {
    return DateTime.now().toIso8601String() + ':' + data.toString();
  }

  dynamic _deserialize(String data) {
    try {
      return data.split(':').sublist(1).join(':');
    } catch (_) {
      return null;
    }
  }
}