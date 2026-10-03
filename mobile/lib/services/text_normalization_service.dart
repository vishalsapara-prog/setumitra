/// Field-aware output normalization for AI AutoFill -- spec Sections 10
/// ("LANGUAGE AND OUTPUT RULE") and 11 ("UPPERCASE EXCEPTIONS").
///
/// MANDATORY RULE (verbatim from the user): all government portal form
/// values filled by AI AutoFill must be English, UPPERCASE. Source data
/// may be Gujarati, English, or mixed; the AI may understand Gujarati, but
/// the value actually written into the portal must always be English
/// upper-case text wherever the portal expects text -- EXCEPT for a fixed
/// set of field kinds the spec carves out explicitly, where forcing
/// uppercase or transliterating would corrupt the value's real meaning:
/// email, URL, dates, registration/reference numbers, and codes (preserve
/// exactly, do not force-case them), and password/OTP/CAPTCHA (never
/// processed through this pipeline -- or any AI pipeline -- at all).
///
/// This service is pure, synchronous, offline Dart: no network, no AI
/// call. It runs on every value right before it is shown in the Preview
/// screen, so what the user reviews is exactly what would be written to
/// the portal.
library;

import 'gujarati_transliteration_service.dart';
import '../models/gujarat_master_data.dart';

/// The semantic kind of a portal/source field, used to pick the correct
/// normalization behaviour. This is intentionally a flat, small enum --
/// per spec Section 21, portal-specific nuance belongs in a per-portal
/// mapping *profile*, not in new kinds added here for every new form.
enum FieldKind {
  /// Free-form text with no special handling: uppercase English, with
  /// Gujarati-script input transliterated first.
  genericText,

  /// A person's or entity's proper name: transliterated then upper-cased,
  /// never semantically translated (per spec Section 10's explicit
  /// warning: "Do NOT blindly translate proper names").
  properName,

  /// Establishment/company/firm name: same handling as [properName].
  establishmentName,

  /// Gujarat district name: resolved via [GujaratMasterData] first (spec
  /// Section 8/9), falling back to transliteration only if not recognised.
  district,

  /// "Gujarat" / state name: same master-data-first handling as [district].
  state,

  /// Must be preserved with valid email semantics -- never transliterated,
  /// never case-changed (spec Section 11: "Email: preserve valid email
  /// semantics").
  email,

  /// Preserved exactly -- never transliterated, never case-changed (spec
  /// Section 11: "URL: preserve URL").
  url,

  /// A date value. Only Gujarati-numeral digits (જો કોઈ હોય તો) are
  /// converted to Latin digits; separators/order are left untouched here
  /// -- reformatting into the portal's exact required date format is the
  /// mapping service's/portal profile's job, not this normalizer's (spec
  /// Section 11: "Dates: use the portal's required date format").
  date,

  /// Registration numbers, licence numbers, GSTIN/PAN/EPF/ESI numbers and
  /// similar official codes: preserved exactly as given (only Gujarati
  /// digits, if any, are converted to Latin digits), never upper-cased or
  /// otherwise reformatted, since altering case/format could change their
  /// official meaning (spec Section 11: "Registration/reference numbers:
  /// preserve the official value and format" / "Codes: preserve official
  /// code format").
  registrationOrCode,

  /// Password / OTP / CAPTCHA. [TextNormalizationService.normalize] refuses
  /// to process this kind at all -- per spec Sections 16/17/31, these must
  /// never be touched by any AI/automated pipeline. This is defense in
  /// depth: [AiPortalFieldDescriptor.isSensitive] and
  /// [AiMappingService] already exclude these fields far upstream, before
  /// a value would ever reach this far.
  sensitiveNeverProcess,
}

class TextNormalizationService {
  const TextNormalizationService._();

  static final RegExp _multiSpace = RegExp(r'\s+');

  /// Classifies a portal field's semantic kind from its machine-readable
  /// identity (name/id/label/placeholder/type), so the correct
  /// normalization rule is applied automatically. Matching is substring-
  /// based (via [_hasAny]/[_wordHaystack]), deliberately -- NOT exact-
  /// word matching -- because this portal's real field names are
  /// un-delimited camelCase compounds (`DistrictID`, `OfficeWiseDistrictID`,
  /// `EstablishmentName`), which exact word-splitting would fail to
  /// classify at all. The trade-off, accepted for this specific field-name
  /// vocabulary (verified against the existing deterministic
  /// `PortalFieldMap`): a keyword could in principle match inside an
  /// unrelated longer word (e.g. a hypothetical "statement" field would
  /// match the "state" keyword); no such collision exists in this portal's
  /// actual field names today. A future portal profile with a colliding
  /// field name should add a more specific keyword (or an exclusion) here
  /// rather than relying on an exact-match rewrite that would break the
  /// compound-identifier cases above.
  static FieldKind classify({
    required String name,
    String? id,
    String? label,
    String? placeholder,
    String? htmlType,
  }) {
    final type = (htmlType ?? '').trim().toLowerCase();
    if (type == 'password') return FieldKind.sensitiveNeverProcess;

    final haystack = _wordHaystack('$name ${id ?? ''} ${label ?? ''} ${placeholder ?? ''}');

    if (_hasAny(haystack, const ['password', 'passwd', 'pwd'])) {
      return FieldKind.sensitiveNeverProcess;
    }
    if (_hasAny(haystack, const ['otp', 'onetimepassword'])) {
      return FieldKind.sensitiveNeverProcess;
    }
    if (_hasAny(haystack, const ['captcha'])) {
      return FieldKind.sensitiveNeverProcess;
    }

    if (type == 'email' || _hasAny(haystack, const ['email', 'emailid', 'emailaddress'])) {
      return FieldKind.email;
    }
    if (type == 'url' ||
        _hasAny(haystack, const ['url', 'website', 'weburl', 'webaddress', 'hyperlink'])) {
      return FieldKind.url;
    }
    if (type == 'date' ||
        _hasAny(haystack, const ['date', 'dob', 'dateofbirth', 'startdate', 'enddate', 'issuedate', 'expirydate'])) {
      return FieldKind.date;
    }

    if (_hasAny(haystack, const [
      'registration',
      'regno',
      'regnumber',
      'licence',
      'license',
      'licenceno',
      'licenseno',
      'certificateno',
      'certificatenumber',
      'gstin',
      'gst',
      'pan',
      'panno',
      'epf',
      'esic',
      'esi',
      'tin',
      'cin',
      'udyam',
      'code',
      'pincode',
      'pin',
      'ifsc',
      'accountnumber',
      'acno',
      'mobileno',
      'mobile',
      'phone',
      'phoneno',
      'contactno',
    ])) {
      return FieldKind.registrationOrCode;
    }

    if (_hasAny(haystack, const ['district'])) return FieldKind.district;
    if (_hasAny(haystack, const ['state'])) return FieldKind.state;

    if (_hasAny(haystack, const [
      'establishment',
      'company',
      'companyname',
      'firm',
      'firmname',
      'organisation',
      'organization',
      'unit',
      'factory',
      'shop',
      'employer',
      'employername',
      'principalemployer',
      'business',
      'businessname',
      'tradename',
    ])) {
      return FieldKind.establishmentName;
    }

    if (_hasAny(haystack, const [
      'name',
      'fullname',
      'firstname',
      'lastname',
      'middlename',
      'fathername',
      'husbandname',
      'guardianname',
      'contactperson',
      'authorizedperson',
      'authorisedperson',
      'applicantname',
      'ownername',
      'signatory',
    ])) {
      return FieldKind.properName;
    }

    return FieldKind.genericText;
  }

  /// Produces the exact string that should be written into the portal (or
  /// shown in the Preview screen as the proposed value), for a value whose
  /// semantic kind is [kind]. Throws [StateError] for
  /// [FieldKind.sensitiveNeverProcess] -- this is intentional: no caller
  /// should ever reach this method for a password/OTP/CAPTCHA field, and a
  /// loud failure here is far safer than a normalized value silently
  /// flowing somewhere it must never go.
  static String normalize(String rawValue, FieldKind kind) {
    switch (kind) {
      case FieldKind.sensitiveNeverProcess:
        throw StateError(
          'TextNormalizationService.normalize() must never be called for '
          'password/OTP/CAPTCHA fields. The caller must exclude these '
          'fields before reaching the normalization layer.',
        );

      case FieldKind.email:
        return rawValue.trim();

      case FieldKind.url:
        return rawValue.trim();

      case FieldKind.date:
        return _collapseWhitespace(GujaratiTransliterationService.transliterate(rawValue).trim());

      case FieldKind.registrationOrCode:
        return _collapseWhitespace(GujaratiTransliterationService.transliterate(rawValue).trim());

      case FieldKind.district:
      case FieldKind.state:
        final master = GujaratMasterData.lookupPlaceName(rawValue);
        if (master != null) return master;
        return _transliterateAndUppercase(rawValue);

      case FieldKind.properName:
      case FieldKind.establishmentName:
      case FieldKind.genericText:
        return _transliterateAndUppercase(rawValue);
    }
  }

  static String _transliterateAndUppercase(String rawValue) {
    final transliterated = GujaratiTransliterationService.containsGujarati(rawValue)
        ? GujaratiTransliterationService.transliterate(rawValue)
        : rawValue;
    return _collapseWhitespace(transliterated.trim()).toUpperCase();
  }

  static String _collapseWhitespace(String s) => s.replaceAll(_multiSpace, ' ');

  static String _wordHaystack(String s) {
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (final rune in lower.runes) {
      final isAlnum = (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7A);
      buf.writeCharCode(isAlnum ? rune : 0x20);
    }
    // Also keep a no-separator form so multi-word keys like "emailid"
    // match whether the source used "email_id", "email id" or "emailId".
    final spaced = buf.toString();
    final squashed = spaced.replaceAll(' ', '');
    return '$spaced $squashed';
  }

  static bool _hasAny(String haystack, List<String> keywords) {
    for (final k in keywords) {
      if (haystack.contains(k)) return true;
    }
    return false;
  }
}
