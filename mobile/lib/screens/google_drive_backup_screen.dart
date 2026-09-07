import 'package:flutter/material.dart';
import '../services/google_drive_backup_service.dart';
import '../services/contacts_export_service.dart';

/// Google Drive Export/Backup (v4 requirements item 10). See
/// GoogleDriveBackupService's doc comment for the full, honest risk
/// disclosure -- this screen surfaces the same caveats to the admin
/// rather than presenting the feature as equally reliable to everything
/// else in Settings.
class GoogleDriveBackupScreen extends StatefulWidget {
  const GoogleDriveBackupScreen({Key? key}) : super(key: key);

  @override
  State<GoogleDriveBackupScreen> createState() => _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState extends State<GoogleDriveBackupScreen> {
  bool _isSignedIn = false;
  String? _signedInEmail;
  bool _isBusy = false;
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    _checkSignIn();
  }

  Future<void> _checkSignIn() async {
    final signedIn = await GoogleDriveBackupService.isSignedIn();
    setState(() => _isSignedIn = signedIn);
  }

  Future<void> _signIn() async {
    setState(() {
      _isBusy = true;
      _lastStatus = null;
    });
    try {
      final email = await GoogleDriveBackupService.signIn();
      setState(() {
        _isSignedIn = true;
        _signedInEmail = email;
        _lastStatus = 'Signed in as $email';
      });
    } catch (e) {
      setState(() => _lastStatus = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signOut() async {
    await GoogleDriveBackupService.signOut();
    setState(() {
      _isSignedIn = false;
      _signedInEmail = null;
      _lastStatus = 'Signed out.';
    });
  }

  Future<void> _backupContactsNow() async {
    setState(() {
      _isBusy = true;
      _lastStatus = null;
    });
    try {
      final file = await ContactsExportService.exportContactsExcel();
      await GoogleDriveBackupService.uploadFile(file, driveFileName: 'Setumitra_Contacts_Backup.xlsx');
      setState(() => _lastStatus = 'Backup uploaded to Google Drive successfully.');
    } catch (e) {
      setState(() => _lastStatus = 'Backup failed: $e\n\nThis feature has known setup prerequisites -- see the app README before assuming the code itself is broken.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This is the highest-uncertainty feature in Setumitra. Google Sign-In '
                'requires one-time setup in Google Cloud Console (OAuth client for this '
                'app\'s package name and signing certificate) before it can work at all -- '
                'no app update alone fixes a sign-in failure caused by missing setup. '
                'See the README for details.',
                style: TextStyle(fontSize: 11.5, color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_isSignedIn) ...[
            ListTile(
              leading: const Icon(Icons.account_circle, color: Colors.green),
              title: Text(_signedInEmail ?? 'Signed in'),
              trailing: TextButton(onPressed: _isBusy ? null : _signOut, child: const Text('Sign Out')),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _backupContactsNow,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Backup Contacts Now'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _signIn,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),

          if (_isBusy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),

          if (_lastStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                color: _lastStatus!.contains('failed') ? Colors.red.shade50 : Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_lastStatus!, style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
