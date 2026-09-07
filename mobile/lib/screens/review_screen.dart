import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/form_model.dart';
import '../providers/draft_provider.dart';
import '../services/database_service.dart';
import 'webview_screen.dart';

class ReviewScreen extends StatefulWidget {
  final String moduleType;
  final ShramsetuFormModel formData;
  const ReviewScreen({Key? key, required this.moduleType, required this.formData}) : super(key: key);

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late ShramsetuFormModel _model;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _model = widget.formData.copy();

    // Section visibility rules per Shramsetu portal role/flow:
    //  - REGISTRATION (Contractor registering itself): show the
    //    "Principal Employer" counterpart block; hide License/BG; hide the
    //    Contractor-manpower row (confirmed absent from a Contractor's own
    //    real Establishment Master page -- a Contractor doesn't declare
    //    "manpower supplied by a contractor" about itself).
    //  - PE_REGISTRATION (Principal Employer registering itself): show the
    //    "Contractor" counterpart block; hide License/BG; DOES show the
    //    Contractor-manpower row (confirmed present on the real PE page).
    //  - LICENSE (Contractor's FORM-25 application): show everything,
    //    including License FORM-25 + Bank Guarantee and the PE counterpart
    //    block (the PE is named again in the license application itself).
    _visibleSections = ShramsetuFormModel.sections.keys.where((section) {
      final isLicenseOrBg = section.startsWith('License FORM-25') ||
          section.startsWith('License —') ||
          section.startsWith('Bank Guarantee');
      final isPeCounterpart = section.startsWith('Contract Details — Principal Employer');
      final isContractorCounterpart = section.startsWith('Contract Details — Contractor');
      final isContractorManpowerRow = section.startsWith('Section B2 — Contractor Manpower');

      if (widget.moduleType == 'REGISTRATION') {
        return !isLicenseOrBg && !isContractorCounterpart && !isContractorManpowerRow;
      }
      if (widget.moduleType == 'PE_REGISTRATION') {
        return !isLicenseOrBg && !isPeCounterpart;
      }
      // LICENSE flow: full form, minus the Contractor-counterpart block
      // (irrelevant — the applicant IS the Contractor in this flow) and
      // minus the Contractor-manpower row (same reasoning as REGISTRATION).
      return !isContractorCounterpart && !isContractorManpowerRow;
    }).toList();

    for (final section in _visibleSections) {
      for (final key in ShramsetuFormModel.sections[section]!) {
        _controllers[key] = TextEditingController(text: _model.getString(key));
      }
    }
  }

  late final List<String> _visibleSections;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _liveManpowerTotal {
    int sumOf(String key) => int.tryParse(_controllers[key]?.text ?? '0') ?? 0;
    const categories = [
      'manpower_direct', 'manpower_contractor', 'manpower_fixed_term',
      'manpower_interstate_migrant', 'manpower_motor_transport',
    ];
    int total = 0;
    for (final c in categories) {
      total += sumOf('${c}_male') + sumOf('${c}_female') + sumOf('${c}_trans');
    }
    return total;
  }

  Future<void> _saveAndContinue() async {
    for (final entry in _controllers.entries) {
      _model.set(entry.key, entry.value.text);
    }
    _model.set('manpower_total', _liveManpowerTotal);

    await context.read<DraftProvider>().saveDraft(widget.moduleType, _model);
    await _syncMasterDataAndApplication();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WebViewScreen(moduleType: widget.moduleType, formData: _model)),
    );
  }

  /// Wires the Master Data reuse layer into the actual save flow -- until
  /// now, `DatabaseService.findOrCreate*`/`saveApplication` existed and
  /// worked (independently verified) but nothing called them. This is
  /// that missing call. Each `findOrCreate*` is gated on its natural key
  /// being genuinely non-empty, so a section that's hidden for this
  /// moduleType (e.g. Principal Employer counterpart fields for a
  /// PE_REGISTRATION flow, where the PE is the applicant, not a
  /// counterpart being named) doesn't create a junk empty-keyed Master
  /// Data record.
  ///
  /// Bank Details Master is now wired too -- `bg_bank_account_number` was
  /// added to `ShramsetuFormModel` specifically to unblock this (it
  /// didn't exist before, see README). Gated on BOTH IFSC and account
  /// number being non-empty, since the table's uniqueness is the pair
  /// together: an entry with one missing would still risk the same
  /// cross-establishment collision this was deliberately left unwired to
  /// avoid previously.
  Future<void> _syncMasterDataAndApplication() async {
    int? establishmentMasterId;

    if (_model.panNumber.trim().isNotEmpty) {
      final establishment = await DatabaseService.findOrCreateEstablishment(
        panNumber: _model.panNumber,
        gstin: _model.gstin,
        establishmentName: _model.establishmentName,
        headOfficeAddress: _model.getString('head_office_address'),
        pincode: _model.getString('pincode'),
        einNumber: _model.getString('ein'),
        typeOfOwnership: _model.getString('type_of_ownership'),
        typeOfEstablishment: _model.getString('type_of_establishment'),
        mobileNumber: _model.getString('mobile_number'),
        emailId: _model.getString('email_id'),
      );
      establishmentMasterId = establishment.id;
    }

    final authIdentityNumber = _model.getString('authorized_person_identity_number');
    if (authIdentityNumber.trim().isNotEmpty) {
      await DatabaseService.findOrCreateAuthorizedPerson(
        identityNumber: authIdentityNumber,
        name: _model.getString('authorized_person_name'),
        dob: _model.getString('authorized_person_dob'),
        permanentAddress: _model.getString('authorized_person_permanent_address'),
        designation: _model.getString('authorized_person_designation'),
      );
    }

    final peEin = _model.getString('pe_ein_selected');
    if (peEin.trim().isNotEmpty) {
      await DatabaseService.findOrCreatePrincipalEmployer(
        einSelected: peEin,
        registrationNo: _model.getString('pe_registration_no'),
        name: _model.getString('pe_name'),
        address: _model.getString('pe_address'),
        district: _model.getString('pe_district'),
        taluka: _model.getString('pe_taluka'),
        pincode: _model.getString('pe_pincode'),
      );
    }

    final bankIfsc = _model.getString('bg_bank_ifsc');
    final bankAccountNumber = _model.getString('bg_bank_account_number');
    if (bankIfsc.trim().isNotEmpty && bankAccountNumber.trim().isNotEmpty) {
      await DatabaseService.findOrCreateBankDetails(
        bankName: _model.getString('bg_bank_name'),
        ifsc: bankIfsc,
        accountNumber: bankAccountNumber,
      );
    }

    await DatabaseService.saveApplication(
      moduleType: widget.moduleType,
      establishmentMasterId: establishmentMasterId,
      status: 'VERIFIED',
      formJson: jsonEncode(_model.toJson()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review — Establishment & Registration', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in _visibleSections) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  section,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A365D)),
                ),
              ),
              ...ShramsetuFormModel.sections[section]!.map((key) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _controllers[key],
                      keyboardType: ShramsetuFormModel.isIntField(key)
                          ? TextInputType.number
                          : TextInputType.text,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _labelFor(key),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  )),
              if (section.startsWith('Section B — Manpower'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Live Total Manpower: $_liveManpowerTotal',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _saveAndContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B6CB0),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.cloud_upload, color: Colors.white),
              label: const Text('Save Draft & Open Portal', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _labelFor(String key) {
    final words = key.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1));
    return words.join(' ');
  }
}
