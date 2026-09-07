import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Camera/OCR capture settings, matching the approved requirements table
/// verbatim (Setumitra_Project_Additions_New_Application_Camera_Settings):
/// Resolution, Auto Crop, Manual Crop, Filter, Enhance Text, Auto Enhance,
/// Show Grid, Auto Flash, Reset to Default.
///
/// Persisted via shared_preferences (plain, non-sensitive app preferences —
/// distinct from flutter_secure_storage, which is reserved for offline
/// draft form data).
enum CameraFilterMode { original, auto, blackAndWhite, grayscale, enhance, clear }

extension CameraFilterModeLabel on CameraFilterMode {
  String get label {
    switch (this) {
      case CameraFilterMode.original:
        return 'Original';
      case CameraFilterMode.auto:
        return 'Auto';
      case CameraFilterMode.blackAndWhite:
        return 'B&W';
      case CameraFilterMode.grayscale:
        return 'Grayscale';
      case CameraFilterMode.enhance:
        return 'Enhance';
      case CameraFilterMode.clear:
        return 'Clear';
    }
  }

  static CameraFilterMode fromLabel(String label) {
    return CameraFilterMode.values.firstWhere(
      (m) => m.label == label,
      orElse: () => CameraFilterMode.original,
    );
  }
}

class CameraSettingsModel {
  /// Approximate megapixel label shown to the user (8M/5M/3M/2M/1M per the
  /// requirements table). The `camera` plugin exposes fixed
  /// [ResolutionPreset] tiers rather than exact megapixel counts, so this
  /// is a best-effort mapping, not a precise MP guarantee -- disclosed here
  /// rather than silently approximated.
  int resolutionMegapixels;
  bool autoCrop;
  bool manualCrop;
  CameraFilterMode filter;
  bool enhanceText;
  bool autoEnhance;
  bool showGrid;
  bool autoFlash;

  CameraSettingsModel({
    this.resolutionMegapixels = 5,
    this.autoCrop = true,
    this.manualCrop = false,
    this.filter = CameraFilterMode.auto,
    this.enhanceText = true,
    this.autoEnhance = true,
    this.showGrid = true,
    this.autoFlash = true,
  });

  static const _keyResolution = 'camera_resolution_mp';
  static const _keyAutoCrop = 'camera_auto_crop';
  static const _keyManualCrop = 'camera_manual_crop';
  static const _keyFilter = 'camera_filter';
  static const _keyEnhanceText = 'camera_enhance_text';
  static const _keyAutoEnhance = 'camera_auto_enhance';
  static const _keyShowGrid = 'camera_show_grid';
  static const _keyAutoFlash = 'camera_auto_flash';

  /// [ResolutionPreset] nearest to the chosen megapixel label. Approximate
  /// mapping (device-dependent actual sensor output varies):
  ///  8M -> max, 5M -> veryHigh, 3M -> high, 2M -> medium, 1M -> low.
  ResolutionPreset get resolutionPreset {
    switch (resolutionMegapixels) {
      case 8:
        return ResolutionPreset.max;
      case 5:
        return ResolutionPreset.veryHigh;
      case 3:
        return ResolutionPreset.high;
      case 2:
        return ResolutionPreset.medium;
      case 1:
      default:
        return ResolutionPreset.low;
    }
  }

  FlashMode get flashMode => autoFlash ? FlashMode.auto : FlashMode.off;

  static Future<CameraSettingsModel> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraSettingsModel(
      resolutionMegapixels: prefs.getInt(_keyResolution) ?? 5,
      autoCrop: prefs.getBool(_keyAutoCrop) ?? true,
      manualCrop: prefs.getBool(_keyManualCrop) ?? false,
      filter: CameraFilterModeLabel.fromLabel(prefs.getString(_keyFilter) ?? 'Auto'),
      enhanceText: prefs.getBool(_keyEnhanceText) ?? true,
      autoEnhance: prefs.getBool(_keyAutoEnhance) ?? true,
      showGrid: prefs.getBool(_keyShowGrid) ?? true,
      autoFlash: prefs.getBool(_keyAutoFlash) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyResolution, resolutionMegapixels);
    await prefs.setBool(_keyAutoCrop, autoCrop);
    await prefs.setBool(_keyManualCrop, manualCrop);
    await prefs.setString(_keyFilter, filter.label);
    await prefs.setBool(_keyEnhanceText, enhanceText);
    await prefs.setBool(_keyAutoEnhance, autoEnhance);
    await prefs.setBool(_keyShowGrid, showGrid);
    await prefs.setBool(_keyAutoFlash, autoFlash);
  }

  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyResolution);
    await prefs.remove(_keyAutoCrop);
    await prefs.remove(_keyManualCrop);
    await prefs.remove(_keyFilter);
    await prefs.remove(_keyEnhanceText);
    await prefs.remove(_keyAutoEnhance);
    await prefs.remove(_keyShowGrid);
    await prefs.remove(_keyAutoFlash);
    final defaults = CameraSettingsModel();
    resolutionMegapixels = defaults.resolutionMegapixels;
    autoCrop = defaults.autoCrop;
    manualCrop = defaults.manualCrop;
    filter = defaults.filter;
    enhanceText = defaults.enhanceText;
    autoEnhance = defaults.autoEnhance;
    showGrid = defaults.showGrid;
    autoFlash = defaults.autoFlash;
  }
}
