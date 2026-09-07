import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/form_model.dart';

/// Offline draft persistence using flutter_secure_storage.
///
/// Each draft is stored as an individual encrypted key-value entry
/// (`draft_<epochMillis>` -> JSON blob), rather than a SQLite table.
/// `readAll()` is used to enumerate drafts, filtered by key prefix, since
/// flutter_secure_storage has no query/index API of its own. This is
/// intentionally simple: draft volumes on a single officer's/contractor's
/// device are expected to be small (tens, not thousands), so an O(n) scan
/// on read is an acceptable trade-off for the added at-rest encryption
/// flutter_secure_storage provides over a plain SQLite file.
class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _keyPrefix = 'draft_';

  Future<String> saveDraft(String moduleType, ShramsetuFormModel form) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final record = {
      'id': id,
      'moduleType': moduleType,
      'formJson': form.toJson(),
      'createdAt': DateTime.now().toIso8601String(),
      'synced': false,
    };
    await _storage.write(key: '$_keyPrefix$id', value: jsonEncode(record));
    return id;
  }

  Future<List<Map<String, dynamic>>> getDrafts() async {
    final all = await _storage.readAll();
    final drafts = <Map<String, dynamic>>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_keyPrefix)) continue;
      try {
        final decoded = jsonDecode(entry.value) as Map<String, dynamic>;
        drafts.add(decoded);
      } catch (_) {
        // Skip a corrupted/unreadable entry rather than crash the whole list.
        continue;
      }
    }
    drafts.sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
    return drafts;
  }

  Future<void> markSynced(String id) async {
    final key = '$_keyPrefix$id';
    final raw = await _storage.read(key: key);
    if (raw == null) return;
    final record = jsonDecode(raw) as Map<String, dynamic>;
    record['synced'] = true;
    await _storage.write(key: key, value: jsonEncode(record));
  }

  Future<void> deleteDraft(String id) async {
    await _storage.delete(key: '$_keyPrefix$id');
  }

  Future<void> deleteAllDrafts() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_keyPrefix)) {
        await _storage.delete(key: key);
      }
    }
  }
}
