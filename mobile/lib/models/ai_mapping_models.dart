/// Provider-agnostic data contracts for the "AI AutoFill" feature.
///
/// Nothing in this file knows what "Gemini" is. The feature name
/// end-to-end is "AI AutoFill"; a concrete AI provider (GeminiAiProvider,
/// in gemini_ai_provider.dart) implements the [AiProvider] interface
/// declared in ai_provider.dart and produces an [AiMappingResponse] shaped
/// exactly as defined here. Adding a second provider later means writing
/// one new class that returns this same shape -- nothing in the mapping
/// engine, the preview UI, or the audit trail needs to change.
library;

import 'dart:convert';

/// How confident the mapping engine is that [AiFieldMapping.value] is
/// correct, translated from the raw confidence score via
/// [AiConfidenceThresholds.classify].
enum MappingStatus {
  /// Confidence at/above the auto-fill threshold -- safe to pre-fill, but
  /// the user still sees it in the Preview screen before anything is
  /// written to the portal (per "Preview Before Fill").
  matched,

  /// Confidence between the review and auto-fill thresholds, or a field
  /// the AI itself flagged as ambiguous -- must not be filled without the
  /// user explicitly confirming this specific row.
  reviewRequired,

  /// No trusted source value was available for this portal field at all
  /// (per "AI must never invent missing data" -- this is the explicit
  /// non-invention signal, never a guess).
  missing,

  /// Two or more trusted sources disagree on the value for this field.
  /// Never auto-resolved; always surfaced to the user.
  conflict,
}

/// Configurable confidence cut-offs (spec: "these thresholds must be
/// configurable. Do not hard-code them in multiple places."). This is the
/// SINGLE place classification happens -- every caller goes through
/// [classify], never compares a raw double to a literal itself.
class AiConfidenceThresholds {
  /// >= this -> [MappingStatus.matched] (eligible for automatic mapping).
  final double autoFillMinConfidence;

  /// >= this (and < [autoFillMinConfidence]) -> [MappingStatus.reviewRequired].
  /// Below this -> never offered for auto-fill at all; still shown in the
  /// preview as "not confident enough" (handled by the AI mapping service,
  /// not this class) rather than silently dropped.
  final double reviewMinConfidence;

  const AiConfidenceThresholds({
    this.autoFillMinConfidence = 0.95,
    this.reviewMinConfidence = 0.80,
  });

  const AiConfidenceThresholds.defaults() : this();

  MappingStatus classify(double confidence) {
    if (confidence >= autoFillMinConfidence) return MappingStatus.matched;
    if (confidence >= reviewMinConfidence) return MappingStatus.reviewRequired;
    // Below the review floor: still surfaced in the UI (never silently
    // discarded), but the caller is responsible for never offering it for
    // one-tap auto-fill. Reusing reviewRequired here would blur "the AI
    // thinks this is probably right, just double check" with "the AI
    // barely has a guess" -- the mapping service keeps these distinguishable
    // via the raw confidence value it still carries alongside the status.
    return MappingStatus.reviewRequired;
  }

  Map<String, dynamic> toJson() => {
        'autoFillMinConfidence': autoFillMinConfidence,
        'reviewMinConfidence': reviewMinConfidence,
      };

  factory AiConfidenceThresholds.fromJson(Map<String, dynamic> json) {
    return AiConfidenceThresholds(
      autoFillMinConfidence: (json['autoFillMinConfidence'] as num?)?.toDouble() ?? 0.95,
      reviewMinConfidence: (json['reviewMinConfidence'] as num?)?.toDouble() ?? 0.80,
    );
  }
}

/// One real, selectable value a portal `<select>`/dropdown field currently
/// offers, extracted live from the WebView DOM -- never invented. The AI
/// mapping layer is only ever allowed to choose among these for a dropdown
/// field (see ai_mapping_service.dart's `_resolveDropdownValue`); it is
/// structurally prevented from writing free text into a `<select>`.
class AiDropdownOption {
  final String value;
  final String label;

  const AiDropdownOption({required this.value, required this.label});

  factory AiDropdownOption.fromJson(Map<String, dynamic> json) {
    return AiDropdownOption(
      value: (json['value'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// One form field as it actually exists on the currently-loaded portal
/// page right now, extracted by the WebView DOM-inspection JS
/// (webview_screen.dart's `_extractPortalFieldDescriptors`). This -- not
/// raw page HTML -- is what gets sent to the AI provider, per "use the
/// minimum necessary data" / "do not send unnecessary page contents to AI."
class AiPortalFieldDescriptor {
  final String name;
  final String? id;
  final String? label;
  final String? placeholder;
  final String type; // 'text' | 'select' | 'checkbox' | 'textarea' | 'date' | 'email' | ...
  final bool required;
  final List<AiDropdownOption> options; // non-empty only for type == 'select'
  final String? nearbyContext;

  const AiPortalFieldDescriptor({
    required this.name,
    this.id,
    this.label,
    this.placeholder,
    required this.type,
    this.required = false,
    this.options = const [],
    this.nearbyContext,
  });

  bool get isSensitive {
    final haystack = '$name ${id ?? ''} ${label ?? ''} ${placeholder ?? ''}'.toLowerCase();
    return haystack.contains('otp') ||
        haystack.contains('captcha') ||
        haystack.contains('password') ||
        type.toLowerCase() == 'password';
  }

  factory AiPortalFieldDescriptor.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = <AiDropdownOption>[];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is Map) {
          options.add(AiDropdownOption.fromJson(Map<String, dynamic>.from(o)));
        }
      }
    }
    return AiPortalFieldDescriptor(
      name: (json['name'] ?? '').toString(),
      id: json['id']?.toString(),
      label: json['label']?.toString(),
      placeholder: json['placeholder']?.toString(),
      type: (json['type'] ?? 'text').toString(),
      required: json['required'] == true,
      options: options,
      nearbyContext: json['nearbyContext']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (id != null) 'id': id,
        if (label != null) 'label': label,
        if (placeholder != null) 'placeholder': placeholder,
        'type': type,
        'required': required,
        if (options.isNotEmpty) 'options': options.map((o) => o.toJson()).toList(),
        if (nearbyContext != null) 'nearbyContext': nearbyContext,
      };
}

/// How a mapping's value was actually determined -- recorded for the
/// audit trail (spec Section 23's "mapping method" field) and to let the
/// mapping engine apply the source-data priority order correctly (a
/// [masterData] or [deterministic] mapping is never sent to the AI
/// provider for reconsideration; see ai_mapping_service.dart).
enum MappingMethod {
  /// Resolved from [GujaratMasterData] (district/state name) -- the
  /// highest-priority source; never overridden by anything else.
  masterData,

  /// Resolved from the existing, protected deterministic AutoFill mapping
  /// (`PortalFieldMap` / `AutoFillMappingService`) plus already-verified
  /// user/document data already held by the app.
  deterministic,

  /// Resolved by the AI provider's semantic mapping -- used only for
  /// portal fields the two higher-priority sources could not resolve.
  aiSemantic,

  /// Entered or corrected by the user directly in the Preview screen.
  userManual,
}

/// One resolved field mapping. The provider-facing wire shape matches the
/// spec's mandated JSON exactly:
/// ```
/// {"portal_field": "...", "source_field": "...", "value": "...",
///  "confidence": 0.0-1.0, "reason": "..."}
/// ```
/// [mappingMethod] is additional, app-internal metadata (not part of the
/// AI provider's wire contract) carried alongside every mapping so the
/// Preview screen and the audit trail can show/record exactly how each
/// value was actually determined, per spec Section 23 ("mapping method").
class AiFieldMapping {
  final String portalField;
  final String? sourceField;
  final String value;
  final double confidence;
  final String reason;
  final MappingStatus status;
  final MappingMethod mappingMethod;

  const AiFieldMapping({
    required this.portalField,
    this.sourceField,
    required this.value,
    required this.confidence,
    required this.reason,
    required this.status,
    this.mappingMethod = MappingMethod.aiSemantic,
  });

  AiFieldMapping withStatus(MappingStatus newStatus) => AiFieldMapping(
        portalField: portalField,
        sourceField: sourceField,
        value: value,
        confidence: confidence,
        reason: reason,
        status: newStatus,
        mappingMethod: mappingMethod,
      );

  AiFieldMapping withValue(String newValue, {String? newReason}) => AiFieldMapping(
        portalField: portalField,
        sourceField: sourceField,
        value: newValue,
        confidence: confidence,
        reason: newReason ?? reason,
        status: status,
        mappingMethod: mappingMethod,
      );

  Map<String, dynamic> toJson() => {
        'portal_field': portalField,
        if (sourceField != null) 'source_field': sourceField,
        'value': value,
        'confidence': confidence,
        'reason': reason,
        'status': status.name,
        'mapping_method': mappingMethod.name,
      };
}

/// Thrown when an AI provider's raw output cannot be trusted: not valid
/// JSON, missing a required key, or a value of the wrong type. Per spec:
/// "Malformed or unexpected AI output must be rejected safely" -- callers
/// catch this and treat it exactly like [AiMappingResponse.providerFailed],
/// never half-parse a partial/corrupt result.
class AiMappingFormatException implements Exception {
  final String message;
  const AiMappingFormatException(this.message);
  @override
  String toString() => 'AiMappingFormatException: $message';
}

/// The full, structured result of one AI mapping request -- this is the
/// ONLY shape the rest of the app ever sees from an [AiProvider]; raw
/// provider-specific response formats never leak past the provider's own
/// implementation file.
class AiMappingResponse {
  final List<AiFieldMapping> mappings;
  final List<String> missing;
  final List<String> conflicts;
  final List<String> reviewRequired;

  /// Non-null only when the provider call itself failed (network error,
  /// non-200 response, missing API key, timeout, etc.) rather than
  /// succeeding with an empty/partial result. The mapping service treats
  /// this exactly like "AI unavailable" -- deterministic AutoFill must
  /// keep working regardless.
  final String? providerError;

  const AiMappingResponse({
    this.mappings = const [],
    this.missing = const [],
    this.conflicts = const [],
    this.reviewRequired = const [],
    this.providerError,
  });

  const AiMappingResponse.failure(String error)
      : mappings = const [],
        missing = const [],
        conflicts = const [],
        reviewRequired = const [],
        providerError = error;

  bool get succeeded => providerError == null;

  /// Parses and VALIDATES the structured JSON shape the spec mandates:
  /// ```
  /// {
  ///   "mappings": [ {"portal_field": "...", "source_field": "...",
  ///                  "value": "...", "confidence": 0.97, "reason": "..."} ],
  ///   "missing": [...],
  ///   "conflicts": [...],
  ///   "review_required": [...]
  /// }
  /// ```
  /// [thresholds] turns each mapping's raw confidence into a
  /// [MappingStatus]. Throws [AiMappingFormatException] -- never returns a
  /// partially-valid result -- on anything that doesn't match this shape,
  /// so a malformed AI response can never silently become a wrong-but-
  /// plausible-looking mapping.
  factory AiMappingResponse.fromJsonString(
    String raw, {
    AiConfidenceThresholds thresholds = const AiConfidenceThresholds.defaults(),
  }) {
    dynamic decoded;
    try {
      decoded = _jsonDecode(raw);
    } catch (e) {
      throw AiMappingFormatException('AI response was not valid JSON: $e');
    }
    if (decoded is! Map) {
      throw const AiMappingFormatException('AI response root must be a JSON object.');
    }
    final map = Map<String, dynamic>.from(decoded);

    final rawMappings = map['mappings'];
    if (rawMappings is! List) {
      throw const AiMappingFormatException('"mappings" must be a JSON array.');
    }
    final mappings = <AiFieldMapping>[];
    for (final entry in rawMappings) {
      if (entry is! Map) {
        throw const AiMappingFormatException('Each "mappings" entry must be a JSON object.');
      }
      final m = Map<String, dynamic>.from(entry);
      final portalField = m['portal_field'];
      final value = m['value'];
      final confidence = m['confidence'];
      final reason = m['reason'];
      if (portalField is! String || portalField.isEmpty) {
        throw const AiMappingFormatException('Each mapping requires a non-empty string "portal_field".');
      }
      if (value is! String) {
        throw AiMappingFormatException('Mapping for "$portalField" requires a string "value".');
      }
      if (confidence is! num || confidence < 0 || confidence > 1) {
        throw AiMappingFormatException(
          'Mapping for "$portalField" requires a numeric "confidence" between 0.0 and 1.0.',
        );
      }
      if (reason is! String) {
        throw AiMappingFormatException('Mapping for "$portalField" requires a string "reason".');
      }
      final sourceField = m['source_field'];
      mappings.add(AiFieldMapping(
        portalField: portalField,
        sourceField: sourceField is String ? sourceField : null,
        value: value,
        confidence: confidence.toDouble(),
        reason: reason,
        status: thresholds.classify(confidence.toDouble()),
      ));
    }

    return AiMappingResponse(
      mappings: mappings,
      missing: _asStringList(map['missing']),
      conflicts: _asStringList(map['conflicts']),
      reviewRequired: _asStringList(map['review_required']),
    );
  }

  static List<String> _asStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  static dynamic _jsonDecode(String raw) => jsonDecode(raw);
}
