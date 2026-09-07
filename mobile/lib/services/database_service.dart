import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/master_data_models.dart';

/// Local SQLite Master Data store. Part of the Path B (native Dart)
/// architecture -- this fully replaces the previous FastAPI/SQLAlchemy
/// backend's database role, running entirely on-device.
///
/// The core value of Master Data (per the requirements document): once an
/// Establishment/PE/Authorized Person/Bank record is verified once, it
/// should be reusable across applications without re-entry. Each
/// `findOrCreate*` method below implements that: look up by the record's
/// natural identifying key (PAN for Establishment, identity number for
/// Authorized Person, IFSC+account for Bank, EIN for Principal Employer);
/// if found, return the existing record (optionally refreshed with newer
/// non-empty field values); if not, insert a new one.
///
/// NOT executed on a real Dart/Flutter runtime in this build environment
/// (no Flutter SDK available here) -- sqflite's API was verified against
/// current, live documentation before writing this (see README), but this
/// file itself is structurally reviewed and compile-checked only.
class DatabaseService {
  static Database? _db;
  // Bumped 1 -> 2 when audit_trail was added, 2 -> 3 when
  // auto_fill_mapping_versions was added, 3 -> 4 when
  // establishment_master gained mobile_number/email_id/username/password
  // (Contacts & Excel export). onUpgrade below handles each for any
  // database that already exists below that version, since onCreate only
  // runs for brand-new databases and would silently do nothing for an
  // existing install otherwise.
  static const int _schemaVersion = 4;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'setumitra_master.db');
    return openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE establishment_master (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pan_number TEXT NOT NULL,
            gstin TEXT,
            establishment_name TEXT NOT NULL,
            head_office_address TEXT,
            pincode TEXT,
            ein_number TEXT,
            type_of_ownership TEXT,
            type_of_establishment TEXT,
            mobile_number TEXT,
            email_id TEXT,
            username TEXT,
            password TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(pan_number)
          )
        ''');
        await db.execute('''
          CREATE TABLE authorized_person_master (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            identity_number TEXT NOT NULL,
            name TEXT NOT NULL,
            dob TEXT,
            permanent_address TEXT,
            designation TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(identity_number)
          )
        ''');
        await db.execute('''
          CREATE TABLE bank_details_master (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bank_name TEXT,
            ifsc TEXT NOT NULL,
            account_number TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(ifsc, account_number)
          )
        ''');
        await db.execute('''
          CREATE TABLE principal_employer_master (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ein_selected TEXT NOT NULL,
            registration_no TEXT,
            name TEXT NOT NULL,
            address TEXT,
            district TEXT,
            taluka TEXT,
            pincode TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(ein_selected)
          )
        ''');
        // Applications table: an application REFERENCES a master
        // establishment record (establishment_master_id) rather than
        // duplicating its fields, so edits to master data are reflected
        // everywhere that record is used.
        await db.execute('''
          CREATE TABLE applications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            module_type TEXT NOT NULL,
            establishment_master_id INTEGER,
            status TEXT NOT NULL DEFAULT 'DRAFT',
            form_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (establishment_master_id) REFERENCES establishment_master (id)
          )
        ''');
        // Audit Trail: part of the approved End-to-End Core Workflow
        // (Document -> OCR -> Verify/Edit -> Master Data -> New App ->
        // Auto-Fill -> Final Review -> Shramsetu -> Document Generation/
        // Save -> Audit Trail). One row per recorded action; application_id
        // is nullable since some actions (e.g. a Master Data edit made
        // outside any specific application) aren't tied to one.
        await db.execute('''
          CREATE TABLE audit_trail (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            application_id INTEGER,
            action TEXT NOT NULL,
            details TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (application_id) REFERENCES applications (id)
          )
        ''');
        // Auto-Fill Mapping versions: converts portal_field_map.dart from
        // a hardcoded, rebuild-required Dart file into an admin-updatable,
        // versioned, rollback-capable config -- per the v4 requirements'
        // "Website & Auto-Fill Mapping" settings section. Each row is a
        // FULL SNAPSHOT (not a diff) of the mapping at that version, so
        // rollback is just "make an older row active again" -- no replay
        // logic needed. Exactly one row should have is_active=1 at a time
        // (enforced in code, not a DB constraint, since SQLite has no
        // native partial-unique-index guard in the version this app
        // targets).
        await db.execute('''
          CREATE TABLE auto_fill_mapping_versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version_number INTEGER NOT NULL,
            mapping_json TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'IMPORTED',
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS audit_trail (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              application_id INTEGER,
              action TEXT NOT NULL,
              details TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY (application_id) REFERENCES applications (id)
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS auto_fill_mapping_versions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              version_number INTEGER NOT NULL,
              mapping_json TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 0,
              source TEXT NOT NULL DEFAULT 'IMPORTED',
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE establishment_master ADD COLUMN mobile_number TEXT');
          await db.execute('ALTER TABLE establishment_master ADD COLUMN email_id TEXT');
          await db.execute('ALTER TABLE establishment_master ADD COLUMN username TEXT');
          await db.execute('ALTER TABLE establishment_master ADD COLUMN password TEXT');
        }
      },
    );
  }

  static String _nowIso() => DateTime.now().toIso8601String();

  // ---------------------------------------------------------------------
  // Establishment Master
  // ---------------------------------------------------------------------

  /// Looks up by PAN (the establishment's stable natural key). If found,
  /// non-empty incoming field values overwrite the stored ones (treating
  /// a fresh OCR/manual entry as potentially more current) and the record
  /// is updated; otherwise a new record is inserted. Returns the final
  /// stored record either way.
  static Future<EstablishmentMaster> findOrCreateEstablishment({
    required String panNumber,
    String gstin = '',
    required String establishmentName,
    String headOfficeAddress = '',
    String pincode = '',
    String einNumber = '',
    String typeOfOwnership = '',
    String typeOfEstablishment = '',
    String mobileNumber = '',
    String emailId = '',
    String username = '',
    String password = '',
  }) async {
    final db = await database;
    final pan = panNumber.toUpperCase().trim();
    final existingRows = await db.query(
      'establishment_master',
      where: 'pan_number = ?',
      whereArgs: [pan],
      limit: 1,
    );

    final now = _nowIso();
    if (existingRows.isNotEmpty) {
      final existing = EstablishmentMaster.fromMap(existingRows.first);
      final merged = EstablishmentMaster(
        id: existing.id,
        panNumber: pan,
        gstin: gstin.isNotEmpty ? gstin : existing.gstin,
        establishmentName: establishmentName.isNotEmpty ? establishmentName : existing.establishmentName,
        headOfficeAddress: headOfficeAddress.isNotEmpty ? headOfficeAddress : existing.headOfficeAddress,
        pincode: pincode.isNotEmpty ? pincode : existing.pincode,
        einNumber: einNumber.isNotEmpty ? einNumber : existing.einNumber,
        typeOfOwnership: typeOfOwnership.isNotEmpty ? typeOfOwnership : existing.typeOfOwnership,
        typeOfEstablishment: typeOfEstablishment.isNotEmpty ? typeOfEstablishment : existing.typeOfEstablishment,
        // mobileNumber/emailId can come from a re-saved Registration form;
        // username/password never do (no such fields exist in the OCR/
        // Registration flow) -- either way, "keep existing if new value is
        // empty" is correct: a plain re-save must never silently wipe out
        // portal credentials entered separately in the Contacts screen.
        mobileNumber: mobileNumber.isNotEmpty ? mobileNumber : existing.mobileNumber,
        emailId: emailId.isNotEmpty ? emailId : existing.emailId,
        username: username.isNotEmpty ? username : existing.username,
        password: password.isNotEmpty ? password : existing.password,
        createdAt: existing.createdAt,
        updatedAt: now,
      );
      await db.update('establishment_master', merged.toMap(), where: 'id = ?', whereArgs: [existing.id]);
      return merged;
    }

    final fresh = EstablishmentMaster(
      panNumber: pan,
      gstin: gstin,
      establishmentName: establishmentName,
      headOfficeAddress: headOfficeAddress,
      pincode: pincode,
      einNumber: einNumber,
      typeOfOwnership: typeOfOwnership,
      typeOfEstablishment: typeOfEstablishment,
      mobileNumber: mobileNumber,
      emailId: emailId,
      username: username,
      password: password,
      createdAt: now,
      updatedAt: now,
    );
    final newId = await db.insert('establishment_master', fresh.toMap());
    return EstablishmentMaster.fromMap({...fresh.toMap(), 'id': newId});
  }

  static Future<List<EstablishmentMaster>> listEstablishments() async {
    final db = await database;
    final rows = await db.query('establishment_master', orderBy: 'updated_at DESC');
    return rows.map(EstablishmentMaster.fromMap).toList();
  }

  /// Updates ONLY the portal-login credential fields for an existing
  /// establishment, without touching anything else -- used by the
  /// Contacts export screen's inline edit, which has no access to (and
  /// shouldn't need) the rest of that establishment's registration data.
  static Future<void> updateEstablishmentCredentials({
    required int id,
    required String username,
    required String password,
  }) async {
    final db = await database;
    await db.update(
      'establishment_master',
      {'username': username, 'password': password, 'updated_at': _nowIso()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Derives whether an establishment record was created via a Contractor
  /// flow (REGISTRATION or LICENSE application linked to it) vs only ever
  /// used as a plain Establishment (e.g. a Principal Employer's own PAN
  /// identity, with no Contractor-type application attached). Used by the
  /// Contacts export's "Type" column. Disclosed interpretation, see
  /// README: the v4 requirements' exact intended Type semantics weren't
  /// fully recoverable from this session's compressed context, so this is
  /// a reasoned best-effort against the actual data model, not a literal
  /// requoted spec.
  static Future<String> deriveEstablishmentType(int establishmentId) async {
    final db = await database;
    final rows = await db.query(
      'applications',
      where: 'establishment_master_id = ? AND (module_type = ? OR module_type = ?)',
      whereArgs: [establishmentId, 'REGISTRATION', 'LICENSE'],
      limit: 1,
    );
    return rows.isNotEmpty ? 'Contractor' : 'Establishment';
  }

  // ---------------------------------------------------------------------
  // Authorized Person Master
  // ---------------------------------------------------------------------

  static Future<AuthorizedPersonMaster> findOrCreateAuthorizedPerson({
    required String identityNumber,
    required String name,
    String dob = '',
    String permanentAddress = '',
    String designation = '',
  }) async {
    final db = await database;
    final idNum = identityNumber.toUpperCase().trim();
    final existingRows = await db.query(
      'authorized_person_master',
      where: 'identity_number = ?',
      whereArgs: [idNum],
      limit: 1,
    );
    final now = _nowIso();
    if (existingRows.isNotEmpty) {
      final existing = AuthorizedPersonMaster.fromMap(existingRows.first);
      final merged = AuthorizedPersonMaster(
        id: existing.id,
        identityNumber: idNum,
        name: name.isNotEmpty ? name : existing.name,
        dob: dob.isNotEmpty ? dob : existing.dob,
        permanentAddress: permanentAddress.isNotEmpty ? permanentAddress : existing.permanentAddress,
        designation: designation.isNotEmpty ? designation : existing.designation,
        createdAt: existing.createdAt,
        updatedAt: now,
      );
      await db.update('authorized_person_master', merged.toMap(), where: 'id = ?', whereArgs: [existing.id]);
      return merged;
    }
    final fresh = AuthorizedPersonMaster(
      identityNumber: idNum,
      name: name,
      dob: dob,
      permanentAddress: permanentAddress,
      designation: designation,
      createdAt: now,
      updatedAt: now,
    );
    final newId = await db.insert('authorized_person_master', fresh.toMap());
    return AuthorizedPersonMaster.fromMap({...fresh.toMap(), 'id': newId});
  }

  // ---------------------------------------------------------------------
  // Bank Details Master
  // ---------------------------------------------------------------------

  static Future<BankDetailsMaster> findOrCreateBankDetails({
    String bankName = '',
    required String ifsc,
    required String accountNumber,
  }) async {
    final db = await database;
    final ifscUpper = ifsc.toUpperCase().trim();
    final existingRows = await db.query(
      'bank_details_master',
      where: 'ifsc = ? AND account_number = ?',
      whereArgs: [ifscUpper, accountNumber],
      limit: 1,
    );
    final now = _nowIso();
    if (existingRows.isNotEmpty) {
      final existing = BankDetailsMaster.fromMap(existingRows.first);
      final merged = BankDetailsMaster(
        id: existing.id,
        bankName: bankName.isNotEmpty ? bankName : existing.bankName,
        ifsc: ifscUpper,
        accountNumber: accountNumber,
        createdAt: existing.createdAt,
        updatedAt: now,
      );
      await db.update('bank_details_master', merged.toMap(), where: 'id = ?', whereArgs: [existing.id]);
      return merged;
    }
    final fresh = BankDetailsMaster(
      bankName: bankName,
      ifsc: ifscUpper,
      accountNumber: accountNumber,
      createdAt: now,
      updatedAt: now,
    );
    final newId = await db.insert('bank_details_master', fresh.toMap());
    return BankDetailsMaster.fromMap({...fresh.toMap(), 'id': newId});
  }

  // ---------------------------------------------------------------------
  // Principal Employer Master
  // ---------------------------------------------------------------------

  static Future<PrincipalEmployerMaster> findOrCreatePrincipalEmployer({
    required String einSelected,
    String registrationNo = '',
    required String name,
    String address = '',
    String district = '',
    String taluka = '',
    String pincode = '',
  }) async {
    final db = await database;
    final ein = einSelected.toUpperCase().trim();
    final existingRows = await db.query(
      'principal_employer_master',
      where: 'ein_selected = ?',
      whereArgs: [ein],
      limit: 1,
    );
    final now = _nowIso();
    if (existingRows.isNotEmpty) {
      final existing = PrincipalEmployerMaster.fromMap(existingRows.first);
      final merged = PrincipalEmployerMaster(
        id: existing.id,
        einSelected: ein,
        registrationNo: registrationNo.isNotEmpty ? registrationNo : existing.registrationNo,
        name: name.isNotEmpty ? name : existing.name,
        address: address.isNotEmpty ? address : existing.address,
        district: district.isNotEmpty ? district : existing.district,
        taluka: taluka.isNotEmpty ? taluka : existing.taluka,
        pincode: pincode.isNotEmpty ? pincode : existing.pincode,
        createdAt: existing.createdAt,
        updatedAt: now,
      );
      await db.update('principal_employer_master', merged.toMap(), where: 'id = ?', whereArgs: [existing.id]);
      return merged;
    }
    final fresh = PrincipalEmployerMaster(
      einSelected: ein,
      registrationNo: registrationNo,
      name: name,
      address: address,
      district: district,
      taluka: taluka,
      pincode: pincode,
      createdAt: now,
      updatedAt: now,
    );
    final newId = await db.insert('principal_employer_master', fresh.toMap());
    return PrincipalEmployerMaster.fromMap({...fresh.toMap(), 'id': newId});
  }

  // ---------------------------------------------------------------------
  // Applications
  // ---------------------------------------------------------------------

  static Future<int> saveApplication({
    required String moduleType,
    int? establishmentMasterId,
    String status = 'DRAFT',
    required String formJson,
    int? existingId,
  }) async {
    final db = await database;
    final now = _nowIso();
    if (existingId != null) {
      await db.update(
        'applications',
        {
          'module_type': moduleType,
          'establishment_master_id': establishmentMasterId,
          'status': status,
          'form_json': formJson,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );
      await logAction(
        applicationId: existingId,
        action: 'APPLICATION_UPDATED',
        details: 'moduleType=$moduleType, status=$status',
      );
      return existingId;
    }
    final newId = await db.insert('applications', {
      'module_type': moduleType,
      'establishment_master_id': establishmentMasterId,
      'status': status,
      'form_json': formJson,
      'created_at': now,
      'updated_at': now,
    });
    await logAction(
      applicationId: newId,
      action: 'APPLICATION_CREATED',
      details: 'moduleType=$moduleType, status=$status',
    );
    return newId;
  }

  static Future<List<Map<String, dynamic>>> listApplications() async {
    final db = await database;
    return db.query('applications', orderBy: 'updated_at DESC');
  }

  static Future<void> deleteApplication(int id) async {
    final db = await database;
    await db.delete('applications', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Audit Trail
  // ---------------------------------------------------------------------

  /// Records one action in the End-to-End Core Workflow chain (Document ->
  /// OCR -> Verify/Edit -> Master Data -> New App -> Auto-Fill -> Final
  /// Review -> Shramsetu -> Document Generation/Save -> Audit Trail).
  /// [details] should be a short, human-readable summary, not raw form
  /// data (this table isn't a data backup -- `applications.form_json`
  /// already holds that).
  static Future<int> logAction({
    int? applicationId,
    required String action,
    String? details,
  }) async {
    final db = await database;
    return db.insert('audit_trail', {
      'application_id': applicationId,
      'action': action,
      'details': details,
      'created_at': _nowIso(),
    });
  }

  static Future<List<Map<String, dynamic>>> getAuditTrail({int? applicationId}) async {
    final db = await database;
    if (applicationId != null) {
      return db.query(
        'audit_trail',
        where: 'application_id = ?',
        whereArgs: [applicationId],
        orderBy: 'created_at DESC',
      );
    }
    return db.query('audit_trail', orderBy: 'created_at DESC');
  }

  // ---------------------------------------------------------------------
  // Auto-Fill Mapping Versions
  // ---------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getActiveMappingVersion() async {
    final db = await database;
    final rows = await db.query('auto_fill_mapping_versions', where: 'is_active = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getMappingVersionHistory() async {
    final db = await database;
    return db.query('auto_fill_mapping_versions', orderBy: 'version_number DESC');
  }

  /// Inserts [mappingJson] as a new version and makes it active,
  /// deactivating whatever was active before (that row is kept, not
  /// deleted -- it remains available for rollback). [source] is a short
  /// label ('SEED', 'IMPORTED', 'ROLLBACK') for the version history UI.
  static Future<int> addMappingVersion({
    required String mappingJson,
    required String source,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.update('auto_fill_mapping_versions', {'is_active': 0});
      final maxRow = await txn.rawQuery(
        'SELECT MAX(version_number) as maxV FROM auto_fill_mapping_versions',
      );
      final nextVersion = ((maxRow.first['maxV'] as int?) ?? 0) + 1;
      return txn.insert('auto_fill_mapping_versions', {
        'version_number': nextVersion,
        'mapping_json': mappingJson,
        'is_active': 1,
        'source': source,
        'created_at': _nowIso(),
      });
    });
  }

  /// Makes an existing (already-stored) version active again, without
  /// creating a new row -- this IS the rollback operation. The
  /// version_number stays whatever it originally was, so version history
  /// accurately shows "we went back to v3," not a fabricated new version.
  static Future<void> setActiveMappingVersion(int versionId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('auto_fill_mapping_versions', {'is_active': 0});
      await txn.update(
        'auto_fill_mapping_versions',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [versionId],
      );
    });
  }
}
