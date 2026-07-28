import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger.dart';

/// Firestore + SharedPreferences persistence for settings and conversation
/// memory, with anonymous auth.
///
/// Local backups are now stored as JSON (previously `_serialize` called
/// `.toString()` on a Map and `_deserialize` split on `:`, which corrupted any
/// value containing a colon and round-tripped unreliably). Firestore failures
/// are logged, not silently swallowed.
class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _settingsBackupKey = 'beatrice_settings_backup';
  static const String _conversationKey = 'beatrice_conversation_memory';

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<User?> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    return credential.user;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> saveSettings(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsBackupKey, jsonEncode(data));
    try {
      await _firestore.collection('settings').doc('current').set(data);
    } catch (e, s) {
      appLogger.w('Firestore saveSettings failed (local backup retained)',
          error: e, stackTrace: s);
    }
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('current').get();
      if (doc.exists && doc.data() != null) return doc.data();
    } catch (e, s) {
      appLogger.w('Firestore loadSettings failed, falling back to local',
          error: e, stackTrace: s);
    }

    final prefs = await SharedPreferences.getInstance();
    final backup = prefs.getString(_settingsBackupKey);
    return _decodeMap(backup);
  }

  Future<void> saveConversation(List<Map<String, dynamic>> turns) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_conversationKey, jsonEncode(turns));
    try {
      await _firestore.collection('memory').doc('conversation').set({
        'turns': turns,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e, s) {
      appLogger.w('Firestore saveConversation failed (local backup retained)',
          error: e, stackTrace: s);
    }
  }

  Future<List<Map<String, dynamic>>> loadConversation() async {
    try {
      final doc = await _firestore.collection('memory').doc('conversation').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['turns'] is List) {
          return (data['turns'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }
    } catch (e, s) {
      appLogger.w('Firestore loadConversation failed, falling back to local',
          error: e, stackTrace: s);
    }

    final prefs = await SharedPreferences.getInstance();
    final backup = prefs.getString(_conversationKey);
    final decoded = _decodeList(backup);
    return decoded;
  }

  Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e, s) {
      appLogger.w('Failed to decode settings backup, discarding',
          error: e, stackTrace: s);
      return null;
    }
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e, s) {
      appLogger.w('Failed to decode conversation backup, discarding',
          error: e, stackTrace: s);
    }
    return [];
  }
}