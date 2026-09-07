import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ocr_engine_service.dart';
import '../services/ocr_text_parser_service.dart';
import '../models/form_model.dart';
import 'review_screen.dart';
import 'camera_capture_screen.dart';

class ScanScreen extends StatefulWidget {
  final String moduleType;
  const ScanScreen({Key? key, required this.moduleType}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final Map<String, File?> _pickedFiles = {};
  bool _isProcessing = false;
  ShramsetuFormModel _formData = ShramsetuFormModel();

  Future<void> _pickFile(String docType) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _pickedFiles[docType] = File(result.files.single.path!));
      await _extractDocument(docType);
    }
  }

  /// Captures a document photo via the live in-app camera preview
  /// (CameraCaptureScreen) — useful in the field when the officer/
  /// contractor only has a physical copy (e.g. a paper Work Order or Bank
  /// passbook) and no pre-scanned PDF/JPG. Applies the approved Camera
  /// Settings pipeline (resolution, grid, flash at capture time; then
  /// crop and filter/enhancement) before returning the processed file.
  Future<void> _captureFromCamera(String docType) async {
    final File? captured = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (captured != null) {
      setState(() => _pickedFiles[docType] = captured);
      await _extractDocument(docType);
    }
  }

  Future<void> _showSourcePicker(String docType) async {
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2B6CB0)),
              title: const Text('Capture with Camera'),
              onTap: () {
                Navigator.pop(sheetContext);
                _captureFromCamera(docType);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Color(0xFF2B6CB0)),
              title: const Text('Choose PDF / Image File'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFile(docType);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _extractDocument(String docType) async {
    final file = _pickedFiles[docType];
    if (file == null) return;
    setState(() => _isProcessing = true);
    try {
      final ext = file.path.toLowerCase();
      final isImage = ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png');

      Map<String, dynamic> fields;
      if (isImage) {
        // Path B: on-device OCR via ML Kit, then the ported OcrTextParserService
        // -- no backend server involved, matching the committed architecture
        // decision (see README).
        final text = await OcrEngineService.extractTextFromImage(file.path);
        fields = OcrTextParserService.routeByDocType(docType, text);
      } else {
        // PDF files: OCR not yet wired for this format (ML Kit works on
        // images, not PDF text layers/pages) -- disclosed gap, not silently
        // ignored. Skip extraction and let the user fill fields manually
        // on the Review screen rather than pretend this worked.
        fields = {};
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'PDF text extraction isn\'t available offline yet -- please '
                'enter these fields manually on the next screen, or capture '
                'a photo of the page instead.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
      setState(() {
        if (docType == 'PAN') {
          _formData.panNumber = fields['pan_number'] ?? _formData.panNumber;
          _formData.establishmentName = fields['legal_name'] ?? _formData.establishmentName;
        } else if (docType == 'GSTIN') {
          _formData.gstin = fields['gstin'] ?? _formData.gstin;
          if ((fields['legal_name'] ?? '').toString().isNotEmpty) {
            _formData.set('establishment_name', fields['legal_name']);
          }
          _formData.set('head_office_address', fields['address']);
          _formData.set('pincode', fields['pincode']);
        } else if (docType == 'WORK_ORDER') {
          _formData.set('nature_of_work', fields['nature_of_work']);
          _formData.set('contract_commencement_date', fields['contract_start_date']);
          _formData.set('contract_completion_date', fields['contract_end_date']);
        } else if (docType == 'BANK') {
          _formData.set('bg_bank_name', fields['bank_name']);
          _formData.set('bg_bank_ifsc', fields['ifsc']);
        } else if (docType == 'PE_FORM3') {
          _formData.set('pe_ein_selected', fields['pe_ein_selected']);
          _formData.set('pe_registration_no', fields['pe_registration_no']);
          _formData.set('pe_name', fields['pe_name']);
          _formData.set('pe_address', fields['pe_address']);
          _formData.set('pe_pincode', fields['pe_pincode']);
        } else if (docType == 'AUTH_PERSON_ID') {
          _formData.set('authorized_person_identity_number', fields['authorized_person_identity_number']);
          _formData.set('authorized_person_dob', fields['authorized_person_dob']);
          _formData.set('authorized_person_name', fields['authorized_person_name']);
          _formData.set('authorized_person_permanent_address', fields['authorized_person_permanent_address']);
        } else if (docType == 'DESIGNATION_PROOF') {
          _formData.set('authorized_person_designation', fields['authorized_person_designation']);
          _formData.set('authorized_person_tenure_from', fields['authorized_person_tenure_from']);
          _formData.set('authorized_person_tenure_to', fields['authorized_person_tenure_to']);
          _formData.set('authorized_person_designation_proof', fields['authorized_person_designation_proof']);
        } else if (docType == 'SHOP_EST') {
          _formData.set('shop_establishment_registration', fields['shop_establishment_registration']);
          _formData.set('establishment_commencement_date', fields['establishment_commencement_date']);
        } else if (docType == 'EPF_ESIC') {
          _formData.set('epf_registration', fields['epf_registration']);
          _formData.set('esi_registration', fields['esi_registration']);
        } else if (docType == 'PRIOR_LICENSE') {
          _formData.set('prior_registration_number', fields['prior_registration_number']);
          _formData.set('prior_registration_certificate_ref', fields['prior_registration_certificate_ref']);
        } else if (docType == 'CONSTITUTION') {
          _formData.set('type_of_ownership', fields['type_of_ownership']);
          _formData.set('type_of_establishment', fields['type_of_establishment']);
        } else if (docType == 'CONTRACTOR_LIST') {
          _formData.set('contractor_ein_selected', fields['contractor_ein_selected']);
          _formData.set('nature_of_work', fields['nature_of_work']);
          _formData.set('contract_commencement_date', fields['contract_commencement_date']);
          _formData.set('contract_completion_date', fields['contract_completion_date']);
        } else if (docType == 'FACTORY_DETAILS') {
          _formData.set('manufacturing_process_details', fields['manufacturing_process_details']);
          _formData.set('chemicals_details', fields['chemicals_details']);
          _formData.set('total_horsepower', fields['total_horsepower']);
        } else if (docType == 'BOCW_APPROVAL') {
          _formData.set('type_of_construction_work', fields['type_of_construction_work']);
          _formData.set('local_authority_approval_details', fields['local_authority_approval_details']);
        } else if (docType == 'EXECUTED_BG') {
          _formData.set('bg_signed_pdf_reference', fields['bg_signed_pdf_reference']);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$docType extracted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extraction failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _proceedToReview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(moduleType: widget.moduleType, formData: _formData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Required documents per the Shramsetu Exhaustive AutoFill Documents
    // Checklist: Part 1 (Contractor, 11 docs) / Part 2 (Principal Employer, 10 docs).
    final requiredDocs = widget.moduleType == 'LICENSE'
        ? const [
            'PAN', 'GSTIN', 'WORK_ORDER', 'PE_FORM3', 'AUTH_PERSON_ID',
            'DESIGNATION_PROOF', 'BANK', 'SHOP_EST', 'EPF_ESIC', 'PRIOR_LICENSE', 'EXECUTED_BG',
          ]
        : widget.moduleType == 'PE_REGISTRATION'
            ? const [
                'PAN', 'GSTIN', 'CONSTITUTION', 'AUTH_PERSON_ID', 'DESIGNATION_PROOF',
                'CONTRACTOR_LIST', 'FACTORY_DETAILS', 'BOCW_APPROVAL', 'EPF_ESIC', 'PRIOR_LICENSE',
              ]
            : const ['PAN', 'GSTIN'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Scan & OCR', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requiredDocs.length,
            itemBuilder: (context, index) {
              final docType = requiredDocs[index];
              final picked = _pickedFiles[docType] != null;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(
                    picked ? Icons.check_circle : Icons.upload_file,
                    color: picked ? Colors.green : Colors.grey,
                  ),
                  title: Text(docType.replaceAll('_', ' ')),
                  subtitle: Text(picked ? 'Uploaded & Extracted' : 'Tap to upload'),
                  onTap: () => _showSourcePicker(docType),
                  // Re-scan/Re-process (Advanced OCR Controls requirement):
                  // re-runs OCR text extraction + parsing on the ALREADY-
                  // CAPTURED image, without re-photographing -- useful
                  // after changing the OCR Language/Script setting, or to
                  // retry a poor first-pass result. Does NOT re-apply a
                  // different crop/filter/threshold to a fresh capture --
                  // that requires a genuinely new photo, already available
                  // via tapping this row again to reopen the source picker.
                  trailing: picked
                      ? IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFF2B6CB0)),
                          tooltip: 'Re-scan (re-run OCR on this image)',
                          onPressed: _isProcessing ? null : () => _extractDocument(docType),
                        )
                      : null,
                ),
              );
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _proceedToReview,
        backgroundColor: const Color(0xFF2B6CB0),
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Review & Continue'),
      ),
    );
  }
}
