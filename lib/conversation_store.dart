// conversation_store.dart
//
// Stores past conversation titles and message lists in SharedPreferences.
// Uses JSON encoding. Each session is keyed by a timestamp-based ID.
// Incognito sessions are never written here.
//
// Storage keys:
//   cs_session_index  -> List<String> of session IDs (newest first)
//   cs_session_<id>   -> JSON-encoded session payload

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_message.dart';

const _kSessionIndexKey = 'cs_session_index';
const _kSessionPrefix = 'cs_session_';

class ConversationStore {
  // ---- Write ---------------------------------------------------------------

  /// Save (or overwrite) a session. Call after every AI reply in normal mode.
  /// No-op in incognito mode - the caller is responsible for the guard.
  static Future<void> saveSession({
    required String id,
    required String title,
    required List<ChatTurn> turns,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Update session index (newest first)
    final index = prefs.getStringList(_kSessionIndexKey) ?? [];
    if (!index.contains(id)) {
      index.insert(0, id);
      await prefs.setStringList(_kSessionIndexKey, index);
    }

    // Encode session
    final payload = jsonEncode({
      'id': id,
      'title': title,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'turns': turns.map((t) => t.toJson()).toList(),
    });
    await prefs.setString('$_kSessionPrefix$id', payload);
  }

  // ---- Read ----------------------------------------------------------------

  /// List all saved sessions, newest first.
  static Future<List<SessionSummary>> listSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_kSessionIndexKey) ?? [];
    final summaries = <SessionSummary>[];
    for (final id in index) {
      final raw = prefs.getString('$_kSessionPrefix$id');
      if (raw == null) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        summaries.add(SessionSummary(
          id: map['id'] as String,
          title: map['title'] as String,
          updatedAt:
              DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
        ));
      } catch (_) {
        // Skip corrupted entries
      }
    }
    return summaries;
  }

  /// Load all turns for a session.
  static Future<List<ChatTurn>?> loadSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kSessionPrefix$id');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final turns = (map['turns'] as List)
          .map((t) => ChatTurn.fromJson(t as Map<String, dynamic>))
          .toList();
      return turns;
    } catch (_) {
      return null;
    }
  }

  // ---- Delete --------------------------------------------------------------

  static Future<void> deleteSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_kSessionIndexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_kSessionIndexKey, index);
    await prefs.remove('$_kSessionPrefix$id');
  }

  // TODO: wire to Settings > Clear all conversations.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_kSessionIndexKey) ?? [];
    for (final id in index) {
      await prefs.remove('$_kSessionPrefix$id');
    }
    await prefs.remove(_kSessionIndexKey);
  }
}

class SessionSummary {
  final String id;
  final String title;
  final DateTime updatedAt;

  const SessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });
}
