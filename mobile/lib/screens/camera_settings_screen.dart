import 'package:flutter/material.dart';
import '../models/camera_settings_model.dart';

/// Camera Settings screen — implements every row of the approved
/// requirements table verbatim: Resolution, Auto Crop, Manual Crop,
/// Filter, Enhance Text, Auto Enhance, Show Grid, Auto Flash, Reset to
/// Default. Per the "UI Simplicity Rule" in that same document, this is
/// the ONLY place these technical toggles are exposed — the rest of the
/// app (scan/review/webview screens) never surfaces them directly.
class CameraSettingsScreen extends StatefulWidget {
  const CameraSettingsScreen({Key? key}) : super(key: key);

  @override
  State<CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends State<CameraSettingsScreen> {
  CameraSettingsModel _settings = CameraSettingsModel();
  bool _isLoading = true;

  static const List<int> _resolutionOptions = [8, 5, 3, 2, 1];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final loaded = await CameraSettingsModel.load();
    setState(() {
      _settings = loaded;
      _isLoading = false;
    });
  }

  Future<void> _persist() async {
    await _settings.save();
  }

  Future<void> _resetToDefault() async {
    await _settings.resetToDefault();
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Camera/OCR settings reset to default.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('Camera Resolution'),
          _card(
            child: DropdownButtonFormField<int>(
              value: _settings.resolutionMegapixels,
              decoration: const InputDecoration(
                labelText: 'Document image quality નિયંત્રિત કરવી',
                border: OutlineInputBorder(),
              ),
              items: _resolutionOptions
                  .map((mp) => DropdownMenuItem(value: mp, child: Text('${mp}M')))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _settings.resolutionMegapixels = v);
                _persist();
              },
            ),
          ),

          _sectionHeader('Crop'),
          _card(
            child: Column(
              children: [
                _switchTile(
                  title: 'Auto Crop',
                  subtitle: 'Documentની boundary આપમેળે detect અને crop કરવી',
                  value: _settings.autoCrop,
                  onChanged: (v) {
                    setState(() => _settings.autoCrop = v);
                    _persist();
                  },
                ),
                const Divider(height: 1),
                _switchTile(
                  title: 'Manual Crop',
                  subtitle: 'Userને crop boundary manually સુધારવાની સુવિધા',
                  value: _settings.manualCrop,
                  onChanged: (v) {
                    setState(() => _settings.manualCrop = v);
                    _persist();
                  },
                ),
              ],
            ),
          ),

          _sectionHeader('Filter'),
          _card(
            child: DropdownButtonFormField<CameraFilterMode>(
              value: _settings.filter,
              decoration: const InputDecoration(
                labelText: 'Document readability સુધારવી',
                border: OutlineInputBorder(),
              ),
              items: CameraFilterMode.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _settings.filter = v);
                _persist();
              },
            ),
          ),

          _sectionHeader('Enhancement'),
          _card(
            child: Column(
              children: [
                _switchTile(
                  title: 'Enhance Text',
                  subtitle: 'Text clarity વધારવી અને OCR માટે image સુધારવી',
                  value: _settings.enhanceText,
                  onChanged: (v) {
                    setState(() => _settings.enhanceText = v);
                    _persist();
                  },
                ),
                const Divider(height: 1),
                _switchTile(
                  title: 'Auto Enhance',
                  subtitle: 'OCR પહેલાં image enhancement આપમેળે કરવું',
                  value: _settings.autoEnhance,
                  onChanged: (v) {
                    setState(() => _settings.autoEnhance = v);
                    _persist();
                  },
                ),
              ],
            ),
          ),

          _sectionHeader('Capture Aids'),
          _card(
            child: Column(
              children: [
                _switchTile(
                  title: 'Show Grid',
                  subtitle: 'Documentને સીધું frame કરવામાં મદદ',
                  value: _settings.showGrid,
                  onChanged: (v) {
                    setState(() => _settings.showGrid = v);
                    _persist();
                  },
                ),
                const Divider(height: 1),
                _switchTile(
                  title: 'Auto Flash',
                  subtitle: 'ઓછી lightમાં capture સુધારવું',
                  value: _settings.autoFlash,
                  onChanged: (v) {
                    setState(() => _settings.autoFlash = v);
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
            label: const Text('Reset to Default'),
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

  Widget _card({required Widget child}) => Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      );

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
      value: value,
      activeColor: const Color(0xFF2B6CB0),
      onChanged: onChanged,
    );
  }
}
