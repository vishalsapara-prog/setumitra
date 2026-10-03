import 'package:flutter/material.dart';

import '../models/ai_mapping_models.dart';

/// "Preview Before Fill" screen -- spec Section 14. Shows every AI
/// AutoFill-resolved field (Portal Field / Source Field / Value /
/// Confidence / Status) plus every field the engine could not resolve
/// (Missing / Conflict), and lets the user accept, edit, reject, or
/// manually supply a value for each one. NOTHING here is written to the
/// portal directly -- this screen only returns the final, user-approved
/// list of [AiFieldMapping] back to the caller (webview_screen.dart),
/// which performs the actual (separate, additive) portal-fill JS and the
/// audit-trail write. Final Submit is never touched by this screen or
/// anything it triggers.
class AiMappingPreviewScreen extends StatefulWidget {
  final AiMappingResponse response;
  final String serviceName;

  const AiMappingPreviewScreen({Key? key, required this.response, required this.serviceName}) : super(key: key);

  @override
  State<AiMappingPreviewScreen> createState() => _AiMappingPreviewScreenState();
}

class _AiMappingPreviewScreenState extends State<AiMappingPreviewScreen> {
  late final List<AiFieldMapping> _mappings;
  late final Set<String> _accepted;
  late final Map<String, TextEditingController> _valueControllers;
  late final Map<String, TextEditingController> _manualControllers;

  @override
  void initState() {
    super.initState();
    _mappings = List<AiFieldMapping>.of(widget.response.mappings);
    _accepted = {
      for (final m in _mappings)
        if (m.status == MappingStatus.matched) m.portalField,
    };
    _valueControllers = {
      for (final m in _mappings) m.portalField: TextEditingController(text: m.value),
    };
    final unresolvedFieldNames = {...widget.response.missing, ...widget.response.conflicts};
    _manualControllers = {
      for (final name in unresolvedFieldNames) name: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _valueControllers.values) {
      c.dispose();
    }
    for (final c in _manualControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirmAndClose() {
    final confirmed = <AiFieldMapping>[];

    for (final m in _mappings) {
      if (!_accepted.contains(m.portalField)) continue;
      final editedValue = _valueControllers[m.portalField]?.text.trim() ?? m.value;
      if (editedValue.isEmpty) continue;
      final wasEdited = editedValue != m.value;
      confirmed.add(
        m.withValue(
          editedValue,
          newReason: wasEdited ? '${m.reason} (value edited by user before filling)' : m.reason,
        ),
      );
    }

    for (final entry in _manualControllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      confirmed.add(
        AiFieldMapping(
          portalField: entry.key,
          sourceField: null,
          value: text,
          confidence: 1.0,
          reason: 'Entered manually by the user in the AI AutoFill preview.',
          status: MappingStatus.matched,
          mappingMethod: MappingMethod.userManual,
        ),
      );
    }

    Navigator.of(context).pop<List<AiFieldMapping>>(confirmed);
  }

  Color _statusColor(MappingStatus status) {
    switch (status) {
      case MappingStatus.matched:
        return Colors.green.shade700;
      case MappingStatus.reviewRequired:
        return Colors.orange.shade800;
      case MappingStatus.missing:
        return Colors.grey.shade700;
      case MappingStatus.conflict:
        return Colors.red.shade700;
    }
  }

  String _statusLabel(MappingStatus status) {
    switch (status) {
      case MappingStatus.matched:
        return 'Matched';
      case MappingStatus.reviewRequired:
        return 'Review Required';
      case MappingStatus.missing:
        return 'Missing';
      case MappingStatus.conflict:
        return 'Conflict';
    }
  }

  Widget _buildResolvedRow(AiFieldMapping m) {
    final accepted = _accepted.contains(m.portalField);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.portalField,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(m.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabel(m.status),
                    style: TextStyle(color: _statusColor(m.status), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (m.sourceField != null) ...[
              const SizedBox(height: 2),
              Text('Source: ${m.sourceField}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _valueControllers[m.portalField],
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Value to fill',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Confidence: ${(m.confidence * 100).round()}%', style: const TextStyle(fontSize: 11.5)),
                const Spacer(),
                Text('Fill this field', style: const TextStyle(fontSize: 12)),
                Switch(
                  value: accepted,
                  onChanged: (v) => setState(() {
                    if (v) {
                      _accepted.add(m.portalField);
                    } else {
                      _accepted.remove(m.portalField);
                    }
                  }),
                ),
              ],
            ),
            if (m.reason.isNotEmpty)
              Text(m.reason, style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  Widget _buildUnresolvedRow(String portalFieldName, {required bool isConflict}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isConflict ? Colors.red.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(portalFieldName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                ),
                Text(
                  isConflict ? 'Conflict' : 'Missing',
                  style: TextStyle(
                    color: isConflict ? Colors.red.shade700 : Colors.grey.shade800,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isConflict
                  ? 'Two or more sources disagree on this value -- please enter the correct value yourself.'
                  : 'No reliable value was found for this field -- enter one manually if you have it, or leave blank to fill it directly on the portal.',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manualControllers[portalFieldName],
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Enter value (optional)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnything = _mappings.isNotEmpty || widget.response.missing.isNotEmpty || widget.response.conflicts.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('AI AutoFill — Preview')),
      body: !hasAnything
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing for AI AutoFill to add -- every visible field is already covered '
                  'by the existing Auto-Fill, or no AI-eligible fields were found on this page.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final m in _mappings) _buildResolvedRow(m),
                for (final name in widget.response.conflicts) _buildUnresolvedRow(name, isConflict: true),
                for (final name in widget.response.missing) _buildUnresolvedRow(name, isConflict: false),
              ],
            ),
      bottomNavigationBar: hasAnything
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Use These Values'),
                  onPressed: _confirmAndClose,
                ),
              ),
            )
          : null,
    );
  }
}
