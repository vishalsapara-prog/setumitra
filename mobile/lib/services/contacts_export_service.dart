import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

/// Contacts & Excel export (v4 requirements Settings item 5). Pulls from
/// Master Data (`establishment_master`), not from any single application
/// -- consistent with the whole point of Master Data being the
/// canonical, de-duplicated source.
///
/// Column structure (best-effort interpretation, disclosed in README):
/// Sr.No, Type, Establishment Name, Contractor Name, Mobile, Email ID,
/// EIN, Username, Password. Type is derived per record (see
/// `DatabaseService.deriveEstablishmentType`); Establishment Name and
/// Contractor Name are mutually exclusive per row -- whichever the Type
/// is NOT, that column is left blank, matching the requirement's
/// "Contractor Name if (blank for Establishment)" phrasing.
///
/// Username/Password are stored and exported in PLAIN TEXT, per the
/// requirements' explicit instruction that this was approved. This is a
/// real security tradeoff for a government app, made because it was
/// explicitly specified, not because it's a generally-recommended
/// pattern -- noted here rather than silently followed without comment.
class ContactsExportService {
  static Future<File> exportContactsExcel() async {
    final establishments = await DatabaseService.listEstablishments();

    final workbook = Excel.createExcel();
    // Excel.createExcel() auto-creates a default sheet named 'Sheet1' --
    // renaming it (rather than also accessing workbook['Contacts'], which
    // would CREATE a second, separate empty sheet alongside it) keeps the
    // output to the single intended sheet.
    workbook.rename('Sheet1', 'Contacts');
    final sheet = workbook['Contacts'];

    const headers = [
      'Sr.No', 'Type', 'Establishment Name', 'Contractor Name',
      'Mobile', 'Email ID', 'EIN', 'Username', 'Password',
    ];
    for (int col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).value =
          TextCellValue(headers[col]);
    }

    int srNo = 1;
    for (final est in establishments) {
      final type = await DatabaseService.deriveEstablishmentType(est.id!);
      final isContractor = type == 'Contractor';
      final row = srNo; // 1-based Sr.No == this row's index into the sheet (row 0 is header)
      final values = <CellValue>[
        IntCellValue(srNo),
        TextCellValue(type),
        TextCellValue(isContractor ? '' : est.establishmentName),
        TextCellValue(isContractor ? est.establishmentName : ''),
        TextCellValue(est.mobileNumber),
        TextCellValue(est.emailId),
        TextCellValue(est.einNumber),
        TextCellValue(est.username),
        TextCellValue(est.password),
      ];
      for (int col = 0; col < values.length; col++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = values[col];
      }
      srNo++;
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('Failed to encode the Contacts Excel workbook.');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outFile = File('${docsDir.path}/Setumitra_Contacts_$timestamp.xlsx');
    await outFile.writeAsBytes(bytes);

    await DatabaseService.logAction(
      action: 'CONTACTS_EXPORTED',
      details: '${establishments.length} records -> ${outFile.path}',
    );

    return outFile;
  }

  /// Separate export: a deduplicated list of every non-empty email
  /// address across Master Data, one per row, no other columns -- for
  /// bulk-emailing / mailing-list use, distinct from the full Contacts
  /// sheet above.
  static Future<File> exportUniqueEmailList() async {
    final establishments = await DatabaseService.listEstablishments();
    final uniqueEmails = <String>{};
    for (final est in establishments) {
      final email = est.emailId.trim();
      if (email.isNotEmpty) uniqueEmails.add(email);
    }
    final sortedEmails = uniqueEmails.toList()..sort();

    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'Unique Emails');
    final sheet = workbook['Unique Emails'];
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('Email ID');
    for (int i = 0; i < sortedEmails.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value =
          TextCellValue(sortedEmails[i]);
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('Failed to encode the Unique Email List workbook.');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outFile = File('${docsDir.path}/Setumitra_UniqueEmails_$timestamp.xlsx');
    await outFile.writeAsBytes(bytes);

    await DatabaseService.logAction(
      action: 'UNIQUE_EMAIL_LIST_EXPORTED',
      details: '${sortedEmails.length} unique emails -> ${outFile.path}',
    );

    return outFile;
  }
}
