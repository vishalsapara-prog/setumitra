/// Pure-Dart port of the backend's `ShramsetuDocParser` (backend/app/engine.py)
/// regex-based document field extractors, for the Path B (native Dart)
/// architecture -- no Python backend involved. Ported mechanically,
/// cross-checked line-by-line against the Python source rather than
/// rewritten from memory. Operates on OCR TEXT already produced by
/// `google_mlkit_text_recognition` (the actual OCR engine choice for
/// Path B, chosen for being a mature, verified-publisher, actively
/// maintained on-device package -- see README) -- this file has no
/// dependency on Tesseract or any OCR engine itself, only on the string
/// each engine ultimately produces.
///
/// NOT executed on a real Dart/Flutter runtime in this build environment
/// (no Flutter SDK available here). The underlying fuzzy-match ALGORITHM
/// (see fuzzy_match_service.dart) was independently prototyped and
/// verified correct in Python against this project's own real OCR-noise
/// test fixture before this port was written; the regex patterns below
/// are unchanged from the verified Python originals, translated 1:1
/// (Dart's RegExp and Python's `re` share compatible syntax for every
/// pattern used here -- no named groups, no engine-specific extensions).
library;

import 'fuzzy_match_service.dart';

class OcrTextParserService {
  static final RegExp panRegex = RegExp(r'[A-Z]{5}[0-9]{4}[A-Z]{1}');
  static final RegExp gstRegex = RegExp(r'[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}');
  static final RegExp dateRegex = RegExp(
    r'(?:\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b|'
    r'\b\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'
    r'[a-z]*[\s,]+\d{4}\b)',
    caseSensitive: false,
  );
  static final RegExp ifscRegex = RegExp(r'\b[A-Z]{4}0[A-Z0-9]{6}\b');
  static final RegExp pincodeRegex = RegExp(r'\b\d{6}\b');
  static final RegExp _trailingTokenRegex = RegExp(r'[A-Za-z0-9][A-Za-z0-9/\-.]{3,}');

  /// Extracts the trailing code-like token from a line. Allows "." as a
  /// mid-token character (stripped if trailing) since OCR sometimes
  /// misreads a hyphen as a period within a registration number.
  static String _extractTrailingToken(String line) {
    final tokens = _trailingTokenRegex.allMatches(line).map((m) => m.group(0)!).toList();
    if (tokens.isEmpty) return '';
    final last = tokens.last;
    return last.endsWith('.') ? last.substring(0, last.length - 1) : last;
  }

  /// Stage 1 of the two-stage EPF/ESIC extraction: a line literally
  /// starting with one of the given identity prefixes (e.g.
  /// "PF"/"EPF"/"EPFO"). Preferred over pure fuzzy phrase-matching where
  /// possible -- fuzzy matching against generic phrases like "Registration
  /// No" is vulnerable to a real, previously-reproduced bug class where a
  /// shared generic word scores a higher match against the WRONG field's
  /// line. Returns null if no line starts with any given prefix.
  static String? identityPrefixLineExtract(String text, List<String> identityPrefixes) {
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();
      for (final tok in identityPrefixes) {
        if (upper.startsWith(tok.toUpperCase())) {
          return _extractTrailingToken(line);
        }
      }
    }
    return null;
  }

  /// Stage 2 fallback: finds the line most similar (via the approximate
  /// partial-ratio fuzzy match) to any of the given label phrases, then
  /// extracts its trailing code-like token. Callers with a reliable short
  /// identity token should prefer [identityPrefixLineExtract] first.
  static String fuzzyLineExtract(String text, List<String> labelKeywords, {double minScore = 60.0}) {
    String? bestLine;
    double bestScore = 0.0;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      for (final kw in labelKeywords) {
        final score = FuzzyMatchService.partialRatio(kw.toUpperCase(), line.toUpperCase());
        if (score > bestScore) {
          bestScore = score;
          bestLine = line;
        }
      }
    }
    if (bestScore < minScore || bestLine == null) return '';
    return _extractTrailingToken(bestLine);
  }

  static Map<String, String> parsePan(String text) {
    final upper = text.toUpperCase();
    final panMatch = panRegex.firstMatch(upper);
    final pan = panMatch?.group(0) ?? '';
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    String name = '', dob = '';
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.toUpperCase().contains('INCOME TAX DEPARTMENT') || l.toUpperCase().contains('GOVT. OF INDIA')) {
        if (i + 1 < lines.length) name = lines[i + 1];
      }
      final dt = dateRegex.firstMatch(l);
      if (dt != null && dob.isEmpty) dob = dt.group(0)!;
    }
    return {'pan_number': pan, 'legal_name': name, 'dob': dob};
  }

  static Map<String, String> parseGst(String text) {
    final upper = text.toUpperCase();
    final gstMatch = gstRegex.firstMatch(upper);
    final gstin = gstMatch?.group(0) ?? '';
    String legalName = '', tradeName = '', address = '', pincode = '';
    final lM = RegExp(r'Legal Name\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    if (lM != null) legalName = lM.group(1)!.trim();
    final tM = RegExp(r'Trade Name\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    if (tM != null) tradeName = tM.group(1)!.trim();
    final aM = RegExp(r'Address\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    if (aM != null) address = aM.group(1)!.trim();
    final pinMatches = pincodeRegex.allMatches(text).toList();
    if (pinMatches.isNotEmpty) pincode = pinMatches.last.group(0)!;
    return {
      'gstin': gstin,
      'legal_name': legalName,
      'trade_name': tradeName,
      'address': address,
      'pincode': pincode,
    };
  }

  static Map<String, String> parseBankDetails(String text) {
    final upper = text.toUpperCase();
    final ifscMatch = ifscRegex.firstMatch(upper);
    final ifsc = ifscMatch?.group(0) ?? '';
    final accM = RegExp(r'(?:A/?C|Account)\s*(?:No\.?)?\s*[:\-]?\s*(\d{9,18})', caseSensitive: false).firstMatch(text);
    final accountNumber = accM?.group(1) ?? '';
    final bankM = RegExp(r'Bank\s*Name\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    final bankName = bankM != null ? bankM.group(1)!.trim() : '';
    return {'ifsc': ifsc, 'account_number': accountNumber, 'bank_name': bankName};
  }

  static Map<String, String> parseWorkOrder(String text) {
    final dates = dateRegex.allMatches(text).map((m) => m.group(0)!).toList();
    final startDate = dates.isNotEmpty ? dates[0] : '';
    final endDate = dates.length >= 2 ? dates[1] : '';
    final valueM = RegExp(r'(?:Contract\s*Value|Total\s*Value)\s*[:\-]?\s*₹?\s*([\d,]+)', caseSensitive: false).firstMatch(text);
    final value = valueM?.group(1) ?? '';
    final natureM = RegExp(r'Nature\s*of\s*Work\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    final nature = natureM != null ? natureM.group(1)!.trim() : '';
    return {
      'contract_start_date': startDate,
      'contract_end_date': endDate,
      'contract_value': value,
      'nature_of_work': nature,
    };
  }

  static Map<String, String> parsePeForm3(String text) {
    final einM = RegExp(r'\bEIN\s*[:\-]?\s*([A-Z0-9]{6,20})', caseSensitive: false).firstMatch(text);
    final regM = RegExp(r'Registration\s*(?:No\.?|Number)\s*[:\-]?\s*([A-Za-z0-9/\-]+)', caseSensitive: false).firstMatch(text);
    final dateM = dateRegex.firstMatch(text);
    final nameM = RegExp(r'(?:Establishment|Principal Employer)\s*Name\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    final addrM = RegExp(r'Address\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    final pinMatches = pincodeRegex.allMatches(text).toList();
    return {
      'pe_ein_selected': einM?.group(1) ?? '',
      'pe_registration_no': regM?.group(1) ?? '',
      'pe_reg_date': dateM?.group(0) ?? '',
      'pe_name': nameM != null ? nameM.group(1)!.trim() : '',
      'pe_address': addrM != null ? addrM.group(1)!.trim() : '',
      'pe_pincode': pinMatches.isNotEmpty ? pinMatches.last.group(0)! : '',
    };
  }

  static Map<String, String> parseAuthPersonId(String text) {
    final upper = text.toUpperCase();
    final panMatch = panRegex.firstMatch(upper);
    final dobM = dateRegex.firstMatch(text);
    final nameM = RegExp(r'Name\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    final addrM = RegExp(r'Address\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    return {
      'authorized_person_identity_number': panMatch?.group(0) ?? '',
      'authorized_person_dob': dobM?.group(0) ?? '',
      'authorized_person_name': nameM != null ? nameM.group(1)!.trim() : '',
      'authorized_person_permanent_address': addrM != null ? addrM.group(1)!.trim() : '',
    };
  }

  static Map<String, String> parseDesignationProof(String text) {
    final designationM = RegExp(r'Designat(?:ion|ed\s*as)\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    final dates = dateRegex.allMatches(text).map((m) => m.group(0)!).toList();
    return {
      'authorized_person_designation': designationM != null ? designationM.group(1)!.trim() : '',
      'authorized_person_tenure_from': dates.isNotEmpty ? dates[0] : '',
      'authorized_person_tenure_to': dates.length > 1 ? dates[1] : '',
      'authorized_person_designation_proof': 'Extracted from uploaded document; verify manually.',
    };
  }

  static Map<String, String> parseShopEstablishment(String text) {
    final regM = RegExp(r'Reg(?:istration)?\.?\s*(?:No\.?|Number)\s*[:\-]?\s*([A-Za-z0-9/\-]+)', caseSensitive: false).firstMatch(text);
    final dateM = dateRegex.firstMatch(text);
    return {
      'shop_establishment_registration': regM?.group(1) ?? '',
      'establishment_commencement_date': dateM?.group(0) ?? '',
    };
  }

  /// Document #9: EPF & ESIC registration proof -- the two-stage extractor
  /// (identity-prefix first, fuzzy fallback second) that fixed two real
  /// cross-contamination bugs found via repeated real-execution testing
  /// in the Python backend. See fuzzy_match_service.dart and
  /// identityPrefixLineExtract's docstring for the full rationale.
  static Map<String, String> parseEpfEsic(String text) {
    String epfCode = identityPrefixLineExtract(text, ['PF', 'EPF', 'EPFO']) ??
        fuzzyLineExtract(text, ['EPF Registration No', 'EPFO Code', 'PF Registration']);
    String esicCode = identityPrefixLineExtract(text, ['ESI', 'ESIC']) ??
        fuzzyLineExtract(text, ['ESIC Code', 'ESI Code']);
    return {'epf_registration': epfCode, 'esi_registration': esicCode};
  }

  static Map<String, String> parsePriorLicense(String text) {
    final regNumber = fuzzyLineExtract(text, ['License Number', 'Licence Number', 'Registration Number']);
    return {
      'prior_registration_number': regNumber,
      'prior_registration_certificate_ref': 'Extracted from uploaded document; verify manually.',
    };
  }

  static Map<String, String> parseConstitutionProof(String text) {
    const ownershipKeywords = {
      'PRIVATE LIMITED': 'Private Limited',
      'PUBLIC LIMITED': 'Public Limited',
      'PARTNERSHIP': 'Partnership',
      'PROPRIETORSHIP': 'Sole Proprietorship',
      'TRUST': 'Trust',
      'SOCIETY': 'Society',
      'GOVERNMENT': 'Government',
      'CORPORATION': 'Corporation',
      'LLP': 'Limited Liability Partnership',
    };
    final upper = text.toUpperCase();
    String ownershipType = '';
    for (final entry in ownershipKeywords.entries) {
      if (upper.contains(entry.key)) {
        ownershipType = entry.value;
        break;
      }
    }
    return {
      'type_of_ownership': ownershipType,
      'type_of_establishment': 'Extracted from uploaded document; verify manually.',
    };
  }

  static Map<String, String> parseContractorList(String text) {
    final einMatches = RegExp(r'\bEIN\s*[:\-]?\s*([A-Z0-9]{6,20})', caseSensitive: false).allMatches(text).toList();
    final dates = dateRegex.allMatches(text).map((m) => m.group(0)!).toList();
    final natureM = RegExp(r'Nature\s*of\s*Work\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(text);
    return {
      'contractor_ein_selected': einMatches.isNotEmpty ? einMatches.first.group(1)! : '',
      'nature_of_work': natureM != null ? natureM.group(1)!.trim() : '',
      'contract_commencement_date': dates.isNotEmpty ? dates[0] : '',
      'contract_completion_date': dates.length > 1 ? dates[1] : '',
    };
  }

  static Map<String, String> parseFactoryDetails(String text) {
    final hpM = RegExp(r'(?:Total\s*)?Horsepower\s*(?:\(HP\))?\s*[:\-]?\s*([\d.]+)', caseSensitive: false).firstMatch(text);
    return {
      'manufacturing_process_details': 'Extracted from uploaded document; verify manually.',
      'chemicals_details': 'Extracted from uploaded document; verify manually.',
      'total_horsepower': hpM?.group(1) ?? '',
    };
  }

  static Map<String, String> parseBocwApproval(String text) {
    return {
      'type_of_construction_work': 'Extracted from uploaded document; verify manually.',
      'local_authority_approval_details': 'Extracted from uploaded document; verify manually.',
    };
  }

  /// Routes an uploaded document to its parser -- Dart port of
  /// `route_by_doc_type`, covering all 14 doc types the Python backend
  /// handles (the previous gap -- FACTORY_DETAILS/BOCW_APPROVAL/
  /// EXECUTED_BG -- is now closed).
  static Map<String, String> routeByDocType(String docType, String text) {
    final dt = docType.toUpperCase();
    switch (dt) {
      case 'PAN':
        return parsePan(text);
      case 'GSTIN':
      case 'GST':
        return parseGst(text);
      case 'BANK':
        return parseBankDetails(text);
      case 'WORK_ORDER':
        return parseWorkOrder(text);
      case 'PE_FORM3':
        return parsePeForm3(text);
      case 'AUTH_PERSON_ID':
        return parseAuthPersonId(text);
      case 'DESIGNATION_PROOF':
        return parseDesignationProof(text);
      case 'SHOP_EST':
        return parseShopEstablishment(text);
      case 'EPF_ESIC':
        return parseEpfEsic(text);
      case 'PRIOR_LICENSE':
        return parsePriorLicense(text);
      case 'CONSTITUTION':
        return parseConstitutionProof(text);
      case 'CONTRACTOR_LIST':
        return parseContractorList(text);
      case 'FACTORY_DETAILS':
        return parseFactoryDetails(text);
      case 'BOCW_APPROVAL':
        return parseBocwApproval(text);
      case 'EXECUTED_BG':
        return {'bg_signed_pdf_reference': 'Uploaded; cross-check bg_format_number manually.'};
      default:
        final matches = panRegex.allMatches(text.toUpperCase()).map((m) => m.group(0)!).toList();
        return {'raw_matches_pan': matches.join(',')};
    }
  }
}
