import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger.dart';

/// 3-tier memory persistence with graceful timeout per tier.
///
/// Tier 1: Firebase Realtime Database (RTDB) — fastest
/// Tier 2: Cloud Firestore — most reliable
/// Tier 3: Local SharedPreferences — always available
class MemoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  static const _tierTimeout = Duration(seconds: 2);

  /// Save conversation turns with 3-tier fallback.
  Future<void> saveConversation(
      String uid, List<Map<String, dynamic>> turns) async {
    // Tier 1: RTDB
    try {
      await _database
          .ref('users/$uid/conversation')
          .set({
            'turns': turns,
            'updatedAt': DateTime.now().toIso8601String(),
          })
          .timeout(_tierTimeout);
      return;
    } on TimeoutException {
      appLogger.d('RTDB save timed out, falling back to Firestore');
    } catch (e, s) {
      appLogger.d('RTDB save failed, falling back to Firestore',
          error: e, stackTrace: s);
    }

    // Tier 2: Firestore
    try {
      await _firestore
          .collection('memory')
          .doc(uid)
          .set({
            'turns': turns,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(_tierTimeout);
      return;
    } on TimeoutException {
      appLogger.d('Firestore save timed out, falling back to local');
    } catch (e, s) {
      appLogger.d('Firestore save failed, falling back to local',
          error: e, stackTrace: s);
    }

    // Tier 3: SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('beatrice_conversation_$uid', jsonEncode(turns));
  }

  /// Load conversation turns with 3-tier fallback.
  Future<List<Map<String, dynamic>>> loadConversation(String uid) async {
    // Tier 1: RTDB
    try {
      final snapshot = await _database
          .ref('users/$uid/conversation')
          .get()
          .timeout(_tierTimeout);
      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final turns = data['turns'];
        if (turns is List) {
          return turns.whereType<Map<String, dynamic>>().toList();
        }
      }
    } on TimeoutException {
      appLogger.d('RTDB load timed out, falling back to Firestore');
    } catch (e, s) {
      appLogger.d('RTDB load failed, falling back to Firestore',
          error: e, stackTrace: s);
    }

    // Tier 2: Firestore
    try {
      final doc = await _firestore
          .collection('memory')
          .doc(uid)
          .get()
          .timeout(_tierTimeout);
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final turns = data['turns'];
        if (turns is List) {
          return turns.whereType<Map<String, dynamic>>().toList();
        }
      }
    } on TimeoutException {
      appLogger.d('Firestore load timed out, falling back to local');
    } catch (e, s) {
      appLogger.d('Firestore load failed, falling back to local',
          error: e, stackTrace: s);
    }

    // Tier 3: SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('beatrice_conversation_$uid');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.whereType<Map<String, dynamic>>().toList();
        }
      } catch (e, s) {
        appLogger.w('Failed to decode local conversation',
            error: e, stackTrace: s);
      }
    }
    return [];
  }

  /// Clear memory across all tiers.
  Future<void> clearConversation(String uid) async {
    try {
      await _database.ref('users/$uid/conversation').remove();
    } catch (_) {}
    try {
      await _firestore.collection('memory').doc(uid).delete();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('beatrice_conversation_$uid');
  }
}
