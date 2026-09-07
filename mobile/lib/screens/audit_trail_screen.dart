import 'package:flutter/material.dart';
import '../services/database_service.dart';

/// Read-only view of the Audit Trail table -- part of the approved
/// End-to-End Core Workflow chain (...-> Document Generation/Save ->
/// Audit Trail). Shows every recorded action across all applications,
/// most recent first. Currently populated by
/// [DatabaseService.saveApplication] (APPLICATION_CREATED /
/// APPLICATION_UPDATED); other workflow milestones (Auto-Fill run,
/// Document Generated, OCR Verified) can call
/// [DatabaseService.logAction] the same way as further screens wire up
/// to this table -- not all workflow steps log yet, see README.
class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({Key? key}) : super(key: key);

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final entries = await DatabaseService.getAuditTrail();
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  IconData _iconFor(String action) {
    switch (action) {
      case 'APPLICATION_CREATED':
        return Icons.add_circle_outline;
      case 'APPLICATION_UPDATED':
        return Icons.edit_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$d/$m/${dt.year} $h:$min';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Trail'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No recorded actions yet. Entries appear here as applications '
                      'are created, updated, and moved through the workflow.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final e = _entries[index];
                      final action = (e['action'] as String?) ?? '';
                      final details = (e['details'] as String?) ?? '';
                      final appId = e['application_id'];
                      final createdAt = (e['created_at'] as String?) ?? '';
                      return Card(
                        child: ListTile(
                          leading: Icon(_iconFor(action), color: const Color(0xFF2B6CB0)),
                          title: Text(
                            action.replaceAll('_', ' '),
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (details.isNotEmpty)
                                Text(details, style: const TextStyle(fontSize: 11.5)),
                              Text(
                                appId != null ? 'Application #$appId • ${_formatTimestamp(createdAt)}' : _formatTimestamp(createdAt),
                                style: const TextStyle(fontSize: 10.5, color: Colors.black45),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
