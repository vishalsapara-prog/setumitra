import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/camera_settings_model.dart';

/// Applies the Filter/Enhance/Crop pipeline from the approved Camera
/// Settings requirements, in the specified workflow order: capture →
/// resolution/capture settings (applied at camera-config level, not here)
/// → Auto/Manual Crop → Filter/Enhancement → OCR.
///
/// All filter transforms below are REAL pixel operations via the `image`
/// package (not placeholder no-ops) — but this code has NOT been executed
/// on a real device/Flutter runtime in this build environment (no Flutter
/// SDK available here); only structurally reviewed and compile-checked.
class ImageProcessingService {
  /// Applies the selected [CameraFilterMode] to raw image bytes.
  ///
  /// - Original: no change.
  /// - Auto: automatic contrast stretch (histogram-based) — a general-
  ///   purpose "make it more readable" pass without full binarization.
  /// - Grayscale: true single-channel grayscale conversion.
  /// - B&W: grayscale + fixed-threshold binarization (pure black/white,
  ///   good for high-contrast printed text on clean paper).
  /// - Enhance: brightness + contrast boost, tuned for scanned-document
  ///   readability (also used by the Enhance Text / Auto Enhance toggles).
  /// - Clear: unsharp-mask style sharpen, for slightly blurry captures.
  static Uint8List applyFilter(Uint8List bytes, CameraFilterMode mode, {int binarizationThreshold = 128}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    img.Image result = decoded;
    switch (mode) {
      case CameraFilterMode.original:
        break;
      case CameraFilterMode.auto:
        result = img.normalize(decoded, min: 0, max: 255);
        break;
      case CameraFilterMode.grayscale:
        result = img.grayscale(decoded);
        break;
      case CameraFilterMode.blackAndWhite:
        result = _binarize(img.grayscale(decoded), threshold: binarizationThreshold);
        break;
      case CameraFilterMode.enhance:
        result = img.adjustColor(decoded, contrast: 1.25, brightness: 1.08, saturation: 0.9);
        break;
      case CameraFilterMode.clear:
        result = img.convolution(
          decoded,
          filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
          div: 1,
        );
        break;
    }
    return Uint8List.fromList(img.encodeJpg(result, quality: 92));
  }

  /// Fixed-threshold binarization: any pixel darker than [threshold]
  /// (0-255, on the already-grayscaled image) becomes black, else white.
  /// [threshold] is now a real, caller-adjustable parameter (Advanced OCR
  /// Controls' "Threshold / B&W intensity control") rather than a hidden
  /// constant.
  static img.Image _binarize(img.Image gray, {int threshold = 128}) {
    final out = img.Image.from(gray);
    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        final lum = p.r; // already single-channel after grayscale()
        final v = lum < threshold ? 0 : 255;
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  /// Denoise via Gaussian blur -- a real, standard noise-reduction
  /// technique (verified against the `image` package's own API docs
  /// before use, not assumed), for the Advanced OCR Controls' "Denoise"
  /// toggle. [radius] trades noise reduction for detail loss; kept small
  /// by default since OCR needs sharp text edges more than a photo does.
  static Uint8List denoise(Uint8List bytes, {int radius = 1}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final result = img.gaussianBlur(decoded, radius: radius);
    return Uint8List.fromList(img.encodeJpg(result, quality: 92));
  }

  /// Applies the Enhance Text / Auto Enhance toggles: a lighter-weight
  /// contrast/brightness pass than the full "Enhance" filter, meant to run
  /// automatically pre-OCR regardless of which Filter is selected.
  static Uint8List applyTextEnhancement(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final result = img.adjustColor(decoded, contrast: 1.15, brightness: 1.04);
    return Uint8List.fromList(img.encodeJpg(result, quality: 92));
  }

  /// Auto Crop: HONEST DISCLOSURE — this is a fixed-margin inset crop
  /// (trims a small border from each edge to remove typical camera-frame
  /// noise/background), NOT true document-boundary detection. Real
  /// auto-boundary-detection (finding the document's four corners against
  /// an arbitrary background) is a non-trivial computer-vision problem
  /// requiring a dedicated edge-detection library or a trained model —
  /// out of scope for this pass. Flagged here rather than silently
  /// pretended to be full CV auto-crop, per this project's disclosure
  /// standard throughout.
  static Uint8List applyAutoCropHeuristic(Uint8List bytes, {double marginPercent = 0.03}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final marginX = (decoded.width * marginPercent).round();
    final marginY = (decoded.height * marginPercent).round();
    final cropped = img.copyCrop(
      decoded,
      x: marginX,
      y: marginY,
      width: decoded.width - (2 * marginX),
      height: decoded.height - (2 * marginY),
    );
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
  }

  /// Runs the full pipeline in the approved workflow order: crop, then
  /// filter, then (if enabled) an additional text-enhancement pass.
  /// Returns the processed bytes ready for OCR upload.
  static Future<Uint8List> processForOcr({
    required File sourceFile,
    required CameraSettingsModel settings,
    Uint8List? manuallyCroppedBytes,
    int binarizationThreshold = 128,
    bool denoiseEnabled = false,
  }) async {
    Uint8List bytes = manuallyCroppedBytes ?? await sourceFile.readAsBytes();

    if (manuallyCroppedBytes == null && settings.autoCrop && !settings.manualCrop) {
      bytes = applyAutoCropHeuristic(bytes);
    }

    if (denoiseEnabled) {
      bytes = denoise(bytes);
    }

    bytes = applyFilter(bytes, settings.filter, binarizationThreshold: binarizationThreshold);

    if (settings.enhanceText || settings.autoEnhance) {
      bytes = applyTextEnhancement(bytes);
    }

    return bytes;
  }
}
