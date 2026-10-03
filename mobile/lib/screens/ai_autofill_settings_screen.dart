import 'package:flutter/material.dart';

import '../models/ai_mapping_models.dart';
import '../services/ai_provider.dart';
import '../services/ai_provider_config_service.dart';

/// Settings screen for the "AI AutoFill" feature -- spec Section 20 ("AI
/// SETTINGS"). The feature is always presented to the user as "AI
/// AutoFill"; "Gemini" appears only as the value of the "AI Provider" row,
/// never as a screen title or section name (per the change request).
class AiAutoFillSettingsScreen extends StatefulWidget {
  const AiAutoFillSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AiAutoFillSettingsScreen> createState() => _AiAutoFillSettingsScreenState();
}

class _AiAutoFillSettingsScreenState extends State<AiAutoFillSettingsScreen> {
  final AiProviderConfigService _config = AiProviderConfigService();

  bool _loading = true;
  bool _enabled = false;
  AiProviderId _providerId = AiProviderId.gemini;
  double _autoFillMinConfidence = 0.95;
  double _reviewMinConfidence = 0.80;
  bool _hasApiKey = false;

  final _apiKeyController = TextEditingController();
  final _backendUrlController = TextEditingController();
  bool _apiKeyObscured = true;
  bool _testingConnection = false;
  String? _testResult;
  bool _testFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _backendUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await _config.isEnabled();
    final providerId = await _config.getProviderId();
    final thresholds = await _config.getThresholds();
    final backendUrl = await _config.getBackendUrl();
    final hasKey = await _config.hasApiKey(providerId);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _providerId = providerId;
      _autoFillMinConfidence = thresholds.autoFillMinConfidence;
      _reviewMinConfidence = thresholds.reviewMinConfidence;
      _backendUrlController.text = backendUrl ?? '';
      _hasApiKey = hasKey;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await _config.setEnabled(value);
  }

  Future<void> _saveThresholds() async {
    await _config.setThresholds(
      AiConfidenceThresholds(
        autoFillMinConfidence: _autoFillMinConfidence,
        reviewMinConfidence: _reviewMinConfidence,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Confidence thresholds saved.')),
    );
  }

  Future<void> _saveApiKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an API key first, or use "Clear" to remove the saved one.')),
      );
      return;
    }
    await _config.setApiKey(_providerId, value);
    _apiKeyController.clear();
    if (!mounted) return;
    setState(() => _hasApiKey = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_providerId.displayLabel} API key saved securely on this device.')),
    );
  }

  Future<void> _clearApiKey() async {
    await _config.clearApiKey(_providerId);
    if (!mounted) return;
    setState(() => _hasApiKey = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_providerId.displayLabel} API key removed.')),
    );
  }

  Future<void> _saveBackendUrl() async {
    await _config.setBackendUrl(_backendUrlController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backend URL saved.')),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _testResult = null;
      _testFailed = false;
    });
    try {
      final provider = AiProviderFactory.create(_providerId, _config);
      final message = await provider.testConnection();
      if (!mounted) return;
      setState(() {
        _testResult = message;
        _testFailed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = e is AiProviderUnavailableException ? e.message : e.toString();
        _testFailed = true;
      });
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI AutoFill')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI AutoFill')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('AI AutoFill'),
              subtitle: const Text(
                'Uses AI to suggest values for portal fields the existing Auto-Fill '
                'does not already know. Always OFF by default; the existing '
                'deterministic Auto-Fill works whether this is on or off.',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _enabled,
              onChanged: _setEnabled,
            ),
          ),
          const SizedBox(height: 20),

          const Text('Provider', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined, color: Color(0xFF2B6CB0)),
                  title: const Text('AI Provider'),
                  subtitle: Text(_providerId.displayLabel),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _apiKeyController,
                    obscureText: _apiKeyObscured,
                    decoration: InputDecoration(
                      labelText: '${_providerId.displayLabel} API Key',
                      helperText: _hasApiKey
                          ? 'A key is already saved securely on this device. Enter a new one to replace it.'
                          : 'Stored only in this device\'s secure keystore -- never bundled into the app.',
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        icon: Icon(_apiKeyObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _apiKeyObscured = !_apiKeyObscured),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(onPressed: _saveApiKey, child: const Text('Save Key')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _hasApiKey ? _clearApiKey : null,
                          child: const Text('Clear Key'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _backendUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Backend URL (optional)',
                      helperText: 'If your office runs a secure backend proxy for AI AutoFill, enter it '
                          'here so the API key never has to be stored on this device at all. '
                          'Leave blank to call the provider directly using the key above.',
                      helperMaxLines: 4,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(onPressed: _saveBackendUrl, child: const Text('Save Backend URL')),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _testingConnection ? null : _testConnection,
                        icon: _testingConnection
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering),
                        label: const Text('Test AI Connection'),
                      ),
                      if (_testResult != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _testFailed ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Text('Confidence Thresholds', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A365D))),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Auto-fill eligible at: ${(_autoFillMinConfidence * 100).round()}%'),
                  Slider(
                    value: _autoFillMinConfidence,
                    min: 0.5,
                    max: 1.0,
                    divisions: 50,
                    label: '${(_autoFillMinConfidence * 100).round()}%',
                    onChanged: (v) => setState(() {
                      _autoFillMinConfidence = v;
                      if (_reviewMinConfidence > _autoFillMinConfidence) {
                        _reviewMinConfidence = _autoFillMinConfidence;
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text('Review required from: ${(_reviewMinConfidence * 100).round()}%'),
                  Slider(
                    value: _reviewMinConfidence,
                    min: 0.0,
                    max: _autoFillMinConfidence,
                    divisions: 50,
                    label: '${(_reviewMinConfidence * 100).round()}%',
                    onChanged: (v) => setState(() => _reviewMinConfidence = v),
                  ),
                  const Text(
                    'Below the review threshold, a field is never auto-filled -- it is '
                    'always left for you to fill in manually.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(onPressed: _saveThresholds, child: const Text('Save Thresholds')),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'AI AutoFill only suggests values -- every suggestion is shown to you for '
                'review before anything is written into the portal. It never enters an '
                'OTP or CAPTCHA, and it never submits the form on your behalf.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
