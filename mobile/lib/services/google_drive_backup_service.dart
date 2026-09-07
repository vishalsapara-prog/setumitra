import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'database_service.dart';

/// Google Drive Export/Backup (v4 requirements item 10): local .xlsx
/// export -> Google Drive, via Google account auth.
///
/// ============================================================
/// HONEST RISK DISCLOSURE -- read before relying on this feature
/// ============================================================
/// This is the single highest-uncertainty piece of code in the entire
/// Setumitra project, for reasons genuinely different from every other
/// package decision made this session:
///
/// 1. `google_sign_in` underwent a MAJOR breaking refactor at v7.0.0
///    (mid-2025): the `GoogleSignIn()` constructor was REMOVED entirely
///    in favor of a singleton (`GoogleSignIn.instance`), sign-in and
///    authorization became two separate steps, and several methods were
///    renamed. This code targets the CURRENT, fully-migrated v7 pattern
///    (verified consistently across the official pub.dev package page,
///    the official Dart API docs, and a technical migration writeup --
///    not a single, possibly-stale source).
/// 2. A live, still-open GitHub issue (flutter/flutter#173407) reports a
///    403 "unregistered caller" error reaching Google Drive specifically
///    after upgrading to google_sign_in v7.1.1. Close inspection of that
///    report's own reproduction code shows it MIXES the old, removed
///    `GoogleSignIn(scopes: [...])` constructor pattern with new v7
///    calls -- a plausible migration mistake in the reporter's own code,
///    not necessarily an unfixable package defect -- but this could not
///    be independently confirmed either way without a real device and a
///    real Google Cloud OAuth client to test against, neither of which
///    exist in this build environment.
/// 3. A **real, unavoidable, non-code prerequisite**: this feature
///    CANNOT function no matter how correct the Dart code is, until a
///    Google Cloud Console project is created, the Drive API enabled,
///    an OAuth consent screen configured, and Android/iOS OAuth client
///    IDs generated and tied to this app's actual package name
///    (`com.example.setumitra`) and signing certificate (SHA-1
///    fingerprint). That setup is entirely external to this codebase.
///
/// Given all of the above, on-device debugging and adjustment by
/// whoever deploys this should be EXPECTED for this specific feature --
/// not treated as a sign the approach is fundamentally wrong. Every
/// other package integration in this project was verified with
/// meaningfully higher confidence than this one.
///
/// Scope: uses the narrow `drive.file` scope (Google's recommended
/// minimal scope -- access only to files this app itself creates, not
/// the user's whole Drive) rather than the broad `drive` scope.
/// "Offline-first" is honestly simplified: this attempts the upload
/// immediately and reports success or a specific failure reason; it
/// does NOT implement a persistent background retry queue (a
/// meaningfully larger feature on its own) -- on failure (no
/// connectivity, auth issue, or otherwise), the user retries manually.
class GoogleDriveBackupService {
  // Using the literal scope string (confirmed directly from Google's own
  // Drive API docs and reproduced in real-world code) rather than
  // `drive.DriveApi.driveFileScope` -- the constant's exact name could
  // not be independently confirmed with full confidence (only
  // `driveScope`/`driveAppdataScope` were directly seen during research),
  // and a wrong guess here would fail to compile. The literal string
  // value is unambiguous either way.
  static const List<String> _scopes = ['https://www.googleapis.com/auth/drive.file'];

  static GoogleSignIn get _signIn => GoogleSignIn.instance;
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _signIn.initialize();
    _initialized = true;
  }

  /// Signs the user in (triggers the account picker) and requests the
  /// `drive.file` scope. Returns the signed-in account's display name/
  /// email for UI confirmation. Throws on any failure -- callers should
  /// catch and show the specific error, not assume this always succeeds.
  static Future<String> signIn() async {
    await _ensureInitialized();
    final GoogleSignInAccount account = await _signIn.authenticate();
    await account.authorizationClient.authorizeScopes(_scopes);
    return account.email;
  }

  static Future<bool> isSignedIn() async {
    await _ensureInitialized();
    return _signIn.currentUser != null;
  }

  static Future<void> signOut() async {
    await _ensureInitialized();
    await _signIn.signOut();
  }

  /// Uploads [file] to the signed-in user's Drive (in the app-scoped
  /// `drive.file` space, not visible in the user's main "My Drive" file
  /// list unless they specifically look for app-created files). Returns
  /// the created Drive file's id. Throws with the underlying error on
  /// any failure -- auth expired, no connectivity, quota, or otherwise --
  /// so the caller can show a specific, honest message rather than a
  /// generic "backup failed."
  static Future<String> uploadFile(File file, {String? driveFileName}) async {
    await _ensureInitialized();
    final account = _signIn.currentUser;
    if (account == null) {
      throw StateError('Not signed in to Google. Call signIn() first.');
    }

    final authorization = await account.authorizationClient.authorizationForScopes(_scopes) ??
        await account.authorizationClient.authorizeScopes(_scopes);

    final authClient = authorization.authClient(scopes: _scopes);
    final driveApi = drive.DriveApi(authClient);

    final driveFile = drive.File()..name = driveFileName ?? file.uri.pathSegments.last;
    final media = drive.Media(file.openRead(), await file.length());

    final result = await driveApi.files.create(driveFile, uploadMedia: media);

    await DatabaseService.logAction(
      action: 'GOOGLE_DRIVE_BACKUP',
      details: 'file=${file.path}, driveFileId=${result.id}',
    );

    return result.id ?? '';
  }
}
