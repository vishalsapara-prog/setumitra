import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Result of an OCR pass: the extracted text, plus an HONESTLY-SCOPED
/// confidence indicator. [averageConfidence] is null whenever ML Kit
/// doesn't provide one -- which is ALWAYS true on iOS (confirmed via the
/// package's own changelog: "Fix: Confidence and angle only available for
/// Android") and also true if a page had no recognized lines at all. UI
/// code must treat null as "not available," never substitute a fake
/// number -- per the requirements' explicit "no UI-only fake options"
/// constraint.
class OcrResult {
  final String text;
  final double? averageConfidence;
  const OcrResult({required this.text, this.averageConfidence});
}

/// On-device OCR via Google ML Kit -- the OCR engine choice for Path B
/// (see README's "Master Data Layer & Python → Dart Port" section for the
/// reasoning: verified publisher, 383 likes, max pub points, actively
/// updated as of Feb 2026, and avoids the separate "bundle a native
/// Tesseract binary for Android" problem the pre-development audit
/// flagged as its own distinct engineering risk).
///
/// This replaces the Python backend's `pytesseract`-based
/// `extract_text_from_image` for the Path B architecture: runs fully
/// on-device, no server round-trip. `OcrTextParserService` (already
/// ported) then runs on whatever text this produces, exactly as it ran on
/// Tesseract's output before.
///
/// Scope: image files (JPG/PNG) only, matching camera-captured documents.
/// PDF documents picked via the file picker are NOT run through this --
/// ML Kit's TextRecognizer operates on images, not PDF text layers/pages,
/// and no PDF rendering/text-extraction package has been added yet. This
/// is a real, disclosed gap (see README), not silently ignored: PDF
/// uploads currently skip OCR entirely and require manual data entry.
class OcrEngineService {
  static TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  static TextRecognitionScript _activeScript = TextRecognitionScript.latin;

  /// Switches the active recognition script (Advanced OCR Controls'
  /// "OCR Language selection"). Recreates the underlying recognizer only
  /// when the script actually changes -- ML Kit's TextRecognizer is
  /// constructed with a fixed script, it can't be reconfigured in place.
  static Future<void> setScript(TextRecognitionScript script) async {
    if (script == _activeScript) return;
    await _recognizer.close();
    _recognizer = TextRecognizer(script: script);
    _activeScript = script;
  }

  /// Extracts raw text from an image file at [imagePath]. Returns an
  /// empty string on any failure (mirroring the Python backend's
  /// `extract_text_from_image`, which also returns "" rather than
  /// throwing, so callers can fall back to manual data entry).
  static Future<String> extractTextFromImage(String imagePath) async {
    final result = await extractWithConfidence(imagePath);
    return result.text;
  }

  /// Extracts text AND a document-level average confidence, when ML Kit
  /// provides one (Android only -- see [OcrResult]). Confidence is
  /// averaged across every recognized [TextLine] with a non-null
  /// confidence; this is a document-level indicator, not yet a per-field
  /// one (mapping a specific parsed field back to the specific OCR line
  /// it came from is a further refinement, not done this round -- see
  /// README).
  static Future<OcrResult> extractWithConfidence(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _recognizer.processImage(inputImage);

      final confidences = <double>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final c = line.confidence;
          if (c != null) confidences.add(c);
        }
      }
      final avg = confidences.isEmpty ? null : confidences.reduce((a, b) => a + b) / confidences.length;

      return OcrResult(text: recognizedText.text, averageConfidence: avg);
    } catch (e) {
      // ignore: avoid_print
      print('[OCR Warning] ML Kit text recognition failed: $e');
      return const OcrResult(text: '');
    }
  }

  /// Releases the recognizer's native resources. Call when OCR is no
  /// longer needed for the app's lifetime (not per-image -- the
  /// recognizer instance is reused across calls for efficiency).
  static Future<void> dispose() async {
    await _recognizer.close();
  }
}
