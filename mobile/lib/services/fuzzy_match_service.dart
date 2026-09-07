/// Approximate string-similarity matching, ported to pure Dart from the
/// Python backend's use of `rapidfuzz.fuzz.partial_ratio`.
///
/// HONEST DISCLOSURE: this is NOT a byte-identical reimplementation of
/// rapidfuzz's algorithm (which internally uses difflib-style matching
/// blocks). It's a hand-written Levenshtein-distance sliding-window
/// approximation that pursues the same goal partial_ratio pursues -- find
/// the best-aligned substring match between a short needle phrase and a
/// longer haystack line, tolerant of OCR noise (dropped/substituted
/// characters) -- without claiming to reproduce rapidfuzz's exact scoring
/// internals. Same disclosure pattern already used once in this project:
/// the Python backend's own test suite substitutes a difflib-based
/// stand-in for rapidfuzz when the real package isn't installable, and
/// documents that substitution rather than hiding it.
class FuzzyMatchService {
  /// Returns a 0-100 similarity score between [needle] and the
  /// best-aligned substring of [haystack], analogous in purpose to
  /// rapidfuzz's `partial_ratio(needle, haystack)`.
  static double partialRatio(String needle, String haystack) {
    final n = needle.trim();
    final h = haystack.trim();
    if (n.isEmpty || h.isEmpty) return 0.0;
    if (h.length <= n.length) {
      return _ratio(n, h) * 100;
    }

    double best = 0.0;
    // Slide a window the length of `n` across `h`, scoring each alignment.
    // This mirrors partial_ratio's intent (best local substring match)
    // without reproducing its exact matching-block internals.
    for (int start = 0; start <= h.length - n.length; start++) {
      final window = h.substring(start, start + n.length);
      final score = _ratio(n, window);
      if (score > best) best = score;
      if (best >= 1.0) break;
    }
    return best * 100;
  }

  /// Normalized similarity in [0, 1] based on Levenshtein edit distance:
  /// 1 - (editDistance / max(len(a), len(b))).
  static double _ratio(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    final dist = _levenshtein(a, b);
    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String a, String b) {
    final la = a.length, lb = b.length;
    if (la == 0) return lb;
    if (lb == 0) return la;
    List<int> prev = List<int>.generate(lb + 1, (j) => j);
    List<int> curr = List<int>.filled(lb + 1, 0);
    for (int i = 1; i <= la; i++) {
      curr[0] = i;
      for (int j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final deletion = prev[j] + 1;
        final insertion = curr[j - 1] + 1;
        final substitution = prev[j - 1] + cost;
        curr[j] = [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[lb];
  }
}
