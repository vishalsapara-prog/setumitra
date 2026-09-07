import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Advanced OCR Controls, kept in a SEPARATE model/screen from the basic
/// Camera Settings per the requirements ("Advanced OCR controls અલગ
/// Advanced sectionમાં રહેશે જેથી સામાન્ય UI complicated ન બને").
///
/// Every control here is backed by a REAL, verified capability of either
/// the `image` package or `google_mlkit_text_recognition` -- per the
/// explicit constraint ("જે controls device/OCR engine ખરેખર support કરે
/// તે જ implement/expose કરવા; UI-only fake options નહીં"), nothing here
/// is a UI-only placeholder with no effect:
///   - ocrScript: real -- TextRecognizer(script:) genuinely changes which
///     character set ML Kit recognizes (Latin/Chinese/Devanagari/
///     Japanese/Korean).
///   - denoiseEnabled: real -- `image` package's gaussianBlur() genuinely
///     reduces noise (verified against pub.dev docs before use).
///   - binarizationThreshold: real -- ImageProcessingService's B&W filter
///     already used a fixed threshold (128); this exposes it as a real,
///     adjustable 0-255 parameter instead of a hidden constant.
///   - confidenceIndicatorEnabled: real, but Android-only -- ML Kit's
///     TextLine/TextElement.confidence is genuinely populated on Android
///     and genuinely returns null on iOS (confirmed via the package's own
///     changelog: "Fix: Confidence and angle only available for
///     Android"). NOT hidden or faked on iOS -- the UI must show "not
///     available on this platform" there, never a made-up number.
class AdvancedOcrSettingsModel {
  TextRecognitionScript ocrScript;
  bool denoiseEnabled;
  int binarizationThreshold;
  bool confidenceIndicatorEnabled;

  AdvancedOcrSettingsModel({
    this.ocrScript = TextRecognitionScript.latin,
    this.denoiseEnabled = false,
    this.binarizationThreshold = 128,
    this.confidenceIndicatorEnabled = true,
  });

  static const _keyScript = 'adv_ocr_script';
  static const _keyDenoise = 'adv_ocr_denoise';
  static const _keyThreshold = 'adv_ocr_threshold';
  static const _keyConfidence = 'adv_ocr_confidence_indicator';

  static String scriptLabel(TextRecognitionScript s) {
    // Deliberately NOT a switch over every enum member: this app's actual
    // OCR targets (PAN, GSTIN, EPF/ESIC, etc.) are all Latin-script English
    // documents, so only `latin` is load-bearing and 100% confirmed
    // correct against real working code. The other 4 script names were
    // confirmed for `latin`/`chinese`/`japanese`/`korean` directly from
    // real example code during research, but `devanagiri`/`devanagari`'s
    // exact Dart spelling could not be independently confirmed with full
    // confidence. Rather than hardcode a guessed enum literal into a
    // switch (which would fail to COMPILE at all if the guess were
    // wrong), this looks up a friendly label by the enum's runtime
    // `.name` string -- safe regardless of exact spelling, and falls back
    // to a readable capitalized version for anything not in the map.
    const labels = {
      'latin': 'Latin (English)',
      'chinese': 'Chinese',
      'japanese': 'Japanese',
      'korean': 'Korean',
    };
    return labels[s.name] ?? '${s.name[0].toUpperCase()}${s.name.substring(1)}';
  }

  static Future<AdvancedOcrSettingsModel> load() async {
    final prefs = await SharedPreferences.getInstance();
    final scriptName = prefs.getString(_keyScript);
    final script = TextRecognitionScript.values.firstWhere(
      (s) => s.name == scriptName,
      orElse: () => TextRecognitionScript.latin,
    );
    return AdvancedOcrSettingsModel(
      ocrScript: script,
      denoiseEnabled: prefs.getBool(_keyDenoise) ?? false,
      binarizationThreshold: prefs.getInt(_keyThreshold) ?? 128,
      confidenceIndicatorEnabled: prefs.getBool(_keyConfidence) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyScript, ocrScript.name);
    await prefs.setBool(_keyDenoise, denoiseEnabled);
    await prefs.setInt(_keyThreshold, binarizationThreshold);
    await prefs.setBool(_keyConfidence, confidenceIndicatorEnabled);
  }

  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyScript);
    await prefs.remove(_keyDenoise);
    await prefs.remove(_keyThreshold);
    await prefs.remove(_keyConfidence);
    final defaults = AdvancedOcrSettingsModel();
    ocrScript = defaults.ocrScript;
    denoiseEnabled = defaults.denoiseEnabled;
    binarizationThreshold = defaults.binarizationThreshold;
    confidenceIndicatorEnabled = defaults.confidenceIndicatorEnabled;
  }
}
