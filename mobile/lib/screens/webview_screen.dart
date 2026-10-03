import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/ai_mapping_models.dart';
import '../models/form_model.dart';
import '../services/ai_mapping_service.dart';
import '../services/document_generation_service.dart';
import '../services/auto_fill_mapping_service.dart';
import 'ai_mapping_preview_screen.dart';

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
  bool _isRunningAiAutoFill = false;
  ResolvedMapping? _activeMapping;
  final AiMappingService _aiMappingService = AiMappingService();

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

  // -------------------------------------------------------------------
  // AI AutoFill -- additive feature, entirely separate from the existing
  // deterministic Auto-Fill above (_injectAutoFill and its helpers are
  // NOT modified or reused by any of the following). Flow (spec Section
  // 14, "Preview Before Fill"):
  //   1. Extract the live portal's current fields from the DOM.
  //   2. Ask AiMappingService (deterministic + master data + AI provider)
  //      to resolve as many as it safely can.
  //   3. Show the user every result in AiMappingPreviewScreen for
  //      accept/edit/reject -- nothing is written to the portal before
  //      this step completes.
  //   4. Fill only the fields the user actually confirmed, via a
  //      separate, minimal JS snippet.
  //   5. Record an audit-trail row per field (spec Section 23).
  // OTP/CAPTCHA/password fields are excluded at the extraction step
  // itself (SKIP_TYPES below) and again, independently, inside
  // AiMappingService -- Final Submit is never touched anywhere in this
  // flow.
  // -------------------------------------------------------------------

  /// Extracts a structured description of every currently-visible,
  /// fillable field on the live portal page -- id/name/label/placeholder/
  /// type/required/options/nearby context only (spec Section 15), never
  /// full page HTML and never password/OTP/CAPTCHA fields (excluded by
  /// SKIP_TYPES in the injected JS itself, before anything leaves the
  /// page).
  Future<List<AiPortalFieldDescriptor>> _extractPortalFieldDescriptors() async {
    const jsCode = r'''
      (function() {
        function isVisible(el) {
          if (!el) return false;
          var style = window.getComputedStyle(el);
          if (style.display === 'none' || style.visibility === 'hidden') return false;
          if (el.offsetParent === null && style.position !== 'fixed') return false;
          return true;
        }
        function labelFor(el) {
          if (el.id) {
            try {
              var lbl = document.querySelector('label[for="' + el.id.replace(/"/g, '\\"') + '"]');
              if (lbl && lbl.textContent) return lbl.textContent.trim().substring(0, 160);
            } catch (e) { /* invalid selector from an unusual id; ignore */ }
          }
          var parentLabel = el.closest ? el.closest('label') : null;
          if (parentLabel && parentLabel.textContent) return parentLabel.textContent.trim().substring(0, 160);
          var prev = el.previousElementSibling;
          if (prev && prev.textContent && prev.textContent.trim()) return prev.textContent.trim().substring(0, 160);
          return null;
        }
        function nearbyContext(el) {
          var parent = el.parentElement;
          if (!parent || !parent.textContent) return null;
          var text = parent.textContent.replace(/\s+/g, ' ').trim();
          return text.substring(0, 160);
        }
        var SKIP_TYPES = ['hidden', 'submit', 'button', 'reset', 'image', 'file', 'checkbox', 'radio', 'password'];
        var elements = document.querySelectorAll('input, select, textarea');
        var out = [];
        for (var i = 0; i < elements.length; i++) {
          var el = elements[i];
          var tag = el.tagName ? el.tagName.toLowerCase() : '';
          var type = (el.getAttribute('type') || (tag === 'select' ? 'select' : (tag === 'textarea' ? 'textarea' : 'text'))).toLowerCase();
          if (SKIP_TYPES.indexOf(type) !== -1) continue;
          if (el.disabled) continue;
          if (!isVisible(el)) continue;
          var name = el.getAttribute('name') || el.id || '';
          if (!name) continue;
          var lname = name.toLowerCase();
          var lid = (el.id || '').toLowerCase();
          if (lname.indexOf('otp') !== -1 || lid.indexOf('otp') !== -1 ||
              lname.indexOf('captcha') !== -1 || lid.indexOf('captcha') !== -1 ||
              lname.indexOf('password') !== -1 || lid.indexOf('password') !== -1) {
            continue;
          }
          var options = [];
          if (tag === 'select') {
            var opts = el.options;
            for (var j = 0; j < opts.length; j++) {
              options.push({ value: opts[j].value, label: opts[j].text });
            }
          }
          out.push({
            name: name,
            id: el.id || null,
            label: labelFor(el),
            placeholder: el.getAttribute('placeholder') || null,
            type: type,
            required: !!el.required,
            options: options,
            nearbyContext: nearbyContext(el)
          });
        }
        return JSON.stringify(out);
      })();
    ''';

    final rawResult = await _controller.runJavaScriptReturningResult(jsCode);
    dynamic decoded;
    try {
      decoded = jsonDecode(rawResult is String ? rawResult : rawResult.toString());
    } catch (_) {
      decoded = null;
    }
    if (decoded is String) {
      // Some WebView platform implementations double-encode a JS string
      // result (the outer decode above just removes one layer of
      // quoting); decode again to reach the actual JSON array.
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is! List) return const [];

    final out = <AiPortalFieldDescriptor>[];
    for (final item in decoded) {
      if (item is Map) {
        out.add(AiPortalFieldDescriptor.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }

  /// Fills ONLY the fields the user explicitly confirmed in
  /// [AiMappingPreviewScreen]. Deliberately a separate, minimal JS
  /// snippet (its own `findElement`/value-setting logic) rather than a
  /// call into [_injectAutoFill] -- that method and its JS are the
  /// protected, existing deterministic Auto-Fill path and are not reused
  /// or modified here.
  Future<void> _fillConfirmedAiMappings(List<AiFieldMapping> mappings) async {
    if (mappings.isEmpty) return;
    final payload = jsonEncode({for (final m in mappings) m.portalField: m.value});
    final jsCode =
        '''
      (function() {
        var data = $payload;
        var filled = 0, skipped = 0;

        function findElement(name) {
          return document.querySelector('[name="' + name + '"]') ||
                 document.getElementById(name) ||
                 document.querySelector('[data-field="' + name + '"]');
        }

        function setValue(el, val) {
          if (!el || val === null || val === undefined || val === '') return false;
          var tag = el.tagName ? el.tagName.toLowerCase() : '';
          if (tag === 'select') {
            var options = Array.prototype.slice.call(el.options);
            var target = val.toString().trim().toLowerCase();
            var matchedOption = options.find(function (opt) {
              return opt.text.trim().toLowerCase() === target || opt.value.trim().toLowerCase() === target;
            });
            if (!matchedOption) return false;
            el.value = matchedOption.value;
          } else {
            el.value = val;
          }
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          el.dispatchEvent(new Event('blur', { bubbles: true }));
          return true;
        }

        for (var key in data) {
          var el = findElement(key);
          if (setValue(el, data[key])) { filled++; } else { skipped++; }
        }

        alert('AI AutoFill: ' + filled + ' field(s) filled, ' + skipped + ' not found on this page.');
      })();
    ''';
    await _controller.runJavaScript(jsCode);
  }

  /// Entry point for the new "AI AutoFill" app bar action.
  Future<void> _runAiAutoFill() async {
    setState(() => _isRunningAiAutoFill = true);
    try {
      final domFields = await _extractPortalFieldDescriptors();
      if (domFields.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No fillable fields were found on the current page.')),
          );
        }
        return;
      }

      final response = await _aiMappingService.generateMappings(
        domFields: domFields,
        formData: widget.formData,
        serviceName: widget.moduleType,
      );

      if (!mounted) return;
      final confirmed = await Navigator.push<List<AiFieldMapping>>(
        context,
        MaterialPageRoute(
          builder: (_) => AiMappingPreviewScreen(response: response, serviceName: widget.moduleType),
        ),
      );
      if (confirmed == null || confirmed.isEmpty) return;

      await _fillConfirmedAiMappings(confirmed);

      // Build the audit list: for every field AI AutoFill originally
      // proposed, use the (possibly user-edited) confirmed version if the
      // user kept it, so the audit trail's "final value" is the value
      // that was actually written to the portal, not the original
      // proposal; append manually-entered values for fields that had no
      // original proposal at all (previously Missing/Conflict).
      final confirmedByField = {for (final c in confirmed) c.portalField: c};
      final auditList = <AiFieldMapping>[];
      final seen = <String>{};
      for (final m in response.mappings) {
        auditList.add(confirmedByField[m.portalField] ?? m);
        seen.add(m.portalField);
      }
      for (final c in confirmed) {
        if (!seen.contains(c.portalField)) auditList.add(c);
      }

      await _aiMappingService.recordAudit(
        mappings: auditList,
        confirmedPortalFields: confirmedByField.keys.toSet(),
        serviceName: widget.moduleType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI AutoFill failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRunningAiAutoFill = false);
    }
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
          IconButton(
            icon: _isRunningAiAutoFill
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.smart_toy_outlined, color: Colors.white),
            tooltip: 'AI AutoFill',
            onPressed: _isRunningAiAutoFill ? null : _runAiAutoFill,
          ),
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
