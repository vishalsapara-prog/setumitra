import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../models/form_model.dart';
import '../services/document_generation_service.dart';
import '../services/auto_fill_mapping_service.dart';

class WebViewScreen extends StatefulWidget {
  final String moduleType;
  final ShramsetuFormModel formData;
  const WebViewScreen({Key? key, required this.moduleType, required this.formData}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isGeneratingDocument = false;
  ResolvedMapping? _activeMapping;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse('https://shramsetu.gujarat.gov.in'));
    _loadMapping();
  }

  /// Loaded once per screen instance (not per Auto-Fill tap) since the
  /// mapping rarely changes mid-session and a DB read per keystroke-
  /// adjacent action would be wasteful. If the admin imports a new
  /// mapping version while this screen is already open, it takes effect
  /// on the NEXT time this screen is opened, not live -- a reasonable,
  /// disclosed limitation rather than added complexity for an edge case.
  Future<void> _loadMapping() async {
    await AutoFillMappingService.seedIfEmpty();
    final mapping = await AutoFillMappingService.getActiveMapping();
    if (mounted) setState(() => _activeMapping = mapping);
  }

  /// Builds the payload actually sent into the page JS: three parallel
  /// maps keyed by REAL portal field `name` attributes (via the
  /// currently-active [AutoFillMappingService] mapping -- configurable,
  /// not the old hardcoded `PortalFieldMap` static calls), not the app's
  /// internal semantic keys — so `establishment_name` becomes
  /// `EstablishmentName`, etc. Semantic keys with no known portal mapping
  /// are passed through unchanged as a last-resort guess (the generic
  /// name/id/data-field selector fallback in the injected JS may still
  /// hit something on portal pages this app hasn't been mapped against
  /// yet).
  Map<String, dynamic> _buildTextPayload(ResolvedMapping mapping) {
    final formJson = widget.formData.toJson();
    final out = <String, dynamic>{};
    for (final entry in formJson.entries) {
      if (mapping.isCheckboxField(entry.key)) continue;
      if (mapping.isCheckboxGroupField(entry.key)) continue;
      final val = entry.value;
      if (val == null || val.toString().isEmpty) continue;
      final portalName = mapping.resolve(entry.key) ?? entry.key;
      out[portalName] = val;
    }
    return out;
  }

  Map<String, bool> _buildCheckboxPayload(ResolvedMapping mapping) {
    final formJson = widget.formData.toJson();
    final out = <String, bool>{};
    for (final key in mapping.checkboxFields.keys) {
      final val = formJson[key];
      final portalName = mapping.checkboxFields[key]!;
      out[portalName] = val == true || val == 'true' || val == 1;
    }
    return out;
  }

  /// Checkbox-group fields (nature_of_work_ids, license_covered_district_ids)
  /// hold comma-separated portal checkbox IDs; expands each into the real
  /// `<idPrefix>_<id>` checkbox name to tick, e.g. 'nature_of_work_ids':
  /// '1,5,23' with prefix 'natureOfWorkCheckbox' -> ticks
  /// natureOfWorkCheckbox_1, natureOfWorkCheckbox_5, natureOfWorkCheckbox_23.
  List<String> _buildCheckboxGroupPayload(ResolvedMapping mapping) {
    final formJson = widget.formData.toJson();
    final out = <String>[];
    for (final entry in mapping.checkboxGroupIdPrefixes.entries) {
      final raw = (formJson[entry.key] ?? '').toString();
      if (raw.isEmpty) continue;
      for (final idStr in raw.split(',')) {
        final trimmed = idStr.trim();
        if (trimmed.isEmpty) continue;
        out.add('${entry.value}_$trimmed');
      }
    }
    return out;
  }

  void _injectAutoFill() async {
    final mapping = _activeMapping;
    if (mapping == null) return; // guarded by the FAB's disabled state too
    final textPayload = jsonEncode(_buildTextPayload(mapping));
    final checkboxPayload = jsonEncode(_buildCheckboxPayload(mapping));
    final checkboxGroupPayload = jsonEncode(_buildCheckboxGroupPayload(mapping));

    final jsCode = '''
      (function() {
        var textData = $textPayload;
        var checkboxData = $checkboxPayload;
        var checkboxGroupIds = $checkboxGroupPayload;
        var filled = 0, skipped = 0;

        function findElement(portalName) {
          return document.querySelector('[name="' + portalName + '"]') ||
                 document.getElementById(portalName) ||
                 document.querySelector('[data-field="' + portalName + '"]');
        }

        // --- Native <select> / jQuery Select2-enhanced dropdowns ---
        function setSmartDropdownValue(el, targetTextOrValue) {
          if (!el || targetTextOrValue === null || targetTextOrValue === undefined || targetTextOrValue === '') {
            return false;
          }
          var target = targetTextOrValue.toString().trim().toLowerCase();

          if (el.tagName && el.tagName.toLowerCase() === 'select') {
            var options = Array.prototype.slice.call(el.options);
            var matchedOption = options.find(function (opt) {
              return opt.text.trim().toLowerCase() === target ||
                     opt.value.trim().toLowerCase() === target;
            });
            if (matchedOption) {
              el.value = matchedOption.value;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              el.dispatchEvent(new Event('blur', { bubbles: true }));
              if (window.jQuery) {
                try {
                  window.jQuery(el).val(matchedOption.value).trigger('change');
                } catch (e) { /* jQuery present but element not plugin-bound; ignore */ }
              }
              return true;
            }
            return false;
          }

          if (el.classList.contains('dropdown') || el.getAttribute('role') === 'combobox') {
            el.click();
            var listItems = document.querySelectorAll(
              '.dropdown-menu li, .select2-results__option, ul li'
            );
            for (var i = 0; i < listItems.length; i++) {
              if (listItems[i].textContent.trim().toLowerCase() === target) {
                listItems[i].click();
                return true;
              }
            }
            return false;
          }
          return false;
        }

        function setTextOrDropdownField(el, val) {
          if (!el || val === null || val === undefined || val === '') return false;
          var tag = el.tagName ? el.tagName.toLowerCase() : '';
          if (tag === 'select' || el.classList.contains('dropdown') || el.getAttribute('role') === 'combobox') {
            return setSmartDropdownValue(el, val);
          }
          el.value = val;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          el.dispatchEvent(new Event('blur', { bubbles: true }));
          return true;
        }

        // Plain text inputs, dropdowns, textareas -- keyed by real portal name
        for (var key in textData) {
          var el = findElement(key);
          if (setTextOrDropdownField(el, textData[key])) { filled++; } else { skipped++; }
        }

        // Boolean declaration/registration checkboxes -- keyed by real portal name
        for (var key in checkboxData) {
          var el = findElement(key);
          if (el && (el.type === 'checkbox')) {
            el.checked = !!checkboxData[key];
            el.dispatchEvent(new Event('change', { bubbles: true }));
            el.dispatchEvent(new Event('click', { bubbles: true }));
            filled++;
          } else {
            skipped++;
          }
        }

        // Checkbox-group selections (Nature of Work, Covered Districts) --
        // each entry is already the fully-expanded real checkbox name
        // (e.g. "natureOfWorkCheckbox_23")
        for (var i = 0; i < checkboxGroupIds.length; i++) {
          var el = document.getElementById(checkboxGroupIds[i]);
          if (el && el.type === 'checkbox') {
            el.checked = true;
            el.dispatchEvent(new Event('change', { bubbles: true }));
            el.dispatchEvent(new Event('click', { bubbles: true }));
            filled++;
          } else {
            skipped++;
          }
        }

        alert('Shramsetu Auto-Fill: ' + filled + ' fields filled, ' + skipped + ' not found on this page.');
      })();
    ''';
    await _controller.runJavaScript(jsCode);
  }

  /// Generates the office-record .docx for this application (independent
  /// of the live Auto-Fill above -- this is the local, printable Word
  /// document, not a portal submission) and opens the platform share
  /// sheet so the user can save/print/email it. Closes the gap flagged
  /// in the last status report: DocxTemplateService existed and worked,
  /// but nothing called it.
  Future<void> _generateAndShareDocument(BuildContext buttonContext) async {
    setState(() => _isGeneratingDocument = true);
    try {
      final file = await DocumentGenerationService.generate(
        moduleType: widget.moduleType,
        formData: widget.formData,
      );

      if (!mounted) return;

      // sharePositionOrigin is required on iPad/iOS to avoid a documented
      // crash (share_plus issue #3685: PlatformException when the origin
      // rect is zero/unset) -- derived from the button's own position via
      // the context passed in, not guessed.
      final box = buttonContext.findRenderObject() as RenderBox?;
      final origin = box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Setumitra — Generated Document',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document generation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingDocument = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setumitra — Portal Live', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
        actions: [
          Builder(
            builder: (buttonContext) => IconButton(
              icon: _isGeneratingDocument
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.article_outlined, color: Colors.white),
              tooltip: 'Generate Document',
              onPressed: _isGeneratingDocument ? null : () => _generateAndShareDocument(buttonContext),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _activeMapping == null ? null : _injectAutoFill,
        backgroundColor: const Color(0xFF2B6CB0),
        icon: const Icon(Icons.flash_on, color: Colors.white),
        label: Text(
          _activeMapping == null ? 'Loading mapping…' : 'Auto-Fill Portal',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
