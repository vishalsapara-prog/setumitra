/// Dynamic Shramsetu form data model.
///
/// Backed by a Map<String, dynamic> so it stays in lock-step with the
/// full 162-field ShramsetuFormModel on the backend (backend/app/models.py)
/// without needing a matching Dart class edited every time the portal
/// schema changes. A small set of "core" fields get typed getters/setters
/// for convenience in the UI; everything else is read/written generically
/// via [get] / [set] and flows straight through to the API / webview JS.
class ShramsetuFormModel {
  final Map<String, dynamic> fields;

  ShramsetuFormModel({Map<String, dynamic>? fields}) : fields = fields ?? {};

  /// Canonical field keys, grouped for UI rendering. Mirrors the section
  /// structure of backend/app/models.py / the docxtpl templates.
  static const Map<String, List<String>> sections = {
    'User Registration & Login': [
      'first_name', 'middle_name', 'last_name', 'reg_mobile_number', 'reg_email', 'login_user_id',
    ],
    'Section A — Establishment Details': [
      'establishment_name', 'lin', 'mobile_number', 'email_id', 'head_office_address',
      'corporate_office_address', 'district', 'taluka', 'area', 'pincode',
      'establishment_commencement_date', 'nic_code', 'type_of_establishment', 'type_of_ownership',
      'do_you_intend_employee', 'risk_category', 'size_of_firm', 'investor_type', 'type_of_industry',
    ],
    'Section B — Manpower Distribution (Male / Female / Trans per Category)': [
      'manpower_direct_male', 'manpower_direct_female', 'manpower_direct_trans',
      'manpower_fixed_term_male', 'manpower_fixed_term_female', 'manpower_fixed_term_trans',
      'manpower_interstate_migrant_male', 'manpower_interstate_migrant_female', 'manpower_interstate_migrant_trans',
      'manpower_motor_transport_male', 'manpower_motor_transport_female', 'manpower_motor_transport_trans',
      'manpower_apprentice_male', 'manpower_apprentice_female', 'manpower_apprentice_trans',
    ],
    'Section B2 — Contractor Manpower (Principal Employer form only)': [
      // Confirmed absent from a Contractor's own Establishment Master on
      // the real portal: this row only appears when a Principal Employer
      // declares manpower supplied BY a contractor at their site.
      'manpower_contractor_male', 'manpower_contractor_female', 'manpower_contractor_trans',
    ],
    'Section C — Establishment Documents': [
      'is_pan_registered', 'tan_pan_registration', 'pan_date_of_issue', 'pan_issuing_authority',
      'is_tan_registered', 'tan_registration_no',
      'is_other_registered', 'other_registration_gst',
      'other_registration_date_of_issue', 'other_registration_issuing_authority',
      'is_gumasta_registered', 'shop_establishment_registration',
      'shop_establishment_date_of_issue', 'shop_establishment_issuing_authority',
      'is_epf_registered', 'epf_registration', 'epf_date_of_issue', 'epf_issuing_authority',
      'is_factory_registered', 'factory_registration', 'factory_date_of_issue', 'factory_issuing_authority',
      'is_esi_registered', 'esi_registration', 'esi_date_of_issue', 'esi_issuing_authority',
    ],
    'Section D — Authorized Person': [
      'authorized_person_name', 'authorized_person_email', 'authorized_person_mobile',
      'authorized_person_permanent_address', 'authorized_person_secondary_address',
      'authorized_person_designation', 'authorized_person_identity_number',
      'authorized_person_dob', 'authorized_person_designation_proof',
      'authorized_person_tenure_from', 'authorized_person_tenure_to', 'ein',
    ],
    'Registration — Contract Details': [
      'applicant_name', 'nature_of_work', 'contract_commencement_date', 'contract_completion_date',
      'total_contract_labour', 'establishment_contract_labour_max', 'license_max_workmen_count',
      'office_location_area', 'office_address', 'application_date',
      'application_number', 'application_status',
    ],
    'Registration — Documents, Fee & Status': [
      'already_registered_central_labour_laws', 'probable_commencement_date',
      'expected_completion_date', 'documents_list', 'registration_fee_details',
      'authorized_person_registered_email', 'registration_otp', 'applicant_remark',
      'registration_certificate_no',
    ],
    'Contract Details — Principal Employer (Contractor form only)': [
      'pe_ein_selected', 'pe_registration_no', 'pe_name', 'pe_address',
      'pe_district', 'pe_taluka', 'pe_mobile', 'pe_pincode',
    ],
    'Contract Details — Contractor (Principal Employer form only)': [
      'contractor_ein_selected', 'contractor_registration_no', 'contractor_name',
      'contractor_address', 'contractor_district', 'contractor_taluka',
      'contractor_mobile', 'contractor_pincode',
    ],
    'Section E — Others (Conditional: Factory)': [
      'manufacturing_process_details', 'chemicals_details', 'total_horsepower',
    ],
    'Section E — Others (Conditional: BOCW / Construction)': [
      'type_of_construction_work', 'local_authority_approval_details',
    ],
    'License FORM-25 (Contractor only)': [
      'license_application_type', 'license_office_location', 'license_area', 'license_zone',
      'already_holding_crla_license',
      'license_commencement_date', 'license_completion_date', 'license_nature_of_work',
      'nature_of_work_ids', 'license_covered_district_ids',
      'license_total_contract_labour', 'license_max_workmen_count',
      'license_documents_list', 'license_additional_documents',
      'license_work_order_doc_ref', 'license_other_doc_ref',
      'license_authorized_email', 'license_otp', 'license_fee',
    ],
    'License — Declarations & Undertakings (Contractor only)': [
      'labour_laws_undertaking',
      'conviction_declaration', 'conviction_remarks',
      'prior_order_declaration', 'prior_order_remarks',
    ],
    'License — Auto-Populated Contractor Details (server-fetched via EIN; edit only if incorrect)': [
      'contractor_identification_number', 'contractor_reg_number', 'contractor_name2',
      'contractor_head_office_address', 'contractor_corporate_office_address',
      'contractor_email2', 'contractor_mobile2', 'contractor_commencement_date2',
      'contractor_district2', 'contractor_taluka2', 'contractor_pincode2',
      'contractor_ownership_type', 'contractor_risk_category', 'contractor_nic_code',
      'contractor_manpower_establishment', 'contractor_manpower_contractor2',
      'contractor_manpower_fixed_term2', 'contractor_manpower_interstate2',
      'contractor_manpower_motor_transport2', 'contractor_manpower_total2',
      'contractor_apprentices',
    ],
    'License — Auto-Populated Principal Employer Details (server-fetched via EIN; edit only if incorrect)': [
      'pe_selected_ein', 'pe_reg_number', 'pe_reg_date', 'pe_approval_date', 'pe_est_name',
      'pe_mobile2', 'pe_email2', 'pe_risk_category', 'pe_address2', 'pe_district2',
      'pe_taluka2', 'pe_pincode2', 'pe_type_industry', 'pe_type_establishment',
      'pe_max_workmen_count', 'pe_ownership_type', 'pe_nic_code', 'pe_authorized_person_details',
    ],
    'Bank Guarantee (Contractor only)': [
      'bg_format_number', 'bg_date', 'bg_authority_name', 'bg_area', 'bg_zone',
      'bg_district', 'bg_state',
      'bg_bank_name', 'bg_bank_address', 'bg_bank_ifsc', 'bg_bank_account_number',
      'bg_total_amount', 'bg_validity_period',
      'bg_license_app_number', 'bg_contractor_reg_number', 'bg_contractor_name_address',
      'bg_total_contract_labour', 'bg_security_deposit_per_labour',
      'bg_pe_reg_number', 'bg_pe_name_address',
      'bg_application_status', 'bg_status_email', 'bg_license_certificate',
    ],
  };

  static const List<String> _intFields = [
    'manpower_direct_male', 'manpower_direct_female', 'manpower_direct_trans',
    'manpower_contractor_male', 'manpower_contractor_female', 'manpower_contractor_trans',
    'manpower_fixed_term_male', 'manpower_fixed_term_female', 'manpower_fixed_term_trans',
    'manpower_interstate_migrant_male', 'manpower_interstate_migrant_female', 'manpower_interstate_migrant_trans',
    'manpower_motor_transport_male', 'manpower_motor_transport_female', 'manpower_motor_transport_trans',
    'manpower_apprentice_male', 'manpower_apprentice_female', 'manpower_apprentice_trans',
    'total_contract_labour', 'license_total_contract_labour', 'license_max_workmen_count',
    'establishment_contract_labour_max',
    'contractor_manpower_establishment', 'contractor_manpower_contractor2',
    'contractor_manpower_fixed_term2', 'contractor_manpower_interstate2',
    'contractor_manpower_motor_transport2', 'contractor_manpower_total2',
    'contractor_apprentices', 'pe_max_workmen_count', 'bg_total_contract_labour',
  ];

  static bool isIntField(String key) => _intFields.contains(key);

  // ---- Typed convenience accessors for the most-used core fields ----
  String get establishmentName => (fields['establishment_name'] ?? '') as String;
  set establishmentName(String v) => fields['establishment_name'] = v;

  String get panNumber => (fields['pan_number'] ?? '') as String;
  set panNumber(String v) => fields['pan_number'] = v;

  String get gstin => (fields['gstin'] ?? '') as String;
  set gstin(String v) => fields['gstin'] = v;

  /// Row totals for the Section B manpower matrix (auto-calculated cells).
  int rowTotal(String categoryPrefix) =>
      _asInt(fields['${categoryPrefix}_male']) +
      _asInt(fields['${categoryPrefix}_female']) +
      _asInt(fields['${categoryPrefix}_trans']);

  static const List<String> _manpowerCategories = [
    'manpower_direct', 'manpower_contractor', 'manpower_fixed_term',
    'manpower_interstate_migrant', 'manpower_motor_transport',
  ];

  int get manpowerTotalMale =>
      _manpowerCategories.map((c) => _asInt(fields['${c}_male'])).fold(0, (a, b) => a + b);
  int get manpowerTotalFemale =>
      _manpowerCategories.map((c) => _asInt(fields['${c}_female'])).fold(0, (a, b) => a + b);
  int get manpowerTotalTrans =>
      _manpowerCategories.map((c) => _asInt(fields['${c}_trans'])).fold(0, (a, b) => a + b);

  int get computedManpowerTotal => manpowerTotalMale + manpowerTotalFemale + manpowerTotalTrans;

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  // ---- Generic accessors for every other portal field ----
  dynamic get(String key) => fields[key];

  void set(String key, dynamic value) {
    if (isIntField(key)) {
      fields[key] = _asInt(value);
    } else {
      fields[key] = value?.toString() ?? '';
    }
  }

  String getString(String key) => (fields[key] ?? '').toString();

  factory ShramsetuFormModel.fromJson(Map<String, dynamic> json) {
    return ShramsetuFormModel(fields: Map<String, dynamic>.from(json));
  }

  Map<String, dynamic> toJson() {
    final out = Map<String, dynamic>.from(fields);
    for (final c in _manpowerCategories) {
      out['${c}_total'] = rowTotal(c);
    }
    out['manpower_total_male'] = manpowerTotalMale;
    out['manpower_total_female'] = manpowerTotalFemale;
    out['manpower_total_trans'] = manpowerTotalTrans;
    out['manpower_total'] = computedManpowerTotal;
    return out;
  }

  ShramsetuFormModel copy() => ShramsetuFormModel(fields: Map<String, dynamic>.from(fields));
}
