/// The current concrete [AiProvider] implementation: Gemini.
///
/// This is the ONLY file in the app that references the Gemini REST API,
/// its request/response envelope shape, or its model name. Everything
/// above this file (the Settings UI, [AiMappingService], the Preview
/// screen, the audit trail) depends only on the provider-agnostic
/// [AiProvider] interface -- per the change request: "Design the provider
/// layer so another AI provider can be added later without rewriting the
/// AutoFill engine."
///
/// Two call paths are supported, selected automatically by whether a
/// backend URL is configured (spec Section 19, "API KEY SECURITY"):
///   - Backend configured (preferred): `Flutter APK -> secure backend API
///     -> Gemini API`. The Gemini API key never touches the device at all
///     in this mode.
///   - No backend configured (fallback, so AI AutoFill still works for a
///     deploying office with no server to stand up): the device calls the
///     Gemini API directly, using an API key the user enters once in
///     Settings and which is stored only in the OS keystore via
///     [AiProviderConfigService] -- never compiled into the APK, never
///     logged, never written to the audit trail.
///
/// IMPORTANT, HONEST LIMITATION: this sandboxed build/dev environment has
/// no outbound network access to generativelanguage.googleapis.com (every
/// non-package-registry host is blocked by the build sandbox's egress
/// allowlist), so the exact current Gemini model identifier and the live
/// request/response shape below could NOT be exercised against the real
/// API while writing this file. [_defaultModel] is a plain constant for
/// exactly this reason -- so it can be corrected in one place the moment
/// it is verified against a real device with real connectivity and a real
/// API key, without touching any other file in the AI AutoFill feature.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';
import 'ai_provider_config_service.dart';
import '../models/ai_mapping_models.dart';

class GeminiProvider implements AiProvider {
  GeminiProvider(this._config, {http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final AiProviderConfigService _config;
  final http.Client _httpClient;

  /// See the library-level doc comment above: verify/update this against
  /// https://ai.google.dev's current model list before relying on it in
  /// production. Using an outdated model id fails safely -- [mapFields]
  /// returns [AiMappingResponse.failure] and the existing deterministic
  /// AutoFill keeps working (spec Section 3) -- it just means AI AutoFill
  /// itself silently has nothing to offer until the id is corrected.
  static const String _defaultModel = 'gemini-2.0-flash';
  static const Duration _requestTimeout = Duration(seconds: 25);

  @override
  AiProviderId get id => AiProviderId.gemini;

  @override
  String get displayName => AiProviderId.gemini.displayLabel;

  @override
  Future<bool> isConfigured() async {
    final backendUrl = await _config.getBackendUrl();
    if (backendUrl != null) return true;
    return _config.hasApiKey(AiProviderId.gemini);
  }

  @override
  Future<String> testConnection() async {
    final backendUrl = await _config.getBackendUrl();
    try {
      if (backendUrl != null) {
        final response = await _httpClient.get(Uri.parse('$backendUrl/health')).timeout(_requestTimeout);
        if (response.statusCode == 200) {
          return 'Connected to the AI AutoFill backend at $backendUrl.';
        }
        throw AiProviderUnavailableException('Backend responded with HTTP ${response.statusCode}.');
      }

      final apiKey = await _config.getApiKey(AiProviderId.gemini);
      if (apiKey == null || apiKey.isEmpty) {
        throw const AiProviderUnavailableException(
          'No Gemini API key is configured. Add one in AI AutoFill settings, '
          'or configure a backend URL instead.',
        );
      }

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_defaultModel:generateContent',
      );
      final response = await _httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': 'Respond with exactly one word: OK'},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0},
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw AiProviderUnavailableException(
          'Gemini API responded with HTTP ${response.statusCode}: ${_truncate(response.body)}',
        );
      }
      return 'Connected to Gemini ($_defaultModel) directly from the device.';
    } on AiProviderUnavailableException {
      rethrow;
    } catch (e) {
      throw AiProviderUnavailableException('AI connection test failed: $e');
    }
  }

  @override
  Future<AiMappingResponse> mapFields(AiMappingRequest request) async {
    try {
      request.assertNoSensitiveFields();
    } on StateError catch (e) {
      return AiMappingResponse.failure(e.message);
    }

    if (request.fields.isEmpty) {
      // Nothing to map is a normal, successful outcome, not a failure.
      return const AiMappingResponse();
    }

    try {
      final backendUrl = await _config.getBackendUrl();
      final String rawJson;
      if (backendUrl != null) {
        rawJson = await _callBackend(backendUrl, request);
      } else {
        final apiKey = await _config.getApiKey(AiProviderId.gemini);
        if (apiKey == null || apiKey.isEmpty) {
          return const AiMappingResponse.failure(
            'Gemini is not configured: no API key and no backend URL are set.',
          );
        }
        rawJson = await _callGeminiDirect(apiKey, request);
      }
      return AiMappingResponse.fromJsonString(rawJson, thresholds: request.thresholds);
    } on AiMappingFormatException catch (e) {
      return AiMappingResponse.failure('AI returned an invalid response: ${e.message}');
    } catch (e) {
      // Network error, timeout, non-2xx, quota exceeded, etc. -- every
      // ordinary failure mode becomes a clean "AI unavailable" result,
      // never a thrown exception (see AiProvider.mapFields contract).
      return AiMappingResponse.failure('AI provider call failed: $e');
    }
  }

  Future<String> _callBackend(String backendUrl, AiMappingRequest request) async {
    final uri = Uri.parse('$backendUrl/ai-autofill/map');
    final response = await _httpClient
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'instruction': _instructionText,
            'request': request.toJson(),
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw AiProviderUnavailableException(
        'Backend responded with HTTP ${response.statusCode}: ${_truncate(response.body)}',
      );
    }
    return response.body;
  }

  Future<String> _callGeminiDirect(String apiKey, AiMappingRequest request) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_defaultModel:generateContent',
    );
    final response = await _httpClient
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': _buildPrompt(request)},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw AiProviderUnavailableException(
        'Gemini API responded with HTTP ${response.statusCode}: ${_truncate(response.body)}',
      );
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const AiMappingFormatException('Gemini response envelope was not a JSON object.');
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiMappingFormatException('Gemini response contained no candidates.');
    }
    final firstCandidate = candidates.first;
    if (firstCandidate is! Map) {
      throw const AiMappingFormatException('Gemini candidate was not a JSON object.');
    }
    final content = firstCandidate['content'];
    if (content is! Map) {
      throw const AiMappingFormatException('Gemini candidate had no content.');
    }
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const AiMappingFormatException('Gemini candidate content had no parts.');
    }
    final firstPart = parts.first;
    if (firstPart is! Map || firstPart['text'] is! String || (firstPart['text'] as String).trim().isEmpty) {
      throw const AiMappingFormatException('Gemini candidate part had no usable text.');
    }
    return firstPart['text'] as String;
  }

  String _buildPrompt(AiMappingRequest request) {
    final buf = StringBuffer()
      ..writeln(_instructionText)
      ..writeln()
      ..writeln('REQUEST JSON:')
      ..writeln(jsonEncode(request.toJson()));
    return buf.toString();
  }

  static String _truncate(String s) => s.length > 300 ? '${s.substring(0, 300)}...' : s;

  static const String _instructionText = '''
You are a field-mapping assistant for a Gujarat Labour Department ("Shramsetu") government registration portal. You perform SEMANTIC FIELD MAPPING ONLY.

The request JSON's "source_candidates" object holds every already-verified value available to you, shared across all fields below -- keys are internal field names, values are their known text.

Rules you must follow exactly:
1. For each portal field listed in "fields", choose the best-matching value from "source_candidates", or synthesize a value only by combining/formatting values already present in "source_candidates". NEVER invent a fact that is not present in "source_candidates".
2. If a portal field has type "select" and lists options, the value you return MUST be exactly equal to one of those options' value or label strings -- never free text that is not one of the listed options.
3. If no candidate source value reasonably matches a portal field, omit it from "mappings" and list its portal field name in "missing" instead.
4. If two or more candidate source values plausibly map to the same portal field but disagree with each other, omit it from "mappings" and list it in "conflicts" instead.
5. If you can propose a value but are not confident, you may still return it in "mappings" with an honest, calibrated confidence score between 0.0 and 1.0 -- never inflate confidence, and list the portal field name again in "review_required" if you believe a human should double-check it regardless of the numeric score.
6. Never guess a value for an OTP, CAPTCHA, password, session token or similar security field -- none of those will ever appear in this request, and you must never try to supply one anyway.
7. Return ONLY the JSON object described below as raw JSON text. No prose, no markdown formatting, no code fences, no commentary.

Required JSON shape:
{
  "mappings": [
    {"portal_field": "<portal field name>", "source_field": "<matching candidate_source_values key, or omit if none>", "value": "<value>", "confidence": 0.0-1.0, "reason": "<short reason>"}
  ],
  "missing": ["<portal field name>"],
  "conflicts": ["<portal field name>"],
  "review_required": ["<portal field name>"]
}
''';
}
