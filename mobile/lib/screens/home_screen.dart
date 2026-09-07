import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/draft_provider.dart';
import 'scan_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🏛️ Setumitra',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A365D),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => context.read<DraftProvider>().loadDrafts(),
            tooltip: 'Refresh saved drafts',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<DraftProvider>().loadDrafts(),
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            const Text(
              'Select Portal Workflow',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A365D)),
            ),
            const SizedBox(height: 20),
            _buildModuleCard(
              context,
              title: '1. New Contractor Registration',
              subtitle: 'Create Establishment Profile & Obtain Unique EIN',
              icon: Icons.business,
              moduleType: 'REGISTRATION',
            ),
            const SizedBox(height: 16),
            _buildModuleCard(
              context,
              title: '2. New Principal Employer Registration',
              subtitle: 'Register as Principal Employer & Nominate Contractor(s)',
              icon: Icons.apartment,
              moduleType: 'PE_REGISTRATION',
            ),
            const SizedBox(height: 16),
            _buildModuleCard(
              context,
              title: '3. New FORM-25 License Application',
              subtitle: 'Work Order OCR, Labour Matrix & Bank Guarantee Auto-Fill',
              icon: Icons.assignment_turned_in,
              moduleType: 'LICENSE',
            ),
            const SizedBox(height: 28),
            const Text(
              'Saved Offline Drafts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A365D)),
            ),
            const SizedBox(height: 8),
            Consumer<DraftProvider>(
              builder: (context, draftProvider, _) {
                if (draftProvider.isLoading) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (draftProvider.drafts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No saved drafts yet.', style: TextStyle(color: Colors.black54)),
                  );
                }
                return Column(
                  children: draftProvider.drafts.map((draft) {
                    final id = draft['id'] as String;
                    final moduleType = draft['moduleType'] as String? ?? 'UNKNOWN';
                    final formJson = draft['formJson'] as Map<String, dynamic>? ?? {};
                    final name = (formJson['establishment_name'] ?? '').toString();
                    final createdAt = draft['createdAt'] as String? ?? '';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined, color: Color(0xFF2B6CB0)),
                        title: Text(name.isNotEmpty ? name : '(Unnamed draft)'),
                        subtitle: Text('$moduleType • Saved: ${_formatTimestamp(createdAt)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _confirmDelete(context, id),
                        ),
                        onTap: () {
                          final formData = draftProvider.formFromDraft(draft);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReviewScreen(moduleType: moduleType, formData: formData),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
      // "＋ નવી અરજી" (New Application): a central, additive entry point per
      // the approved requirements addition. Does NOT replace the three
      // existing module cards above -- both remain available. Opens a
      // bottom sheet listing the same application types, structured so
      // future types (Renewal, Amendment/Update) can be added to this one
      // list without complicating the rest of the screen.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewApplicationSheet(context),
        backgroundColor: const Color(0xFF2B6CB0),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('નવી અરજી', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showNewApplicationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                'નવી અરજી — Select Application Type',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D)),
              ),
            ),
            _sheetOption(
              context,
              sheetContext,
              icon: Icons.business,
              title: 'Contractor Registration',
              moduleType: 'REGISTRATION',
            ),
            _sheetOption(
              context,
              sheetContext,
              icon: Icons.apartment,
              title: 'Principal Employer Registration',
              moduleType: 'PE_REGISTRATION',
            ),
            _sheetOption(
              context,
              sheetContext,
              icon: Icons.assignment_turned_in,
              title: 'FORM-25 License Application',
              moduleType: 'LICENSE',
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// [pageContext] (the Home screen's own, still-mounted context) is used
  /// for the actual navigation push; [sheetContext] is used only to close
  /// the bottom sheet. Using sheetContext for both would push a route on
  /// an already-deactivated widget once the sheet is popped.
  Widget _sheetOption(
    BuildContext pageContext,
    BuildContext sheetContext, {
    required IconData icon,
    required String title,
    required String moduleType,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF2B6CB0),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.pop(sheetContext);
        Navigator.push(
          pageContext,
          MaterialPageRoute(builder: (_) => ScanScreen(moduleType: moduleType)),
        );
      },
    );
  }

  static String _formatTimestamp(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Draft?'),
        content: const Text('This will permanently remove the saved draft from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<DraftProvider>().deleteDraft(id);
              Navigator.pop(dialogContext);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String moduleType,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ScanScreen(moduleType: moduleType)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF2B6CB0),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF1A365D)),
            ],
          ),
        ),
      ),
    );
  }
}
