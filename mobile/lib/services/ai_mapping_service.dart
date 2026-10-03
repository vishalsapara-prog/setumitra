/// Orchestration layer for "AI AutoFill" -- this is the engine named in the
/// change request's architecture diagram:
/// ```
/// AI AutoFill
///     |
///     +-- Existing deterministic AutoFill   (PortalFieldMap / AutoFillMappingService)
///     +-- AI Mapping Provider               (AiProvider -> GeminiProvider today)
/// ```
///
/// This file is the ONLY place that combines the two. It:
///   1. Takes the portal fields actually present on the live page right
///      now (extracted by webview_screen.dart's DOM-inspection JS) and the
///      app's own verified data (the existing deterministic mapping +
///      [ShramsetuFormModel]).
///   2. Resolves as many fields as possible WITHOUT any AI call at all,
///      via [GujaratMasterData] (highest priority) and the existing
///      deterministic AutoFill mapping (second priority) -- these two
///      sources are structurally never sent to, or overridable by, the AI
///      provider: a field resolved here never enters the AI request at
///      all, which is what makes "AI must never silently overwrite
///      verified Master Data" true by construction rather than by a
///      runtime check that could have a bug in it.
///   3. Sends only the REMAINING unresolved, non-sensitive fields (plus
///      the app's already-collected, already-verified field values as
///      candidates) to the configured [AiProvider] in one batched request.
///   4. Re-validates everything the AI returns (dropdown fields must match
///      a real live option; every value is re-normalized per
///      [TextNormalizationService]; confidence is re-classified from the
///      configured, single-source-of-truth [AiConfidenceThresholds] rather
///      than trusting the provider's own stated status).
///   5. Returns ONE merged [AiMappingResponse] ready for the "Preview
///      Before Fill" screen (spec Section 14) -- deterministic-resolved
///      and AI-resolved fields appear side by side, with
///      [AiFieldMapping.mappingMethod] distinguishing them for the audit
///      trail.
///
/// AI AutoFill never runs when disabled in Settings, and degrades to
/// "nothing AI-resolved, everything else unaffected" whenever the provider
/// is unavailable -- the existing deterministic AutoFill in
/// webview_screen.dart is completely untouched by, and independent of,
/// this file (spec Section 3: "The existing deterministic AutoFill must
/// continue to work even when Gemini is unavailable").
library;

import 'dart:convert';

import 'ai_provider.dart';
import 'ai_provider_config_service.dart';
import 'auto_fill_mapping_service.dart';
import 'database_service.dart';
import 'fuzzy_match_service.dart';
import 'text_normalization_service.dart';
import '../models/ai_mapping_models.dart';
import '../models/form_model.dart';
import '../models/gujarat_master_data.dart';

/// Minimum fuzzy-match score (0-100, see [FuzzyMatchService.partialRatio])
/// for choosing a live dropdown option. Below this, the field is left as
/// [MappingStatus.reviewRequired] rather than guessing which option the
/// user meant -- consistent with spec Section 9/10: "Do NOT simply type
/// arbitrary text into a select field" / "If ambiguous: REVIEW_REQUIRED."
const double _dropdownMatchMinScore = 70.0;

class AiMappingService {
  AiMappingService({
    AiProviderConfigService? configService,
    AiProvider? providerOverride,
  })  : _configService = configService ?? AiProviderConfigService(),
        _providerOverride = providerOverride;

  final AiProviderConfigService _configService;

  /// Lets tests (and, if ever needed, a future "preview with a different
  /// provider" admin feature) inject a specific [AiProvider] instead of
  /// resolving one from [AiProviderConfigService]. Production code paths
  /// never set this.
  final AiProvider? _providerOverride;

  static const String portalName = 'Shramsetu';

  /// Builds the reverse lookup (real portal field name -> app semantic
  /// key) from the existing, protected deterministic mapping, so a DOM
  /// field can be recognised as "already known" without asking the AI.
  Map<String, String> _reversePortalNameLookup(ResolvedMapping mapping) {
    final out = <String, String>{};
    void addAll(Map<String, String> semanticKeyToPortalName) {
      semanticKeyToPortalName.forEach((semanticKey, portalFieldName) {
        // First mapping for a given portal name wins; a real portal field
        // name should only ever be claimed by one semantic key (see the
        // documented exception already called out in portal_field_map.dart
        // for 'pe_*' vs the applicant's own fields -- those never collide
        // because they are genuinely different DOM elements with
        // different real names, not the same name reused).
        out.putIfAbsent(portalFieldName, () => semanticKey);
      });
    }

    addAll(mapping.textAndDropdownFields);
    addAll(mapping.checkboxFields);
    addAll(mapping.inferredFields);
    return out;
  }

  /// The main entry point. [domFields] is the live, current set of portal
  /// field descriptors (webview_screen.dart's DOM extraction).
  /// [serviceName] is a short label for the current form/module (e.g.
  /// "REGISTRATION", "LICENSE") used only for display/audit, matching the
  /// existing `ShramsetuFormModel.moduleType` convention used elsewhere in
  /// this app.
  Future<AiMappingResponse> generateMappings({
    required List<AiPortalFieldDescriptor> domFields,
    required ShramsetuFormModel formData,
    required String serviceName,
  }) async {
    final deterministicMapping = await AutoFillMappingService.getActiveMapping();
    final reverseLookup = _reversePortalNameLookup(deterministicMapping);
    final formJson = formData.toJson();
    final thresholds = await _configService.getThresholds();

    final resolved = <AiFieldMapping>[];
    final aiRequestFields = <AiMappingRequestField>[];

    for (final field in domFields) {
      // Rule 1 (structural, not a runtime check): password/OTP/CAPTCHA
      // fields never enter this pipeline in any capacity, at any stage.
      if (field.isSensitive) continue;

      final kind = TextNormalizationService.classify(
        name: field.name,
        id: field.id,
        label: field.label,
        placeholder: field.placeholder,
        htmlType: field.type,
      );
      // classify() already treats password-like fields as
      // FieldKind.sensitiveNeverProcess as a second, independent check;
      // honour it even if field.isSensitive somehow missed a case.
      if (kind == FieldKind.sensitiveNeverProcess) continue;

      final semanticKey = reverseLookup[field.name] ?? reverseLookup[field.id];
      final rawSourceValue = semanticKey != null ? (formJson[semanticKey]?.toString() ?? '') : '';

      if (semanticKey != null && rawSourceValue.trim().isNotEmpty) {
        // Priority 1 (master data) and Priority 2 (existing deterministic
        // mapping + verified user/document data) are both resolvable
        // right here, with NO AI involvement -- this field never becomes
        // part of the AI request at all.
        resolved.add(
          _resolveFromTrustedSource(
            field: field,
            kind: kind,
            semanticKey: semanticKey,
            rawSourceValue: rawSourceValue,
          ),
        );
        continue;
      }

      // No trusted (master-data or deterministic) source is available for
      // this field -- it is a candidate for AI semantic mapping. The AI's
      // job is to find which already-verified value (shared across the
      // whole batch as sourceCandidates, built once below) semantically
      // belongs in THIS portal field, not to invent a new one.
      aiRequestFields.add(AiMappingRequestField(portalField: field));
    }

    final missing = <String>[];
    final conflicts = <String>[];
    final reviewRequired = <String>[];

    if (aiRequestFields.isNotEmpty) {
      final aiEnabled = await _configService.isEnabled();
      if (!aiEnabled) {
        // AI AutoFill is off: every otherwise-AI-eligible field is simply
        // left unresolved (not a crash, not a guess) -- the user can still
        // fill it manually or via the existing deterministic AutoFill if a
        // mapping is later added for it.
        missing.addAll(aiRequestFields.map((f) => f.portalField.name));
      } else {
        final provider = _providerOverride ?? AiProviderFactory.create(await _configService.getProviderId(), _configService);
        final isConfigured = await _safeIsConfigured(provider);
        if (!isConfigured) {
          missing.addAll(aiRequestFields.map((f) => f.portalField.name));
        } else {
          // Built once, shared across every field in this batch: every
          // already-collected, non-empty, non-sensitive form value --
          // never raw page/document content.
          final sourceCandidates = <String, String>{};
          formJson.forEach((key, value) {
            final text = value?.toString() ?? '';
            if (text.trim().isNotEmpty) sourceCandidates[key] = text;
          });
          final request = AiMappingRequest(
            portalName: portalName,
            serviceName: serviceName,
            fields: aiRequestFields,
            sourceCandidates: sourceCandidates,
            thresholds: thresholds,
          );
          final response = await provider.mapFields(request);
          if (!response.succeeded) {
            // Provider failed end-to-end (network/timeout/quota/etc.) --
            // degrade gracefully: nothing AI-resolved, nothing crashes.
            missing.addAll(aiRequestFields.map((f) => f.portalField.name));
          } else {
            final byPortalField = {for (final f in aiRequestFields) f.portalField.name: f.portalField};
            final answered = <String>{};
            for (final m in response.mappings) {
              final descriptor = byPortalField[m.portalField];
              if (descriptor == null) {
                // AI referenced a field that was never offered to it --
                // never trust an out-of-band field name; drop it.
                continue;
              }
              answered.add(m.portalField);
              resolved.add(_validateAndNormalizeAiMapping(m, descriptor, thresholds));
            }
            missing.addAll(response.missing);
            conflicts.addAll(response.conflicts);
            reviewRequired.addAll(response.reviewRequired);
            // Conservative-by-default: anything offered to the AI that it
            // neither mapped nor explicitly flagged is still "missing",
            // never silently dropped (spec: never assume silence is fine).
            for (final f in aiRequestFields) {
              if (!answered.contains(f.portalField.name) &&
                  !missing.contains(f.portalField.name) &&
                  !conflicts.contains(f.portalField.name) &&
                  !reviewRequired.contains(f.portalField.name)) {
                missing.add(f.portalField.name);
              }
            }
          }
        }
      }
    }

    return AiMappingResponse(
      mappings: resolved,
      missing: missing,
      conflicts: conflicts,
      reviewRequired: reviewRequired,
    );
  }

  Future<bool> _safeIsConfigured(AiProvider provider) async {
    try {
      return await provider.isConfigured();
    } catch (_) {
      return false;
    }
  }

  /// Resolves one field using master data (priority 1) and/or the
  /// existing deterministic mapping + verified form data (priority 2).
  /// Master data, when it recognises the value, wins even over what the
  /// deterministic mapping/form data literally stored (spec: "Use
  /// verified Master Data wherever available") -- e.g. a form value typed
  /// or OCR'd as "અમદાવાદ" still resolves to the master-data-correct
  /// "AHMEDABAD", not a raw transliteration of whatever was actually
  /// stored.
  AiFieldMapping _resolveFromTrustedSource({
    required AiPortalFieldDescriptor field,
    required FieldKind kind,
    required String semanticKey,
    required String rawSourceValue,
  }) {
    if ((kind == FieldKind.district || kind == FieldKind.state)) {
      final masterValue = GujaratMasterData.lookupPlaceName(rawSourceValue);
      if (masterValue != null) {
        final choice = field.type.toLowerCase() == 'select'
            ? _bestDropdownOptionOrFallback(field, masterValue)
            : _DropdownChoice(value: masterValue, matched: true);
        return AiFieldMapping(
          portalField: field.name,
          sourceField: semanticKey,
          value: choice.value,
          confidence: 1.0,
          reason: 'Resolved from verified Gujarat master data (${kind == FieldKind.district ? 'district' : 'state'}).',
          status: choice.matched ? MappingStatus.matched : MappingStatus.reviewRequired,
          mappingMethod: MappingMethod.masterData,
        );
      }
    }

    final normalized = TextNormalizationService.normalize(rawSourceValue, kind);
    if (field.type.toLowerCase() == 'select') {
      final choice = _bestDropdownOptionOrFallback(field, normalized);
      return AiFieldMapping(
        portalField: field.name,
        sourceField: semanticKey,
        value: choice.value,
        confidence: choice.matched ? 1.0 : 0.0,
        reason: choice.matched
            ? 'Matched an existing portal option using the existing deterministic AutoFill value.'
            : 'No existing portal option matched the known value closely enough to select automatically.',
        status: choice.matched ? MappingStatus.matched : MappingStatus.reviewRequired,
        mappingMethod: MappingMethod.deterministic,
      );
    }

    return AiFieldMapping(
      portalField: field.name,
      sourceField: semanticKey,
      value: normalized,
      confidence: 1.0,
      reason: 'Resolved from the existing deterministic AutoFill mapping and already-verified form data.',
      status: MappingStatus.matched,
      mappingMethod: MappingMethod.deterministic,
    );
  }

  /// Re-validates one AI-proposed mapping against the field it was
  /// actually offered for:
  ///   - re-normalizes the value per [TextNormalizationService] (never
  ///     trusts the AI's own casing/transliteration at face value);
  ///   - for a `select` field, requires the value to equal one of the
  ///     field's real, live options -- if the AI proposed free text that
  ///     matches no option closely enough, the mapping is downgraded to
  ///     [MappingStatus.reviewRequired] rather than written in as typed
  ///     text (spec Section 9/10);
  ///   - re-classifies confidence from the single configured
  ///     [AiConfidenceThresholds] rather than trusting any status the
  ///     provider itself claimed.
  AiFieldMapping _validateAndNormalizeAiMapping(
    AiFieldMapping aiMapping,
    AiPortalFieldDescriptor descriptor,
    AiConfidenceThresholds thresholds,
  ) {
    final kind = TextNormalizationService.classify(
      name: descriptor.name,
      id: descriptor.id,
      label: descriptor.label,
      placeholder: descriptor.placeholder,
      htmlType: descriptor.type,
    );
    if (kind == FieldKind.sensitiveNeverProcess) {
      // Defense in depth: this should be structurally unreachable (such
      // fields are filtered out of aiRequestFields before the AI is ever
      // called), but a mapping for one is refused outright rather than
      // ever being surfaced for fill.
      return aiMapping.withStatus(MappingStatus.missing).withValue(
            '',
            newReason: 'Refused: this field must never be processed by AI AutoFill.',
          );
    }

    if (descriptor.type.toLowerCase() == 'select') {
      final choice = _bestDropdownOptionOrFallback(descriptor, aiMapping.value);
      if (!choice.matched) {
        return aiMapping.withStatus(MappingStatus.reviewRequired).withValue(
              aiMapping.value,
              newReason:
                  '${aiMapping.reason} (AI-proposed value did not match any existing portal option closely enough; manual selection required.)',
            );
      }
      final status = thresholds.classify(aiMapping.confidence);
      return AiFieldMapping(
        portalField: aiMapping.portalField,
        sourceField: aiMapping.sourceField,
        value: choice.value,
        confidence: aiMapping.confidence,
        reason: aiMapping.reason,
        status: status,
        mappingMethod: MappingMethod.aiSemantic,
      );
    }

    final renormalized = TextNormalizationService.normalize(aiMapping.value, kind);
    final status = thresholds.classify(aiMapping.confidence);
    return AiFieldMapping(
      portalField: aiMapping.portalField,
      sourceField: aiMapping.sourceField,
      value: renormalized,
      confidence: aiMapping.confidence,
      reason: aiMapping.reason,
      status: status,
      mappingMethod: MappingMethod.aiSemantic,
    );
  }

  /// Picks the best live `<select>` option for [targetValue] using fuzzy
  /// matching against each option's label and value, never returning free
  /// text that is not one of the field's real options.
  _DropdownChoice _bestDropdownOptionOrFallback(AiPortalFieldDescriptor field, String targetValue) {
    if (field.options.isEmpty || targetValue.trim().isEmpty) {
      return _DropdownChoice(value: targetValue, matched: false);
    }
    String? bestValue;
    double bestScore = -1;
    for (final option in field.options) {
      final scoreByLabel = FuzzyMatchService.partialRatio(targetValue, option.label);
      final scoreByValue = FuzzyMatchService.partialRatio(targetValue, option.value);
      final score = scoreByLabel > scoreByValue ? scoreByLabel : scoreByValue;
      if (score > bestScore) {
        bestScore = score;
        bestValue = option.value;
      }
    }
    if (bestValue != null && bestScore >= _dropdownMatchMinScore) {
      return _DropdownChoice(value: bestValue, matched: true);
    }
    return _DropdownChoice(value: targetValue, matched: false);
  }

  /// Persists one audit-trail row per confirmed/rejected mapping, per spec
  /// Section 23 ("AUDIT TRAIL"). Reuses the app's existing, protected,
  /// generic `audit_trail` table (via `DatabaseService.logAction`) rather
  /// than adding a new table -- the required fields (timestamp, portal/
  /// service, portal field, source field, mapped value, confidence,
  /// provider, mapping method, user confirmation, final value) all fit in
  /// a structured JSON `details` payload, so no schema change to the
  /// protected `database_service.dart` file is needed at all. Never
  /// stores secrets: sensitive fields never reach this method in the
  /// first place (see [generateMappings]).
  Future<void> recordAudit({
    required List<AiFieldMapping> mappings,
    required Set<String> confirmedPortalFields,
    required String serviceName,
    int? applicationId,
  }) async {
    final providerId = await _configService.getProviderId();
    for (final m in mappings) {
      final userConfirmed = confirmedPortalFields.contains(m.portalField);
      await DatabaseService.logAction(
        applicationId: applicationId,
        action: 'AI_AUTOFILL_FIELD_MAPPED',
        details: jsonEncode({
          'portal': portalName,
          'service': serviceName,
          'portal_field': m.portalField,
          'source_field': m.sourceField,
          'mapped_value': m.value,
          'confidence': m.confidence,
          'provider': m.mappingMethod == MappingMethod.aiSemantic ? providerId.displayLabel : 'N/A',
          'mapping_method': m.mappingMethod.name,
          'status': m.status.name,
          'user_confirmed': userConfirmed,
          'final_value': userConfirmed ? m.value : null,
        }),
      );
    }
  }
}

class _DropdownChoice {
  final String value;
  final bool matched;
  const _DropdownChoice({required this.value, required this.matched});
}
