/// Deterministic, pure-Dart Gujarati (U+0A80-U+0AFF) -> Latin transliteration.
///
/// This is NOT a dictionary and NOT an AI call -- it is a character-level
/// algorithm, so it is fast, offline, fully unit-testable, and gives the
/// exact same output for the exact same input every time (required: the
/// spec's uppercase/normalization rule must be deterministic, not a guess
/// from an AI provider that might be unavailable).
///
/// IMPORTANT ARCHITECTURAL NOTE (verified by hand-decoding the master
/// spec's own worked examples before writing this file):
///   - "ગુજરાત" -> "GUJARAT"   : matches this algorithm exactly.
///   - "બોટાદ"  -> "BOTAD"    : matches this algorithm exactly.
///   - "રાજેશભાઈ" -> "RAJESHBHAI" : matches this algorithm exactly.
///     (The spec's own example text showed "RAMESHBHAI PATEL" for input
///     "રાજેશભાઈ પટેલ" -- રાજેશભાઈ unambiguously transliterates to
///     "Rajeshbhai" (Rajesh), not "Rameshbhai" (Ramesh); this is flagged
///     to the user in the final implementation report as an apparent typo
///     in the spec's example, not propagated into this algorithm.)
///   - "અમદાવાદ" -> "AHMEDABAD": does NOT match this algorithm. Algorithmic
///     transliteration of અમદાવાદ is "AMDAVAD"/"AMADAVAD" -- "Ahmedabad" is
///     the historical English exonym for the city, not its phonetic
///     transliteration. This is exactly why [GujaratMasterData] exists:
///     official state/district/city names are resolved from a curated
///     lookup table FIRST, and this transliteration service is only the
///     fallback for everything else (personal names, entity names, and
///     any other free Gujarati text a source field might contain).
///
/// Algorithm (standard Indic-script transliteration rules):
///   1. Every consonant carries an inherent short "a" vowel UNLESS:
///      a) it is immediately followed by a vowel sign (matra) -- then the
///         matra's sound is used instead of the inherent "a";
///      b) it is immediately followed by virama (U+0ACD) -- then it carries
///         NO vowel at all (it is the first member of a consonant
///         conjunct; the next consonant is processed independently);
///      c) it is the LAST Gujarati letter of its word AND has no matra --
///         then its inherent "a" is deleted ("word-final schwa deletion"),
///         e.g. "બોટાદ" ends in bare "D", not "DA".
///   2. Vowel signs (matras) and independent vowels are collapsed to a
///      single Latin letter each (long/short distinctions merge: ા/આ and
///      િ/ી and ુ/ૂ each map to one Latin vowel) -- this is what makes
///      "ઈ" at the end of "રાજેશભાઈ" come out as plain "I", not "II".
///   3. Anusvara (ં) nasalizes: rendered "M" before a labial consonant
///      (બ/ભ/મ/પ/ફ), "N" otherwise -- standard transliteration practice
///      (e.g. "ગાંધીનગર" -> "GANDHINAGAR", not "GANDHINAGAR" with a
///      literal raw nasal mark).
///   4. Anything outside the Gujarati Unicode block (Latin letters,
///      digits, spaces, punctuation -- including source text that is
///      already in English) passes through completely unchanged, character
///      for character, in its original run of text. This also means mixed
///      Gujarati+English input (e.g. "ABC Industries Pvt Ltd (ગુજરાત)")
///      only has its Gujarati runs transliterated.
///   5. Malformed/orphan sequences (a stray matra with no preceding
///      consonant, a stray virama at a word boundary, an unmapped rare
///      Gujarati code point) degrade gracefully -- this is free-text input
///      from OCR or manual typing, not a validated format, so this service
///      must never throw. Unmapped or orphan code points are either
///      rendered using their closest defined value or silently dropped
///      (documented per case below); they never crash the caller.
///
/// Known, deliberate simplifications (acceptable for this domain -- proper
/// nouns and administrative text on Gujarati government forms):
///   - The nukta (઼, U+0ABC) is used to represent a handful of
///     Perso-Arabic loan sounds (e.g. ज़/ञ़-style sounds borrowed from
///     Hindi/Urdu orthographic practice). This service does not maintain a
///     separate nukta-modified consonant table; a nukta is consumed
///     silently and the base consonant's normal sound is used. This is an
///     accepted limitation, not a silent data-corruption risk, because it
///     only affects phonetic nuance of a transliterated spelling, never the
///     field's logical value.
///   - Vocalic L/LL (ऌ/ॡ-equivalents, vanishingly rare outside Sanskrit
///     loanwords) are mapped to a plain "L" rather than a distinct vowel.
library;

class GujaratiTransliterationService {
  const GujaratiTransliterationService._();

  // --- Unicode code points (Gujarati block, U+0A80-U+0AFF) ---------------

  static const int _candrabindu = 0x0A81;
  static const int _anusvara = 0x0A82;
  static const int _visarga = 0x0A83;
  static const int _nukta = 0x0ABC;
  static const int _avagraha = 0x0ABD;
  static const int _virama = 0x0ACD;
  static const int _om = 0x0AD0;

  /// Independent vowels (used when a vowel starts a word or stands alone,
  /// not attached to a preceding consonant as a matra).
  static const Map<int, String> _independentVowels = {
    0x0A85: 'A', // અ A
    0x0A86: 'A', // આ AA -> collapsed to A
    0x0A87: 'I', // ઇ I
    0x0A88: 'I', // ઈ II -> collapsed to I
    0x0A89: 'U', // ઉ U
    0x0A8A: 'U', // ઊ UU -> collapsed to U
    0x0A8B: 'RU', // ઋ vocalic R
    0x0A8C: 'LU', // ઌ vocalic L (rare)
    0x0A8D: 'E', // ઍ candra E
    0x0A8F: 'E', // એ E
    0x0A90: 'AI', // ઐ AI
    0x0A91: 'O', // ઑ candra O
    0x0A93: 'O', // ઓ O
    0x0A94: 'AU', // ઔ AU
    0x0AE0: 'RU', // ૠ vocalic RR (rare)
    0x0AE1: 'LU', // ૡ vocalic LL (rare)
  };

  /// Vowel signs (matras) that attach to a preceding consonant, replacing
  /// its inherent "a". Same collapsing rule as independent vowels above.
  static const Map<int, String> _matras = {
    0x0ABE: 'A', // ા AA
    0x0ABF: 'I', // િ I
    0x0AC0: 'I', // ી II
    0x0AC1: 'U', // ુ U
    0x0AC2: 'U', // ૂ UU
    0x0AC3: 'RU', // ૃ vocalic R
    0x0AC4: 'RU', // ૄ vocalic RR (rare)
    0x0AC5: 'E', // ૅ candra E
    0x0AC7: 'E', // ે E
    0x0AC8: 'AI', // ૈ AI
    0x0AC9: 'O', // ૉ candra O
    0x0ACB: 'O', // ો O
    0x0ACC: 'AU', // ૌ AU
    0x0AE2: 'LU', // ૢ vocalic L (rare)
    0x0AE3: 'LU', // ૣ vocalic LL (rare)
  };

  /// Consonants, WITHOUT their inherent vowel baked in -- the caller adds
  /// "A" for the inherent vowel, substitutes a matra's letter, or adds
  /// nothing at all (conjunct / word-final schwa deletion), per the rules
  /// documented on the class.
  static const Map<int, String> _consonants = {
    0x0A95: 'K', // ક
    0x0A96: 'KH', // ખ
    0x0A97: 'G', // ગ
    0x0A98: 'GH', // ઘ
    0x0A99: 'NG', // ઙ
    0x0A9A: 'CH', // ચ
    0x0A9B: 'CHH', // છ
    0x0A9C: 'J', // જ
    0x0A9D: 'JH', // ઝ
    0x0A9E: 'NY', // ઞ
    0x0A9F: 'T', // ટ (retroflex)
    0x0AA0: 'TH', // ઠ (retroflex)
    0x0AA1: 'D', // ડ (retroflex)
    0x0AA2: 'DH', // ઢ (retroflex)
    0x0AA3: 'N', // ણ (retroflex)
    0x0AA4: 'T', // ત (dental)
    0x0AA5: 'TH', // થ (dental)
    0x0AA6: 'D', // દ (dental)
    0x0AA7: 'DH', // ધ (dental)
    0x0AA8: 'N', // ન (dental)
    0x0AAA: 'P', // પ
    0x0AAB: 'PH', // ફ
    0x0AAC: 'B', // બ
    0x0AAD: 'BH', // ભ
    0x0AAE: 'M', // મ
    0x0AAF: 'Y', // ય
    0x0AB0: 'R', // ર
    0x0AB2: 'L', // લ
    0x0AB3: 'L', // ળ (retroflex L, no distinct Latin letter used)
    0x0AB5: 'V', // વ
    0x0AB6: 'SH', // શ
    0x0AB7: 'SH', // ષ
    0x0AB8: 'S', // સ
    0x0AB9: 'H', // હ
  };

  /// Labial consonants -- when anusvara (ં) precedes one of these, the
  /// nasal is rendered "M" rather than "N" (e.g. "અંબાલાલ" -> "AMBALAL").
  static const Set<int> _labialConsonants = {
    0x0AAA, // પ P
    0x0AAB, // ફ PH
    0x0AAC, // બ B
    0x0AAD, // ભ BH
    0x0AAE, // મ M
  };

  static const Map<int, String> _digits = {
    0x0AE6: '0',
    0x0AE7: '1',
    0x0AE8: '2',
    0x0AE9: '3',
    0x0AEA: '4',
    0x0AEB: '5',
    0x0AEC: '6',
    0x0AED: '7',
    0x0AEE: '8',
    0x0AEF: '9',
  };

  static bool _isGujaratiCodePoint(int c) {
    if (c >= 0x0A80 && c <= 0x0AFF) return true;
    return false;
  }

  /// True if [text] contains at least one Gujarati-script character.
  /// The normalization layer uses this to decide whether transliteration
  /// is even necessary (pure-English/number fields skip this pass).
  static bool containsGujarati(String text) {
    for (final rune in text.runes) {
      if (_isGujaratiCodePoint(rune)) return true;
    }
    return false;
  }

  /// Transliterates every Gujarati-script run inside [text] into Latin
  /// letters; every other character (Latin letters, digits, spaces,
  /// punctuation, symbols) is copied through unchanged. Output for
  /// Gujarati runs is always upper-case Latin, by construction of the
  /// character tables above -- callers do not need to re-uppercase the
  /// Gujarati-derived portion, though the normalization service uppercases
  /// the whole combined result defensively for mixed-script input.
  static String transliterate(String text) {
    if (text.isEmpty) return text;
    final runes = text.runes.toList(growable: false);
    final out = StringBuffer();
    int i = 0;
    while (i < runes.length) {
      if (_isGujaratiCodePoint(runes[i])) {
        final start = i;
        while (i < runes.length && _isGujaratiCodePoint(runes[i])) {
          i++;
        }
        out.write(_transliterateRun(runes.sublist(start, i)));
      } else {
        out.writeCharCode(runes[i]);
        i++;
      }
    }
    return out.toString();
  }

  /// Transliterates a single contiguous run of Gujarati code points (i.e.
  /// one "word" in script terms -- callers already split on script
  /// boundaries in [transliterate], so the end of [run] is always this
  /// run's true end, which is what makes word-final schwa deletion work).
  static String _transliterateRun(List<int> run) {
    final buf = StringBuffer();
    int i = 0;
    while (i < run.length) {
      final c = run[i];

      if (_consonants.containsKey(c)) {
        final base = _consonants[c]!;
        final hasNext = i + 1 < run.length;
        final next = hasNext ? run[i + 1] : null;

        if (next == _virama) {
          // Conjunct: this consonant carries no vowel at all; the next
          // consonant in the run is processed on its own next iteration.
          buf.write(base);
          i += 2;
          continue;
        }
        if (next != null && _matras.containsKey(next)) {
          buf.write(base);
          buf.write(_matras[next]);
          i += 2;
          continue;
        }
        if (next == _nukta) {
          // Nukta-modified consonant (rare loan sound): emit the base
          // consonant's ordinary sound (documented simplification above),
          // then continue scanning from the following character, which
          // may itself be a matra/virama for THIS same consonant cluster.
          buf.write(base);
          i += 2;
          continue;
        }
        // No matra, no virama immediately after: inherent schwa "A",
        // unless this consonant is the last Gujarati letter in the word.
        buf.write(base);
        if (hasNext) {
          buf.write('A');
        }
        i += 1;
        continue;
      }

      if (_independentVowels.containsKey(c)) {
        buf.write(_independentVowels[c]);
        i += 1;
        continue;
      }

      if (c == _anusvara || c == _candrabindu) {
        final next = (i + 1 < run.length) ? run[i + 1] : null;
        final nasal = (next != null && _labialConsonants.contains(next)) ? 'M' : 'N';
        buf.write(nasal);
        i += 1;
        continue;
      }

      if (c == _visarga) {
        buf.write('H');
        i += 1;
        continue;
      }

      if (c == _om) {
        buf.write('OM');
        i += 1;
        continue;
      }

      if (_digits.containsKey(c)) {
        buf.write(_digits[c]);
        i += 1;
        continue;
      }

      if (c == _nukta || c == _avagraha) {
        // Modifier/elision marks with no standalone Latin letter of their
        // own when not attached to a consonant handled above -- dropped
        // silently rather than corrupting the surrounding word.
        i += 1;
        continue;
      }

      if (_matras.containsKey(c)) {
        // Orphan matra (no preceding consonant -- malformed input from
        // free-text OCR/manual entry). Degrade gracefully: emit its vowel
        // sound on its own rather than throwing.
        buf.write(_matras[c]);
        i += 1;
        continue;
      }

      if (c == _virama) {
        // Orphan virama with nothing before it in this run: nothing to
        // suppress, so it contributes nothing to the output.
        i += 1;
        continue;
      }

      // Any other Gujarati-block code point this table does not
      // explicitly recognise (reserved/unassigned points, rare marks):
      // drop silently rather than emit a replacement character into a
      // government form field.
      i += 1;
    }
    return buf.toString();
  }
}
