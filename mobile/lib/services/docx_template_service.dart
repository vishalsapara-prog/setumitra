import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Renders `{{tag}}`-style Word template placeholders in pure Dart, as a
/// deliberately narrow alternative to depending on the Dart `docxtpl`
/// package (found at version 0.0.1, >1 year since last GitHub activity --
/// a real risk signal for a government-facing app, documented in the
/// README rather than picked silently either way).
///
/// SCOPE, STATED HONESTLY: this is NOT a general-purpose docxtpl
/// replacement. It does plain string substitution of `{{tag}}` markers
/// directly in the underlying `word/document.xml`, with no support for
/// Jinja2-style loops, conditionals, or rich-text runs. This is safe
/// specifically for `Shramsetu_Contractor_Template.docx` and
/// `Shramsetu_Principal_Employer_Template.docx` because both were already
/// verified (see README, docx skill's split-run checker) to have every
/// `{{tag}}` placeholder contained in a single XML text run -- i.e. Word
/// never split a placeholder across runs when the templates were built.
/// If a *different* template is ever swapped in without that same
/// verification, this approach could silently fail to find split-run
/// placeholders; [findUnresolvedTags] below exists specifically to catch
/// that class of problem before it ships silently.
class DocxTemplateService {
  static final RegExp _tagPattern = RegExp(r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}');

  /// Renders [templateBytes] (the raw bytes of a .docx file) against
  /// [context], returning the rendered .docx bytes. Any `{{tag}}` found in
  /// `word/document.xml` with a matching key in [context] is replaced with
  /// that value (XML-escaped); any `{{tag}}` with NO matching key is
  /// replaced with an empty string, matching the Python backend's
  /// behavior of always supplying every field (defaulting to `""`) via
  /// `ShramsetuFormModel`'s Pydantic field defaults.
  static Uint8List render(Uint8List templateBytes, Map<String, dynamic> context) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final documentXmlFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw StateError('word/document.xml not found -- is this a valid .docx file?'),
    );

    final xmlBytes = documentXmlFile.content as List<int>;
    final xmlString = utf8.decode(xmlBytes);

    final renderedXml = xmlString.replaceAllMapped(_tagPattern, (match) {
      final key = match.group(1)!;
      final value = context.containsKey(key) ? context[key] : '';
      return _xmlEscape(_stringifyValue(value));
    });

    final renderedBytes = Uint8List.fromList(utf8.encode(renderedXml));

    final outArchive = Archive();
    for (final file in archive.files) {
      if (file.name == 'word/document.xml') {
        outArchive.addFile(ArchiveFile('word/document.xml', renderedBytes.length, renderedBytes));
      } else if (file.isFile) {
        outArchive.addFile(ArchiveFile(file.name, file.size, file.content));
      }
    }

    final encoded = ZipEncoder().encode(outArchive);
    if (encoded == null) {
      throw StateError('ZipEncoder failed to encode the rendered document.');
    }
    return Uint8List.fromList(encoded);
  }

  /// Scans [templateBytes] for any `{{...}}`-*looking* text that the
  /// simple regex above would NOT recognize as a clean tag (e.g. a
  /// placeholder split across XML runs by Word, which shows up as
  /// `{{` and `tag}}` in separate, non-adjacent text nodes). Returns any
  /// suspicious fragments found, so a template swap can be checked before
  /// it's trusted -- this is the safety net for this service's narrow
  /// scope, not a fix for split runs (which this service cannot repair).
  static List<String> findUnresolvedTags(Uint8List templateBytes) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final documentXmlFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw StateError('word/document.xml not found.'),
    );
    final xmlString = utf8.decode(documentXmlFile.content as List<int>);
    final strippedOfTags = xmlString.replaceAll(RegExp(r'<[^>]+>'), '');
    final suspicious = <String>{};
    for (final m in RegExp(r'\{\{[^}]{0,60}').allMatches(strippedOfTags)) {
      if (!_tagPattern.hasMatch(m.group(0)! + '}}')) {
        suspicious.add(m.group(0)!);
      }
    }
    return suspicious.toList();
  }

  static String _stringifyValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is double) {
      // Avoid "25000.0" for whole-number amounts; keep 2dp otherwise.
      return value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
    }
    return value.toString();
  }

  static String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
