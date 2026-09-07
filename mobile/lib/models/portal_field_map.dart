/// Real Shramsetu portal field-name mapping.
///
/// This maps ShramsetuFormModel's semantic snake_case keys to the ACTUAL
/// `name` attribute used by the live portal's HTML form, extracted directly
/// from real captured portal pages (Establishment Application Master and
/// License FORM-25 for Contractor). Without this map, the webview auto-fill
/// injector would search for elements like `[name="establishment_name"]`
/// (my invented key) when the real portal field is `[name="EstablishmentName"]`
/// (PascalCase) -- a mismatch that would silently fail on every field.
///
/// Fields not present in this map fall back to the generic
/// name/id/data-field guessing in webview_screen.dart, which may or may not
/// hit a real element depending on the portal page.
class PortalFieldMap {
  /// Text inputs, dropdowns (<select>), and textareas: semantic key -> real portal `name`.
  static const Map<String, String> textAndDropdownFields = {
    'already_registered_central_labour_laws': 'toggleEstablishmentRegistered',
    'application_date': 'AppDate',
    'application_number': 'AppID',
    'applicant_name': 'Name',
    'area': 'ddlArea',
    'authorized_person_designation': 'PrincipalDesigID',
    'authorized_person_dob': 'PrincipalDOB',
    'authorized_person_email': 'PrincipalEmail',
    'authorized_person_identity_number': 'PrincipalAadharno',
    'authorized_person_mobile': 'Principalmobile',
    'authorized_person_name': 'PrincipalEmployerName',
    'authorized_person_permanent_address': 'PrincipalPAddress',
    'authorized_person_secondary_address': 'PrincipalSAddress',
    'authorized_person_tenure_from': 'PrincipalFrmDt',
    'authorized_person_tenure_to': 'PrincipalToDt',
    'bg_format_number': 'txtBGNumber',
    'bg_date': 'txtBGIssueDate',
    'bg_signed_pdf_reference': 'fileBGDocument',
    'chemicals_details': 'ChemicalDetailsWithQuantity',
    'contract_commencement_date': 'commencement',
    'contract_completion_date': 'completion',
    'conviction_remarks': 'convictionRemarks',
    'corporate_office_address': 'CorporateAddress',
    'district': 'DistrictID',
    'do_you_intend_employee': 'IntendEmployee',
    'ein': 'EIN',
    'email_id': 'EmailID',
    'epf_date_of_issue': 'EPFDateofIssue',
    'epf_issuing_authority': 'EPFIssuedbyAuthority',
    'epf_registration': 'EPFRegNo',
    'esi_date_of_issue': 'ESILicenceDateofIssue',
    'esi_issuing_authority': 'ESIIssuedbyAuthority',
    'esi_registration': 'ESIRegNo',
    'establishment_commencement_date': 'EstabCommencementDatee',
    'establishment_contract_labour_max': 'EstablismentContlabmax',
    'establishment_name': 'EstablishmentName',
    'expected_completion_date': 'ExpectedDate',
    'factory_date_of_issue': 'FactoryLicenceDateofIssue',
    'factory_issuing_authority': 'FactoryLicenceIssuedbyAuthority',
    'factory_registration': 'FactoryLicenceRegNo',
    'head_office_address': 'Address',
    'investor_type': 'InvestorTypeNewLists',
    'license_area': 'OfficeAreaID',
    'license_commencement_date': 'CommencementDate',
    'license_completion_date': 'CompletionDate',
    'license_fee': 'Registrationfees',
    'license_max_workmen_count': 'MaxEmployerCount',
    'license_office_location': 'OfficeWiseDistrictID',
    'license_zone': 'OfficeZoneID',
    'lin': 'LIN',
    'local_authority_approval_details': 'LocalAuthorityApprovalDetails',
    'login_user_id': 'LoginUserID',
    'manpower_apprentice_female': 'ApprenticeFemaleWorker',
    'manpower_apprentice_male': 'ApprenticeMaleWorker',
    'manpower_apprentice_total': 'ApprenticeTotalWorker',
    'manpower_apprentice_trans': 'ApprenticeTransWorker',
    'manpower_contractor_female': 'ContractFemaleWorker',
    'manpower_contractor_male': 'ContractMaleWorker',
    'manpower_contractor_total': 'ContractorTotalWorker',
    'manpower_contractor_trans': 'ContractTransWorker',
    'manpower_direct_female': 'FemaleWorker',
    'manpower_direct_male': 'MaleWorker',
    'manpower_direct_total': 'TotalWorker',
    'manpower_direct_trans': 'TransWorker',
    'manpower_fixed_term_female': 'FixTermFemaleWorker',
    'manpower_fixed_term_male': 'FixTermMaleWorker',
    'manpower_fixed_term_total': 'FixTermTotalWorker',
    'manpower_fixed_term_trans': 'FixTermTransWorker',
    'manpower_interstate_migrant_female': 'InterMigrantFemaleWorker',
    'manpower_interstate_migrant_male': 'InterMigrantMaleWorker',
    'manpower_interstate_migrant_total': 'InterMigrantTotalWorker',
    'manpower_interstate_migrant_trans': 'InterMigrantTransWorker',
    'manpower_motor_transport_female': 'OthersFemaleWorker',
    'manpower_motor_transport_male': 'OthersMaleWorker',
    'manpower_motor_transport_total': 'OthersTotalWorker',
    'manpower_motor_transport_trans': 'OthersTransWorker',
    'manpower_total': 'TotalEmpWorkersCount',
    'manpower_total_female': 'TotalFemaleEmpWorkersCount',
    'manpower_total_male': 'TotalMaleEmpWorkersCount',
    'manpower_total_trans': 'TotalOtherEmpWorkersCount',
    'manufacturing_process_details': 'ManufacturingProcess',
    'mobile_number': 'MobileNo',
    'nic_code': 'NICCode',
    'office_address': 'OfficeAddress',
    'other_registration_date_of_issue': 'OtherDateofIssue',
    'other_registration_gst': 'OtherRegNo',
    'other_registration_issuing_authority': 'OtherIssuedbyAuthority',
    // pe_name/pe_address/pe_district/pe_taluka/pe_pincode below are
    // confirmed via the real "D. Contract Details" section on a
    // Contractor's own Registration Application page: the ASP.NET
    // markup reuses generically-named "Contractor*" input fields to mean
    // "the other party in the contract" regardless of which role is
    // filling the form -- confirmed by the section header text ("D.
    // Contract Details", matching this exact Dart section) and the
    // immediately-preceding EIN search dropdown listing real establishment
    // names. pe_ein_selected/pe_mobile are deliberately NOT mapped to the
    // page's bare 'EIN'/'MobileNo' fields: those names are already claimed
    // by the top-level 'ein'/'mobile_number' semantic keys for the
    // applicant's OWN establishment on this same page -- mapping both
    // would make the webview auto-fill JS inject two different values into
    // the same DOM element, with whichever runs last silently winning.
    'pe_name': 'ContractorName',
    'pe_address': 'ContractorAddress',
    'pe_district': 'ContractorDistrictName',
    'pe_taluka': 'ContractorTalukaName',
    'pe_pincode': 'ContractorPincode',
    'pan_date_of_issue': 'PanDateofIssue',
    'pan_issuing_authority': 'PanIssuedbyAuthority',
    'pincode': 'Pincode',
    'prior_order_remarks': 'orderRemarks',
    'probable_commencement_date': 'ProbableDate',
    'registration_fee_details': 'Registrationfees',
    'registration_otp': 'OTP',
    'risk_category': 'RiskCategory',
    'shop_establishment_date_of_issue': 'GumsataDateofIssue',
    'shop_establishment_issuing_authority': 'GumsataIssuedbyAuthority',
    'shop_establishment_registration': 'GumsataRegNo',
    'size_of_firm': 'SizeOfFirm',
    'taluka': 'TalukaID',
    'tan_pan_registration': 'PanRegNo',
    'tan_registration_no': 'TanRegNo',
    'total_contract_labour': 'totalContractLabour',
    'total_horsepower': 'TotalHorsepower',
    'type_of_construction_work': 'ConstructionWorkType',
    'type_of_establishment': 'TypeOfBusinessTrade',
    'type_of_industry': 'TypeofEstablishmentIndustryNewLists',
    'type_of_ownership': 'OwnershipTypeID',
  };

  /// Checkbox inputs: semantic key -> real portal `name`. These need
  /// `.checked = <bool>` rather than `.value = ...` in the injection JS.
  static const Map<String, String> checkboxFields = {
    'conviction_declaration': 'convictionCheckbox',
    'is_epf_registered': 'IsEPFReg',
    'is_esi_registered': 'IsESIReg',
    'is_factory_registered': 'IsFactoryReg',
    'is_gumasta_registered': 'IsGumsataReg',
    'is_other_registered': 'IsOtherReg',
    'is_pan_registered': 'IsPANReg',
    'is_tan_registered': 'IsTANReg',
    'labour_laws_undertaking': 'labourLawsCheckbox',
    'prior_order_declaration': 'orderCheckbox',
  };

  /// Fields referenced in the real portal's live JavaScript (calc/AJAX/XML
  /// builder functions) but NOT found as static <input> DOM elements in the
  /// captured HTML snapshot -- likely injected dynamically at runtime.
  /// Included with the same name-matching confidence as the rest, but flagged
  /// here since their exact DOM presence wasn't directly confirmed.
  static const Map<String, String> inferredFields = {
    'manpower_apprentice_female': 'ApprenticeFemaleWorker',
    'manpower_apprentice_male': 'ApprenticeMaleWorker',
    'manpower_apprentice_total': 'ApprenticeTotalWorker',
    'manpower_apprentice_trans': 'ApprenticeTransWorker',
    'manpower_others_female': 'OthersFemaleWorker',
    'manpower_others_male': 'OthersMaleWorker',
    'manpower_others_total': 'OthersTotalWorker',
    'manpower_others_trans': 'OthersTransWorker',
  };

  /// Checkbox-group fields: comma-separated portal checkbox IDs stored in
  /// one semantic field (e.g. 'nature_of_work_ids': '1,5,23'), each ticked
  /// via `<idPrefix>_<id>` on the real portal (natureOfWorkCheckbox_1, etc.).
  static const Map<String, String> checkboxGroupIdPrefixes = {
    'nature_of_work_ids': 'natureOfWorkCheckbox',
    'license_covered_district_ids': 'districtCheckbox',
  };

  /// Resolves a semantic key to its real portal `name` attribute, checking
  /// text/dropdown, checkbox, then inferred maps in that order. Returns null
  /// if no mapping is known (caller should fall back to generic guessing).
  static String? resolve(String semanticKey) {
    return textAndDropdownFields[semanticKey] ??
        checkboxFields[semanticKey] ??
        inferredFields[semanticKey];
  }

  static bool isCheckboxField(String semanticKey) => checkboxFields.containsKey(semanticKey);

  static bool isCheckboxGroupField(String semanticKey) =>
      checkboxGroupIdPrefixes.containsKey(semanticKey);
}
