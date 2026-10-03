/// Provider-agnostic contract for the "AI AutoFill" feature's AI Mapping
/// Provider layer -- spec Section 18 ("AI PROVIDER ARCHITECTURE"):
///
/// ```
/// AI AutoFill
///     |
///     +-- Existing deterministic AutoFill
///     +-- AI Mapping Provider
///           +-- AIProvider (this interface)
///                 +-- GeminiProvider   (gemini_ai_provider.dart -- current)
///                 +-- <FutureProvider> (one new class, implementing this
///                                       same interface -- the mapping
///                                       engine in ai_mapping_service.dart
///                                       never needs to change)
/// ```
///
/// Nothing in [AiMappingService] (the orchestration/engine layer) ever
/// imports `gemini_ai_provider.dart` directly or checks "is this Gemini".
/// It only depends on this file's [AiProvider] interface and on the
/// provider-agnostic data shapes in `ai_mapping_models.dart`. The only
/// place that is allowed to know concrete provider class names is
/// [AiProviderFactory.create] at the bottom of this file -- adding a
/// second provider later means adding one `case` there and one new class
/// file; it does not mean touching the engine, the Preview UI, the Settings
/// UI, or the audit trail.
library;

import 'ai_provider_config_service.dart';
import 'gemini_ai_provider.dart';
import '../models/ai_mapping_models.dart';

/// Identifies which concrete [AiProvider] implementation is selected.
/// Adding a new provider means adding one new value here, one new class
/// implementing [AiProvider], and one new `case` in
/// [AiProviderFactory.create] -- nothing else in the app needs to change.
enum AiProviderId {
  gemini;

  String get storageValue => name;

  static AiProviderId fromStorageValue(String? value) {
    return AiProviderId.values.firstWhere(
      (p) => p.storageValue == value,
      orElse: () => AiProviderId.gemini,
    );
  }

  /// Label shown in Settings as "AI Provider: <label>" -- per the
  /// change-request's explicit wording: the feature is always "AI
  /// AutoFill"; the provider identity is surfaced only this way, never as
  /// the feature's own name.
  String get displayLabel {
    switch (this) {
      case AiProviderId.gemini:
        return 'Gemini';
    }
  }
}

/// Thrown by an [AiProvider] only for a *configuration* problem that the
/// user must fix before the provider can be used at all (no API key set,
/// invalid backend URL, etc). This is distinct from an ordinary runtime
/// failure (network error, timeout, quota, malformed response), which
/// [AiProvider.mapFields] must instead report as
/// [AiMappingResponse.failure] -- never as a thrown exception -- so a
/// transient AI outage can never crash the mapping flow or block the
/// existing deterministic AutoFill.
class AiProviderUnavailableException implements Exception {
  final String message;
  const AiProviderUnavailableException(this.message);
  @override
  String toString() => 'AiProviderUnavailableException: $message';
}

/// One portal field the mapping engine wants resolved. The actual
/// candidate values it might be resolved from are NOT duplicated here --
/// they are sent once, shared across the whole batch, as
/// [AiMappingRequest.sourceCandidates] -- since the same already-verified
/// form data is equally relevant to every field in the request.
class AiMappingRequestField {
  final AiPortalFieldDescriptor portalField;

  const AiMappingRequestField({required this.portalField});

  Map<String, dynamic> toJson() => {'portal_field': portalField.toJson()};
}

/// A sanitized request to map one portal's fields against the data this
/// app already holds. [AiMappingService] is solely responsible for
/// building this object and MUST have already:
///   1. Excluded every field where [AiPortalFieldDescriptor.isSensitive]
///      is true (password/OTP/CAPTCHA) -- per spec Sections 16/17/31.
///   2. Excluded session tokens, cookies and authorization headers.
///   3. Included only the minimum field/context data actually needed.
/// [AiProvider] implementations add a defensive re-check of (1) before
/// sending anything over the network, as defense in depth -- never as the
/// only safeguard.
class AiMappingRequest {
  final String portalName;
  final String serviceName;
  final List<AiMappingRequestField> fields;

  /// sourceFieldKey -> candidate value, shared across every field in
  /// [fields] (sent once per request, not duplicated per field). Keys are
  /// the app's internal semantic field names (e.g. `form_model.dart`'s
  /// section keys); values are already-verified, already-non-empty plain
  /// text, never anything sensitive. The AI chooses among/interprets
  /// these; it never invents a value with no candidate behind it at all.
  final Map<String, String> sourceCandidates;

  /// Confidence thresholds to echo back to the provider in the prompt (so
  /// the model's own stated confidence is calibrated against the same
  /// scale the app will classify it with); the app still re-validates and
  /// re-classifies every returned confidence value itself and never trusts
  /// the provider's own status label at face value.
  final AiConfidenceThresholds thresholds;

  const AiMappingRequest({
    required this.portalName,
    required this.serviceName,
    required this.fields,
    this.sourceCandidates = const {},
    this.thresholds = const AiConfidenceThresholds.defaults(),
  });

  /// Defense-in-depth guard: throws if any field in this request is
  /// sensitive. [AiMappingService] must never construct a request that
  /// fails this check; providers call it again before every network call.
  void assertNoSensitiveFields() {
    for (final f in fields) {
      if (f.portalField.isSensitive) {
        throw StateError(
          'Refusing to send sensitive field "${f.portalField.name}" '
          '(password/OTP/CAPTCHA) to an AI provider.',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'portal_name': portalName,
        'service_name': serviceName,
        'fields': fields.map((f) => f.toJson()).toList(),
        'source_candidates': sourceCandidates,
        'thresholds': thresholds.toJson(),
      };
}

/// The provider-agnostic AI Mapping Provider contract. Every concrete
/// provider (currently only [GeminiProvider] in gemini_ai_provider.dart)
/// implements exactly this interface.
abstract class AiProvider {
  /// Stable identity for this provider, used for "AI Provider: <id>"-style
  /// display and for audit-trail records -- never as the feature name.
  AiProviderId get id;

  /// Human-readable name for display, equal to `id.displayLabel` for the
  /// built-in providers.
  String get displayName;

  /// True if this provider currently has what it needs to run (e.g. an
  /// API key is configured) WITHOUT making a network call. The mapping
  /// engine checks this first and skips straight to deterministic-only
  /// behaviour if false, rather than attempting and failing a network call
  /// on every single AutoFill.
  Future<bool> isConfigured();

  /// A lightweight connectivity/credential check for the Settings screen's
  /// "Test AI Connection" button. Returns a short, user-displayable
  /// success message, or throws [AiProviderUnavailableException] /
  /// [AiMappingFormatException] describing exactly what failed. Must not
  /// alter any portal or application state.
  Future<String> testConnection();

  /// Sends [request] and returns a validated [AiMappingResponse].
  /// Implementations must:
  ///   - call `request.assertNoSensitiveFields()` before doing anything
  ///     else;
  ///   - catch every ordinary failure mode (network error, timeout,
  ///     non-2xx response, missing credentials, quota exceeded, malformed
  ///     JSON) and return `AiMappingResponse.failure(...)` -- NEVER let an
  ///     exception escape this method for those cases, since the mapping
  ///     engine and UI must be able to treat "AI unavailable" as a normal,
  ///     expected outcome, not a crash.
  Future<AiMappingResponse> mapFields(AiMappingRequest request);
}

/// The single, explicit extension point for adding a new AI provider.
/// This is the ONLY place in the app that is allowed to reference a
/// concrete [AiProvider] subclass by name (other than the subclass's own
/// file) -- [AiMappingService] and every UI screen go through
/// [AiProviderId] and this factory, never through `GeminiProvider` (or any
/// future provider class) directly. Dart permits the mutual import between
/// this file and `gemini_ai_provider.dart` (each is a normal library, not
/// a `part`), so adding `AiProviderId.otherProvider` plus one `case` below
/// is the entire integration surface for a new provider.
class AiProviderFactory {
  const AiProviderFactory._();

  static AiProvider create(AiProviderId id, AiProviderConfigService config) {
    switch (id) {
      case AiProviderId.gemini:
        return GeminiProvider(config);
    }
  }
}
