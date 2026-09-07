import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/auto_fill_mapping_service.dart';
import '../services/database_service.dart';

/// Website & Auto-Fill Mapping settings (v4 requirements Settings item 6):
/// Current Mapping Version + Last Updated, Mapping Update (via local JSON
/// import -- see AutoFillMappingService's doc comment for why "Check for
/// Update" against a remote server isn't implemented), Previous Mapping
/// Restore/Rollback, Auto-Fill Test. No raw JS/code editing surface
/// exists anywhere here -- only structured JSON import, validated before
/// it's ever applied.
class AutoFillMappingScreen extends StatefulWidget {
  const AutoFillMappingScreen({Key? key}) : super(key: key);

  @override
  State<AutoFillMappingScreen> createState() => _AutoFillMappingScreenState();
}

class _AutoFillMappingScreenState extends State<AutoFillMappingScreen> {
  ResolvedMapping? _active;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  MappingTestResult? _lastTestResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    await AutoFillMappingService.seedIfEmpty();
    final active = await AutoFillMappingService.getActiveMapping();
    final history = await DatabaseService.getMappingVersionHistory();
    setState(() {
      _active = active;
      _history = history;
      _isLoading = false;
      _lastTestResult = null;
    });
  }

  Future<void> _runTest() async {
    if (_active == null) return;
    final result = AutoFillMappingService.testMapping(_active!);
    setState(() => _lastTestResult = result);
  }

  Future<void> _importMapping() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final jsonString = await file.readAsString();

    final validation = AutoFillMappingService.validateMappingJson(jsonString);
    if (!validation.isValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import rejected: ${validation.error}'), backgroundColor: Colors.red),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import New Mapping?'),
        content: const Text(
          'This becomes the active Auto-Fill mapping immediately. The current '
          'version is kept in history and can be restored at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Import')),
        ],
      ),
    );
    if (confirmed != true) return;

    await AutoFillMappingService.importMappingVersion(jsonString);
    await DatabaseService.logAction(action: 'AUTOFILL_MAPPING_IMPORTED', details: 'from ${result.files.single.name}');
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New mapping imported and activated.')));
  }

  Future<void> _rollback(Map<String, dynamic> version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore Version ${version['version_number']}?'),
        content: const Text('This becomes the active Auto-Fill mapping immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;

    await AutoFillMappingService.rollbackTo(version['id'] as int);
    await DatabaseService.logAction(
      action: 'AUTOFILL_MAPPING_ROLLBACK',
      details: 'restored version ${version['version_number']}',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _active == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = _active!;
    final activeRow = _history.isNotEmpty
        ? _history.firstWhere((v) => v['is_active'] == 1, orElse: () => _history.first)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Website & Auto-Fill Mapping')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Version: ${active.versionNumber == 0 ? "Built-in (not yet saved)" : active.versionNumber}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A365D)),
                  ),
                  const SizedBox(height: 4),
                  Text('Source: ${active.source}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if (activeRow != null)
                    Text('Last Updated: ${activeRow['created_at']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 8),
                  Text(
                    '${active.textAndDropdownFields.length + active.checkboxFields.length + active.inferredFields.length} fields mapped',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _importMapping,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Import Mapping (JSON)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _runTest,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Auto-Fill Test'),
                ),
              ),
            ],
          ),

          if (_lastTestResult != null) ...[
            const SizedBox(height: 12),
            Card(
              color: _lastTestResult!.duplicatePortalNames.isEmpty ? Colors.green.shade50 : Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_lastTestResult!.totalMappedFields} fields checked',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (_lastTestResult!.duplicatePortalNames.isEmpty)
                      const Text('No duplicate portal-name collisions found.', style: TextStyle(fontSize: 12))
                    else ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Portal field names claimed by more than one semantic key '
                        '(review each -- some are legitimate, e.g. the same field '
                        'name on two different portal pages):',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      for (final entry in _lastTestResult!.duplicatePortalNames.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• ${entry.key} ← ${entry.value.join(", ")}', style: const TextStyle(fontSize: 11.5)),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Text('Version History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 8),
          for (final v in _history)
            Card(
              child: ListTile(
                leading: Icon(
                  v['is_active'] == 1 ? Icons.check_circle : Icons.circle_outlined,
                  color: v['is_active'] == 1 ? Colors.green : Colors.grey,
                ),
                title: Text('Version ${v['version_number']} (${v['source']})', style: const TextStyle(fontSize: 13)),
                subtitle: Text('${v['created_at']}', style: const TextStyle(fontSize: 11)),
                trailing: v['is_active'] == 1
                    ? null
                    : TextButton(onPressed: () => _rollback(v), child: const Text('Restore')),
              ),
            ),
        ],
      ),
    );
  }
}
