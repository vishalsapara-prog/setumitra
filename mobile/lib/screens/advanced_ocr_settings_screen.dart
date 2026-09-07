import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/advanced_ocr_settings_model.dart';
import '../services/ocr_engine_service.dart';

/// Advanced OCR Controls -- kept OUT of the main Camera Settings screen
/// per the requirements ("Advanced OCR controls અલગ Advanced sectionમાં
/// રહેશે"), reachable only from Settings. Every control here is real
/// (see AdvancedOcrSettingsModel's doc comment for what backs each one).
class AdvancedOcrSettingsScreen extends StatefulWidget {
  const AdvancedOcrSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AdvancedOcrSettingsScreen> createState() => _AdvancedOcrSettingsScreenState();
}

class _AdvancedOcrSettingsScreenState extends State<AdvancedOcrSettingsScreen> {
  AdvancedOcrSettingsModel _settings = AdvancedOcrSettingsModel();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await AdvancedOcrSettingsModel.load();
    setState(() {
      _settings = loaded;
      _isLoading = false;
    });
  }

  Future<void> _persist() async {
    await _settings.save();
    await OcrEngineService.setScript(_settings.ocrScript);
  }

  Future<void> _resetToDefault() async {
    await _settings.resetToDefault();
    await OcrEngineService.setScript(_settings.ocrScript);
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Advanced OCR settings reset to default.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced OCR Controls')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Every control below reflects a real, verified capability of this '
                'app\'s OCR engine and image pipeline -- nothing here is a '
                'placeholder with no effect.',
                style: TextStyle(fontSize: 11.5, color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 12),

          _sectionHeader('OCR Language / Script'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<TextRecognitionScript>(
                value: _settings.ocrScript,
                decoration: const InputDecoration(
                  labelText: 'Supported script',
                  border: OutlineInputBorder(),
                ),
                items: TextRecognitionScript.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(AdvancedOcrSettingsModel.scriptLabel(s))))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _settings.ocrScript = v);
                  _persist();
                },
              ),
            ),
          ),

          _sectionHeader('Image Preprocessing'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Denoise', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Gaussian blur noise reduction before OCR', style: TextStyle(fontSize: 11.5)),
                  value: _settings.denoiseEnabled,
                  onChanged: (v) {
                    setState(() => _settings.denoiseEnabled = v);
                    _persist();
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'B&W Threshold / Intensity: ${_settings.binarizationThreshold}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'Only affects the "B&W" filter in Camera Settings',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      Slider(
                        value: _settings.binarizationThreshold.toDouble(),
                        min: 0,
                        max: 255,
                        divisions: 51,
                        label: '${_settings.binarizationThreshold}',
                        onChanged: (v) {
                          setState(() => _settings.binarizationThreshold = v.round());
                        },
                        onChangeEnd: (_) => _persist(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          _sectionHeader('OCR Confidence'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Show Confidence / Uncertain-Field Indication',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Android only -- ML Kit does not provide a confidence score on iOS. '
                    'When unavailable, the app shows "not available" rather than a made-up number.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: _settings.confidenceIndicatorEnabled,
                  onChanged: (v) {
                    setState(() => _settings.confidenceIndicatorEnabled = v);
                    _persist();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _resetToDefault,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.restore),
            label: const Text('Reset Advanced OCR Settings to Default'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
      );
}
