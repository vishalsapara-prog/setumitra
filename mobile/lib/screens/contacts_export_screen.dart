import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../models/master_data_models.dart';
import '../services/database_service.dart';
import '../services/contacts_export_service.dart';

/// Contacts & Excel export (v4 requirements Settings item 5). Lists
/// Master Data establishments, lets the admin view/edit each one's
/// portal-login username/password (stored plain-text, explicitly
/// approved per the requirements -- see ContactsExportService's doc
/// comment), and exports either the full Contacts sheet or a
/// deduplicated Unique Email List.
class ContactsExportScreen extends StatefulWidget {
  const ContactsExportScreen({Key? key}) : super(key: key);

  @override
  State<ContactsExportScreen> createState() => _ContactsExportScreenState();
}

class _ContactsExportScreenState extends State<ContactsExportScreen> {
  List<EstablishmentMaster> _establishments = [];
  Map<int, String> _typeById = {};
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final establishments = await DatabaseService.listEstablishments();
    final types = <int, String>{};
    for (final e in establishments) {
      types[e.id!] = await DatabaseService.deriveEstablishmentType(e.id!);
    }
    setState(() {
      _establishments = establishments;
      _typeById = types;
      _isLoading = false;
    });
  }

  Future<void> _editCredentials(EstablishmentMaster est) async {
    final usernameController = TextEditingController(text: est.username);
    final passwordController = TextEditingController(text: est.password);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(est.establishmentName.isEmpty ? 'Portal Credentials' : est.establishmentName, style: const TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), isDense: true),
              obscureText: false, // stored/exported plain-text; obscuring only the input field would be inconsistent
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.updateEstablishmentCredentials(
        id: est.id!,
        username: usernameController.text,
        password: passwordController.text,
      );
      await _load();
    }
  }

  Future<void> _exportAndShare(BuildContext buttonContext, Future<dynamic> Function() exportFn, String label) async {
    setState(() => _isExporting = true);
    try {
      final file = await exportFn();
      if (!mounted) return;
      final box = buttonContext.findRenderObject() as RenderBox?;
      final origin = box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: label, sharePositionOrigin: origin),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts & Excel Export')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (buttonContext) => ElevatedButton.icon(
                            onPressed: _isExporting
                                ? null
                                : () => _exportAndShare(buttonContext, ContactsExportService.exportContactsExcel, 'Setumitra Contacts Export'),
                            icon: const Icon(Icons.table_chart_outlined, size: 18),
                            label: const Text('Export Contacts'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (buttonContext) => OutlinedButton.icon(
                            onPressed: _isExporting
                                ? null
                                : () => _exportAndShare(buttonContext, ContactsExportService.exportUniqueEmailList, 'Setumitra Unique Email List'),
                            icon: const Icon(Icons.email_outlined, size: 18),
                            label: const Text('Unique Emails'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isExporting) const LinearProgressIndicator(),
                Expanded(
                  child: _establishments.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No Master Data establishments yet. These appear here once an application '
                              'with a PAN has been saved on the Review screen.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.black54),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _establishments.length,
                          itemBuilder: (context, index) {
                            final est = _establishments[index];
                            final type = _typeById[est.id] ?? 'Establishment';
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: type == 'Contractor' ? const Color(0xFF2B6CB0) : Colors.teal,
                                  child: Icon(type == 'Contractor' ? Icons.business : Icons.apartment, color: Colors.white, size: 18),
                                ),
                                title: Text(
                                  est.establishmentName.isEmpty ? '(Unnamed)' : est.establishmentName,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '$type • ${est.mobileNumber.isEmpty ? "no mobile" : est.mobileNumber} • '
                                  '${est.username.isEmpty ? "no login set" : "login: ${est.username}"}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _editCredentials(est),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
