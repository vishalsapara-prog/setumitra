/// Curated, hand-verified master data for Gujarat state and its 33
/// districts -- per spec Section 8 ("MASTER DATA") / Section 7 ("SOURCE
/// DATA PRIORITY", where VERIFIED MASTER DATA is priority #1, above both
/// the existing deterministic mapping and the AI semantic mapping).
///
/// WHY THIS FILE EXISTS (and why it is deliberately narrow):
/// The spec's own worked example proves algorithmic transliteration is NOT
/// enough for place names: "અમદાવાદ" character-by-character transliterates
/// to "AMDAVAD"/"AMADAVAD", but the required portal value is "AHMEDABAD" --
/// the historical English exonym, not a phonetic rendering. The same is
/// true, to varying degrees, for several other Gujarati districts. A
/// lookup table of real, known values is the only correct way to produce
/// the official English district/state name; [GujaratiTransliterationService]
/// is intentionally only the fallback for everything else (personal names,
/// entity names, free text).
///
/// WHAT IS DELIBERATELY *NOT* IN THIS FILE, AND WHY:
/// The spec's Section 8 also lists "talukas", "cities", "establishment
/// types", "risk categories", "NIC codes" and "portal dropdown options" as
/// master-data examples. Those are NOT hand-enumerated here:
///   - Gujarat has ~250 talukas, and taluka names/boundaries are revised
///     more often than district boundaries. Hand-typing an exhaustive list
///     from memory risks silently writing WRONG administrative data onto a
///     government form -- which is a far worse failure than the field
///     being left for review. That would also violate the spec's own
///     "never invent data" principle, applied to this app's own code.
///   - Establishment types, risk categories and NIC codes are controlled
///     vocabularies defined by the Shramsetu portal itself, not by
///     geography -- the portal's live `<select>` options ARE the correct,
///     current, authoritative source for them (per spec Section 9: "select
///     the EXISTING portal option"). [AiMappingService] resolves these by
///     fuzzy-matching the (transliterated/normalized) source value against
///     the options actually extracted from the live WebView DOM, which is
///     more correct than any value this app could hardcode, and self-heals
///     if the portal adds/renames options in the future.
///   - District and state names, by contrast, are stable, census-level
///     public facts suitable for a static, verifiable lookup table, so
///     they are hardcoded here as the single safe exception.
///
/// The Gujarati-script spellings below use the standard/common orthography
/// for each district name. Administrative Gujarati spelling can have minor
/// regional/typographic variants (e.g. a different vowel-length matra); if
/// a source document uses an unusual spelling this table does not
/// recognise verbatim, [AiMappingService] still has two fallbacks below
/// it in the priority order: algorithmic transliteration, then AI semantic
/// mapping -- so an unrecognised spelling degrades to "best effort",
/// never to a crash or a blank field.
library;

class GujaratMasterData {
  const GujaratMasterData._();

  static const String stateNameEnglish = 'GUJARAT';
  static const String stateNameGujarati = 'ગુજરાત';

  /// Gujarati district name -> official English district name (upper case,
  /// matching how these names are conventionally written on Gujarat
  /// government forms and in the state gazette).
  static const Map<String, String> _districtGujaratiToEnglish = {
    'અમદાવાદ': 'AHMEDABAD',
    'અમરેલી': 'AMRELI',
    'આણંદ': 'ANAND',
    'અરવલ્લી': 'ARAVALLI',
    'બનાસકાંઠા': 'BANASKANTHA',
    'ભરૂચ': 'BHARUCH',
    'ભાવનગર': 'BHAVNAGAR',
    'બોટાદ': 'BOTAD',
    'છોટાઉદેપુર': 'CHHOTA UDEPUR',
    'દાહોદ': 'DAHOD',
    'ડાંગ': 'DANG',
    'દેવભૂમિ દ્વારકા': 'DEVBHOOMI DWARKA',
    'ગાંધીનગર': 'GANDHINAGAR',
    'ગીર સોમનાથ': 'GIR SOMNATH',
    'જામનગર': 'JAMNAGAR',
    'જૂનાગઢ': 'JUNAGADH',
    'ખેડા': 'KHEDA',
    'કચ્છ': 'KUTCH',
    'મહીસાગર': 'MAHISAGAR',
    'મહેસાણા': 'MAHESANA',
    'મોરબી': 'MORBI',
    'નર્મદા': 'NARMADA',
    'નવસારી': 'NAVSARI',
    'પંચમહાલ': 'PANCHMAHAL',
    'પાટણ': 'PATAN',
    'પોરબંદર': 'PORBANDAR',
    'રાજકોટ': 'RAJKOT',
    'સાબરકાંઠા': 'SABARKANTHA',
    'સુરત': 'SURAT',
    'સુરેન્દ્રનગર': 'SURENDRANAGAR',
    'તાપી': 'TAPI',
    'વડોદરા': 'VADODARA',
    'વલસાડ': 'VALSAD',
  };

  /// Alternate English spellings/aliases that different forms, older
  /// records, or portal dropdowns may use for the same district, mapped to
  /// this table's one canonical spelling. Used so e.g. a source document
  /// already in English ("Mehsana", "Kachchh", "The Dangs") still resolves
  /// to the same canonical value as the Gujarati-script source would.
  static const Map<String, String> _englishAliasToCanonical = {
    'AHMADABAD': 'AHMEDABAD',
    'AMDAVAD': 'AHMEDABAD',
    'CHHOTAUDEPUR': 'CHHOTA UDEPUR',
    'CHHOTA-UDEPUR': 'CHHOTA UDEPUR',
    'CHHOTAUDAIPUR': 'CHHOTA UDEPUR',
    'THE DANGS': 'DANG',
    'DANGS': 'DANG',
    'DEVBHUMI DWARKA': 'DEVBHOOMI DWARKA',
    'DWARKA': 'DEVBHOOMI DWARKA',
    'KACHCHH': 'KUTCH',
    'KACHH': 'KUTCH',
    'MEHSANA': 'MAHESANA',
    'PANCH MAHALS': 'PANCHMAHAL',
    'PANCHMAHALS': 'PANCHMAHAL',
  };

  /// All 33 canonical district names, sorted alphabetically -- usable as a
  /// static fallback candidate list for fuzzy-matching when, for some
  /// reason, live DOM dropdown options could not be extracted.
  static List<String> get allDistrictsEnglish {
    final set = _districtGujaratiToEnglish.values.toSet();
    final list = set.toList()..sort();
    return List.unmodifiable(list);
  }

  static String _normalizeGujarati(String s) => s.trim();

  static String _normalizeEnglish(String s) => s.trim().toUpperCase();

  /// Resolves a place-name source value (Gujarati script, English, or an
  /// alias/misspelling of the state or one of its 33 districts) to the
  /// single canonical, upper-case official English name, or `null` if it
  /// is not recognised as the state name or any district name at all (in
  /// which case the caller falls back to transliteration / AI mapping,
  /// per the source-data priority order in spec Section 7).
  static String? lookupPlaceName(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;

    if (_normalizeGujarati(trimmed) == stateNameGujarati) {
      return stateNameEnglish;
    }
    final upperEnglish = _normalizeEnglish(trimmed);
    if (upperEnglish == stateNameEnglish) {
      return stateNameEnglish;
    }

    final directDistrict = _districtGujaratiToEnglish[_normalizeGujarati(trimmed)];
    if (directDistrict != null) return directDistrict;

    if (_districtGujaratiToEnglish.containsValue(upperEnglish)) {
      return upperEnglish;
    }

    final alias = _englishAliasToCanonical[upperEnglish];
    if (alias != null) return alias;

    return null;
  }

  /// True if [source] is recognised as the state name (Gujarati, English,
  /// or a case-insensitive variant).
  static bool isStateName(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return false;
    return _normalizeGujarati(trimmed) == stateNameGujarati ||
        _normalizeEnglish(trimmed) == stateNameEnglish;
  }
}
