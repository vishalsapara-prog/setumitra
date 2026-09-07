import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../models/form_model.dart';
import 'docx_template_service.dart';
import 'business_calculators_service.dart';
import 'database_service.dart';

/// Ties together the pieces that already existed independently but had no
/// caller: DocxTemplateService (built, unwired), the bundled .docx
/// templates (existed only on the backend side, now also bundled as
/// Flutter assets), and ManpowerCalculator's render context. This closes
/// the gap flagged in the last status report -- "Document Generation
/// button: built but unwired."
///
/// Part of the approved End-to-End Core Workflow's final step
/// (...-> Shramsetu -> Document Generation/Save -> Audit Trail).
class DocumentGenerationService {
  static const _contractorTemplateAsset = 'assets/word_templates/Shramsetu_Contractor_Template.docx';
  static const _peTemplateAsset = 'assets/word_templates/Shramsetu_Principal_Employer_Template.docx';

  /// Which template to use for a given moduleType. LICENSE uses the
  /// Contractor template -- per review_screen.dart's existing section-
  /// visibility logic, a LICENSE (FORM-25) applicant IS the Contractor,
  /// same as a plain REGISTRATION applicant; only PE_REGISTRATION's
  /// applicant is the Principal Employer.
  static String _templateAssetFor(String moduleType) {
    return moduleType == 'PE_REGISTRATION' ? _peTemplateAsset : _contractorTemplateAsset;
  }

  /// Generates the filled .docx for [formData] under [moduleType], saves
  /// it to the app's documents directory, logs a DOCUMENT_GENERATED audit
  /// entry, and returns the saved file. Throws if the template asset or
  /// rendering fails -- callers should catch and show a clear error
  /// rather than silently produce a blank/broken file.
  static Future<File> generate({
    required String moduleType,
    required ShramsetuFormModel formData,
    int? applicationId,
  }) async {
    final assetPath = _templateAssetFor(moduleType);
    final ByteData templateData = await rootBundle.load(assetPath);
    final Uint8List templateBytes = templateData.buffer.asUint8List(
      templateData.offsetInBytes,
      templateData.lengthInBytes,
    );

    final context = Map<String, dynamic>.from(formData.toJson());
    context.addAll(ManpowerCalculator.renderContext(context));

    final renderedBytes = DocxTemplateService.render(templateBytes, context);

    final docsDir = await getApplicationDocumentsDirectory();
    final safeName = formData.getString('establishment_name').trim().isEmpty
        ? 'Setumitra_Document'
        : formData.getString('establishment_name').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outFile = File('${docsDir.path}/${safeName}_${moduleType}_$timestamp.docx');
    await outFile.writeAsBytes(renderedBytes);

    await DatabaseService.logAction(
      applicationId: applicationId,
      action: 'DOCUMENT_GENERATED',
      details: 'moduleType=$moduleType, template=$assetPath, file=${outFile.path}',
    );

    return outFile;
  }
}
