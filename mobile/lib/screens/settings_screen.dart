import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/theme_service.dart';
import 'camera_settings_screen.dart';
import 'advanced_ocr_settings_screen.dart';
import 'audit_trail_screen.dart';
import 'auto_fill_mapping_screen.dart';
import 'contacts_export_screen.dart';
import 'google_drive_backup_screen.dart';

/// Settings hub -- per the "UI Simplicity Rule," this is where all
/// technical/configuration screens live, kept out of the main Dashboard.
/// Reachable via the Home screen's app bar Settings icon.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Appearance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 8),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return Card(
                child: Column(
                  children: SetumitraTheme.values.map((t) {
                    return RadioListTile<SetumitraTheme>(
                      title: Text(t.label),
                      value: t,
                      groupValue: themeProvider.current,
                      onChanged: (v) {
                        if (v != null) themeProvider.setTheme(v);
                      },
                    );
                  }).toList(),
                ),
              );
            },
          ),

          const SizedBox(height: 20),
          const Text('Document Scan & OCR', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF2B6CB0)),
                  title: const Text('Camera Settings'),
                  subtitle: const Text('Resolution, crop, filter, grid, flash', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraSettingsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tune, color: Color(0xFF2B6CB0)),
                  title: const Text('Advanced OCR Controls'),
                  subtitle: const Text('Language, denoise, threshold, confidence', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvancedOcrSettingsScreen())),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Text('Records', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history, color: Color(0xFF2B6CB0)),
                  title: const Text('Audit Trail'),
                  subtitle: const Text('History of application actions', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditTrailScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.hub_outlined, color: Color(0xFF2B6CB0)),
                  title: const Text('Website & Auto-Fill Mapping'),
                  subtitle: const Text('Version, import, test, rollback', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoFillMappingScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.contact_page_outlined, color: Color(0xFF2B6CB0)),
                  title: const Text('Contacts & Excel Export'),
                  subtitle: const Text('Export Master Data, manage portal logins', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsExportScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined, color: Color(0xFF2B6CB0)),
                  title: const Text('Google Drive Backup'),
                  subtitle: const Text('Sign in and back up exports', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoogleDriveBackupScreen())),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
