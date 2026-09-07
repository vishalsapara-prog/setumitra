import 'package:flutter/foundation.dart';
import '../models/form_model.dart';
import '../services/db_service.dart';

/// App-wide state for saved offline drafts (Contractor / Principal Employer
/// / License applications the user has partially filled but not yet
/// submitted through the WebView). Backed by [DbService]
/// (flutter_secure_storage). Screens read this via
/// `context.watch<DraftProvider>()` / `context.read<DraftProvider>()`.
class DraftProvider extends ChangeNotifier {
  final DbService _db = DbService();

  List<Map<String, dynamic>> _drafts = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get drafts => List.unmodifiable(_drafts);
  bool get isLoading => _isLoading;

  Future<void> loadDrafts() async {
    _isLoading = true;
    notifyListeners();
    try {
      _drafts = await _db.getDrafts();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> saveDraft(String moduleType, ShramsetuFormModel form) async {
    final id = await _db.saveDraft(moduleType, form);
    await loadDrafts();
    return id;
  }

  Future<void> deleteDraft(String id) async {
    await _db.deleteDraft(id);
    await loadDrafts();
  }

  Future<void> markSynced(String id) async {
    await _db.markSynced(id);
    await loadDrafts();
  }

  ShramsetuFormModel formFromDraft(Map<String, dynamic> draft) {
    final formJson = draft['formJson'] as Map<String, dynamic>? ?? {};
    return ShramsetuFormModel.fromJson(formJson);
  }
}
