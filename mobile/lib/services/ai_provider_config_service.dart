/// Secure, provider-agnostic configuration storage for the "AI AutoFill"
/// feature -- spec Section 20 ("AI SETTINGS") and Section 19 ("API KEY
/// SECURITY").
///
/// Everything here is stored with [FlutterSecureStorage], which uses the
/// OS keystore (Android Keystore / iOS Keychain) rather than a plain file
/// or SharedPreferences, so a provider's API key never sits in clear text
/// in app storage, and is never compiled into the APK (spec: "NEVER
/// hard-code Gemini API keys in the APK").
///
/// This file knows nothing about Gemini specifically -- API keys are
/// stored per [AiProviderId], so a future second provider reuses the same
/// storage methods with its own id, with zero changes needed here.
///
/// An in-process memory cache sits in front of secure storage: every
/// successful read is cached, and every write updates the cache
/// immediately regardless of whether the underlying secure-storage write
/// itself succeeds. This means a value just written is always visible to
/// the rest of THIS app session right away, even if the platform storage
/// call is slow, races with another read, or (in a test/host environment
/// with no secure-storage platform implementation at all) silently
/// no-ops -- persistence across app restarts still depends on the
/// underlying secure storage succeeding, but in-session behaviour no
/// longer does.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_provider.dart';
import '../models/ai_mapping_models.dart';

class AiProviderConfigService {
  AiProviderConfigService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryCache = {};

  static const String _keyEnabled = 'ai_autofill_enabled';
  static const String _keyProviderId = 'ai_autofill_provider_id';
  static const String _keyAutoFillMinConfidence = 'ai_autofill_min_confidence';
  static const String _keyReviewMinConfidence = 'ai_autofill_review_min_confidence';
  static const String _keyBackendUrl = 'ai_autofill_backend_url';
  static const String _apiKeyPrefix = 'ai_autofill_api_key__';

  /// AI AutoFill is OFF by default. This is a deliberately safe default:
  /// the feature is purely additive (spec Section 3), so a fresh install
  /// or upgrade must not start silently calling an external AI provider
  /// until the user has explicitly opted in via Settings.
  Future<bool> isEnabled() async {
    final raw = await _readSafe(_keyEnabled);
    return raw == 'true';
  }

  Future<void> setEnabled(bool value) => _writeSafe(_keyEnabled, value.toString());

  Future<AiProviderId> getProviderId() async {
    final raw = await _readSafe(_keyProviderId);
    return AiProviderId.fromStorageValue(raw);
  }

  Future<void> setProviderId(AiProviderId id) => _writeSafe(_keyProviderId, id.storageValue);

  /// Confidence thresholds, per spec Section 13: "These thresholds must be
  /// CONFIGURABLE. Do not hard-code them in multiple places." This service
  /// is the one place the configured values are persisted; every caller
  /// that needs the thresholds reads them from here (falling back to
  /// [AiConfidenceThresholds.defaults] if nothing has been configured yet
  /// or secure storage is temporarily unavailable).
  Future<AiConfidenceThresholds> getThresholds() async {
    final autoFillRaw = await _readSafe(_keyAutoFillMinConfidence);
    final reviewRaw = await _readSafe(_keyReviewMinConfidence);
    const defaults = AiConfidenceThresholds.defaults();
    final autoFillMin = double.tryParse(autoFillRaw ?? '') ?? defaults.autoFillMinConfidence;
    final reviewMin = double.tryParse(reviewRaw ?? '') ?? defaults.reviewMinConfidence;
    if (autoFillMin < 0 || autoFillMin > 1 || reviewMin < 0 || reviewMin > 1 || reviewMin > autoFillMin) {
      // Corrupt/invalid stored values must never silently relax safety --
      // fall back to the safe defaults rather than using a nonsensical
      // threshold pair.
      return defaults;
    }
    return AiConfidenceThresholds(autoFillMinConfidence: autoFillMin, reviewMinConfidence: reviewMin);
  }

  Future<void> setThresholds(AiConfidenceThresholds thresholds) async {
    await _writeSafe(_keyAutoFillMinConfidence, thresholds.autoFillMinConfidence.toString());
    await _writeSafe(_keyReviewMinConfidence, thresholds.reviewMinConfidence.toString());
  }

  /// Optional backend proxy URL (spec Section 19's preferred architecture:
  /// "Flutter APK -> Secure backend API -> Gemini API", so the real
  /// provider secret can live server-side instead of on-device). Null/empty
  /// means "no backend configured" -- [GeminiProvider] then falls back to
  /// calling the Gemini REST API directly using the on-device-stored key,
  /// which is this app's only backend-free option since it ships with no
  /// server component of its own (documented as a known trade-off in the
  /// implementation report, not hidden).
  Future<String?> getBackendUrl() async {
    final raw = await _readSafe(_keyBackendUrl);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  Future<void> setBackendUrl(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _deleteSafe(_keyBackendUrl);
      return;
    }
    await _writeSafe(_keyBackendUrl, url.trim());
  }

  String _apiKeyStorageKey(AiProviderId id) => '$_apiKeyPrefix${id.storageValue}';

  Future<String?> getApiKey(AiProviderId id) => _readSafe(_apiKeyStorageKey(id));

  Future<void> setApiKey(AiProviderId id, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await clearApiKey(id);
      return;
    }
    await _writeSafe(_apiKeyStorageKey(id), trimmed);
  }

  Future<void> clearApiKey(AiProviderId id) => _deleteSafe(_apiKeyStorageKey(id));

  Future<bool> hasApiKey(AiProviderId id) async {
    final key = await getApiKey(id);
    return key != null && key.isNotEmpty;
  }

  // Secure storage is OS-backed and can, in rare circumstances (keystore
  // not yet unlocked, platform channel hiccup during a cold start, or no
  // secure-storage platform implementation at all in a host/test
  // environment), throw instead of returning a value. Settings/mapping
  // reads must never crash the app over this -- they degrade to "not
  // configured" instead, which is exactly the safe behaviour the rest of
  // this feature already expects when AI is unavailable. The in-memory
  // cache is checked first, so a value set earlier in this session is
  // always honoured even when the platform call itself cannot succeed.
  Future<String?> _readSafe(String key) async {
    if (_memoryCache.containsKey(key)) return _memoryCache[key];
    try {
      final value = await _storage.read(key: key);
      if (value != null) _memoryCache[key] = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSafe(String key, String value) async {
    _memoryCache[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Best-effort: the in-memory cache still reflects the intended
      // value for the rest of this session even if persistence failed; it
      // must not crash the Settings screen the user is actively using.
    }
  }

  Future<void> _deleteSafe(String key) async {
    _memoryCache.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // See _writeSafe.
    }
  }
}
