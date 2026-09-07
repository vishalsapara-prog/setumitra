import 'dart:convert';
import '../models/portal_field_map.dart';
import 'database_service.dart';

/// Converts the Auto-Fill mapping from a hardcoded, rebuild-required Dart
/// file (`portal_field_map.dart`) into an admin-updatable, versioned,
/// rollback-capable config -- per the v4 requirements' "Website &
/// Auto-Fill Mapping" settings section (Check for Update, Mapping
/// Update, Current Version + Last Updated, Previous Mapping Restore/
/// Rollback, Auto-Fill Test).
///
/// Scope, stated honestly: "Check for Update" as specified implies
/// checking a REMOTE server for a newer mapping. There is no such server
/// in the Path B architecture (no backend is deployed/reachable by the
/// mobile app at all) -- so that specific remote-check mechanism is NOT
/// implemented here. What IS implemented, and genuinely satisfies the
/// underlying need ("update the mapping without an app rebuild"): local
/// JSON import (an admin can hand the app a new mapping file however it
/// reaches the device -- email, USB, a future Drive-sync feature),
/// version history, and rollback. All of these actually change what the
/// Auto-Fill in `webview_screen.dart` does at runtime -- this isn't a
/// settings screen that quietly does nothing.
///
/// The mapping is stored as JSON, never as code: import validates JSON
/// structure only (four string-to-string maps) and rejects anything
/// else, satisfying "NO arbitrary JS/code edit allowed."
class AutoFillMappingService {
  /// Ensures at least one version exists. On a fresh install, seeds
  /// Version 1 from the CURRENT hardcoded [PortalFieldMap] -- so the
  /// 127-of-207 confirmed mappings already built and verified aren't
  /// lost when this layer is introduced; they simply become the starting
  /// point of the configurable history.
  static Future<void> seedIfEmpty() async {
    final existing = await DatabaseService.getActiveMappingVersion();
    if (existing != null) return;

    final seedMapping = {
      'textAndDropdownFields': PortalFieldMap.textAndDropdownFields,
      'checkboxFields': PortalFieldMap.checkboxFields,
      'inferredFields': PortalFieldMap.inferredFields,
      'checkboxGroupIdPrefixes': PortalFieldMap.checkboxGroupIdPrefixes,
    };
    await DatabaseService.addMappingVersion(
      mappingJson: jsonEncode(seedMapping),
      source: 'SEED',
    );
  }

  /// Returns the currently-active mapping as four typed maps, ready for
  /// `webview_screen.dart` to use exactly like the old static
  /// `PortalFieldMap` calls did. Falls back to the hardcoded
  /// [PortalFieldMap] directly if, for any reason, no active DB version
  /// exists yet (e.g. [seedIfEmpty] hasn't run) -- Auto-Fill should never
  /// silently do nothing just because the configurable layer is empty.
  static Future<ResolvedMapping> getActiveMapping() async {
    final row = await DatabaseService.getActiveMappingVersion();
    if (row == null) {
      return ResolvedMapping(
        textAndDropdownFields: PortalFieldMap.textAndDropdownFields,
        checkboxFields: PortalFieldMap.checkboxFields,
        inferredFields: PortalFieldMap.inferredFields,
        checkboxGroupIdPrefixes: PortalFieldMap.checkboxGroupIdPrefixes,
        versionNumber: 0,
        source: 'HARDCODED_FALLBACK',
      );
    }
    final decoded = jsonDecode(row['mapping_json'] as String) as Map<String, dynamic>;
    return ResolvedMapping(
      textAndDropdownFields: _asStringMap(decoded['textAndDropdownFields']),
      checkboxFields: _asStringMap(decoded['checkboxFields']),
      inferredFields: _asStringMap(decoded['inferredFields']),
      checkboxGroupIdPrefixes: _asStringMap(decoded['checkboxGroupIdPrefixes']),
      versionNumber: row['version_number'] as int,
      source: row['source'] as String,
    );
  }

  static Map<String, String> _asStringMap(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// Validates [jsonString] is a well-formed mapping (an object with the
  /// four expected keys, each itself a flat string-to-string map) before
  /// it's ever imported -- rejects malformed input with a clear reason
  /// rather than importing garbage that then silently breaks Auto-Fill.
  static MappingValidationResult validateMappingJson(String jsonString) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e) {
      return MappingValidationResult(isValid: false, error: 'Not valid JSON: $e');
    }
    if (decoded is! Map) {
      return MappingValidationResult(isValid: false, error: 'Root must be a JSON object.');
    }
    const requiredKeys = [
      'textAndDropdownFields', 'checkboxFields', 'inferredFields', 'checkboxGroupIdPrefixes',
    ];
    for (final key in requiredKeys) {
      if (!decoded.containsKey(key)) {
        return MappingValidationResult(isValid: false, error: 'Missing required section: "$key".');
      }
      final section = decoded[key];
      if (section is! Map) {
        return MappingValidationResult(isValid: false, error: '"$key" must be an object of string:string pairs.');
      }
      for (final entry in section.entries) {
        if (entry.value is! String) {
          return MappingValidationResult(
            isValid: false,
            error: '"$key.${entry.key}" must be a plain string value (found ${entry.value.runtimeType}) -- no code, no nested objects.',
          );
        }
      }
    }
    return const MappingValidationResult(isValid: true);
  }

  /// Imports a new mapping version after validating it. Throws
  /// [ArgumentError] if validation fails -- callers should validate
  /// separately first (via [validateMappingJson]) to show the error
  /// before attempting the import, not catch this as a surprise.
  static Future<int> importMappingVersion(String jsonString) async {
    final validation = validateMappingJson(jsonString);
    if (!validation.isValid) {
      throw ArgumentError(validation.error);
    }
    return DatabaseService.addMappingVersion(mappingJson: jsonString, source: 'IMPORTED');
  }

  static Future<void> rollbackTo(int versionId) async {
    await DatabaseService.setActiveMappingVersion(versionId);
  }

  /// "Auto-Fill Test": a genuine structural check, not a placeholder --
  /// finds portal field NAMES claimed by more than one semantic key
  /// within the same section. This is informational, not a hard
  /// pass/fail: some duplicates are legitimate (e.g. the same field name
  /// appearing on two genuinely different portal pages) -- see README for
  /// the one already-known, already-verified-safe case in the built-in
  /// mapping. The admin reviews the list and judges each one.
  static MappingTestResult testMapping(ResolvedMapping mapping) {
    final duplicates = <String, List<String>>{};
    final byValue = <String, List<String>>{};
    mapping.textAndDropdownFields.forEach((key, value) {
      byValue.putIfAbsent(value, () => []).add(key);
    });
    byValue.forEach((portalName, semanticKeys) {
      if (semanticKeys.length > 1) {
        duplicates[portalName] = semanticKeys;
      }
    });

    final totalMapped = mapping.textAndDropdownFields.length +
        mapping.checkboxFields.length +
        mapping.inferredFields.length;

    return MappingTestResult(
      totalMappedFields: totalMapped,
      duplicatePortalNames: duplicates,
    );
  }
}

class ResolvedMapping {
  final Map<String, String> textAndDropdownFields;
  final Map<String, String> checkboxFields;
  final Map<String, String> inferredFields;
  final Map<String, String> checkboxGroupIdPrefixes;
  final int versionNumber;
  final String source;

  const ResolvedMapping({
    required this.textAndDropdownFields,
    required this.checkboxFields,
    required this.inferredFields,
    required this.checkboxGroupIdPrefixes,
    required this.versionNumber,
    required this.source,
  });

  /// Same fallback priority as the old static `PortalFieldMap.resolve()`.
  String? resolve(String semanticKey) {
    return textAndDropdownFields[semanticKey] ??
        checkboxFields[semanticKey] ??
        inferredFields[semanticKey];
  }

  bool isCheckboxField(String semanticKey) => checkboxFields.containsKey(semanticKey);
  bool isCheckboxGroupField(String semanticKey) => checkboxGroupIdPrefixes.containsKey(semanticKey);
}

class MappingValidationResult {
  final bool isValid;
  final String? error;
  const MappingValidationResult({required this.isValid, this.error});
}

class MappingTestResult {
  final int totalMappedFields;
  final Map<String, List<String>> duplicatePortalNames;
  const MappingTestResult({required this.totalMappedFields, required this.duplicatePortalNames});
}
