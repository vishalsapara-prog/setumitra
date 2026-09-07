/// Pure-Dart port of backend/app/models.py's PAN/GSTIN field validators
/// and manpower-matrix computed properties, and backend/app/engine.py's
/// BankGuaranteeCalculator. Mechanical, verified-against-source port for
/// the Path B (native Dart) architecture -- every regex/formula below is
/// unchanged from the Python originals.
library;

/// Result of a validation attempt: [value] is the normalized (uppercased,
/// trimmed) input; [isValid] false means [value] was non-empty but didn't
/// match the required format (mirrors the Python validator's behavior of
/// allowing an empty string through but rejecting a malformed non-empty
/// one).
class ValidationResult {
  final String value;
  final bool isValid;
  final String? error;
  const ValidationResult({required this.value, required this.isValid, this.error});
}

class PanGstinValidator {
  static final RegExp _panPattern = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  static final RegExp _gstinPattern =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');

  /// Ported from models.py `validate_pan`.
  static ValidationResult validatePan(String? raw) {
    final v = (raw ?? '').toUpperCase().trim();
    if (v.isNotEmpty && !_panPattern.hasMatch(v)) {
      return ValidationResult(value: v, isValid: false, error: 'Invalid PAN format');
    }
    return ValidationResult(value: v, isValid: true);
  }

  /// Ported from models.py `validate_gstin`.
  static ValidationResult validateGstin(String? raw) {
    final v = (raw ?? '').toUpperCase().trim();
    if (v.isNotEmpty && !_gstinPattern.hasMatch(v)) {
      return ValidationResult(value: v, isValid: false, error: 'Invalid GSTIN format');
    }
    return ValidationResult(value: v, isValid: true);
  }
}

/// Ported from models.py's `manpower_*_total` computed properties.
/// Field names match ShramsetuFormModel's existing manpower_* keys
/// exactly, so this operates directly on the same Map<String, dynamic>
/// form data structure already used throughout the app.
class ManpowerCalculator {
  static int _asInt(Map<String, dynamic> form, String key) {
    final v = form[key];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static int categoryTotal(Map<String, dynamic> form, String category) {
    return _asInt(form, 'manpower_${category}_male') +
        _asInt(form, 'manpower_${category}_female') +
        _asInt(form, 'manpower_${category}_trans');
  }

  static int directTotal(Map<String, dynamic> form) => categoryTotal(form, 'direct');
  static int contractorTotal(Map<String, dynamic> form) => categoryTotal(form, 'contractor');
  static int fixedTermTotal(Map<String, dynamic> form) => categoryTotal(form, 'fixed_term');
  static int interstateMigrantTotal(Map<String, dynamic> form) => categoryTotal(form, 'interstate_migrant');
  static int motorTransportTotal(Map<String, dynamic> form) => categoryTotal(form, 'motor_transport');

  /// Apprentice is tracked separately and deliberately EXCLUDED from
  /// [computedTotal] below -- the real Shramsetu portal's own JS grand-
  /// total summation never includes Apprentice counts in
  /// TotalEmpWorkersCount. See models.py's manpower_apprentice_total
  /// docstring for the original confirmation of this rule.
  static int apprenticeTotal(Map<String, dynamic> form) => categoryTotal(form, 'apprentice');

  static int totalMale(Map<String, dynamic> form) {
    return _asInt(form, 'manpower_direct_male') +
        _asInt(form, 'manpower_contractor_male') +
        _asInt(form, 'manpower_fixed_term_male') +
        _asInt(form, 'manpower_interstate_migrant_male') +
        _asInt(form, 'manpower_motor_transport_male');
  }

  static int totalFemale(Map<String, dynamic> form) {
    return _asInt(form, 'manpower_direct_female') +
        _asInt(form, 'manpower_contractor_female') +
        _asInt(form, 'manpower_fixed_term_female') +
        _asInt(form, 'manpower_interstate_migrant_female') +
        _asInt(form, 'manpower_motor_transport_female');
  }

  static int totalTrans(Map<String, dynamic> form) {
    return _asInt(form, 'manpower_direct_trans') +
        _asInt(form, 'manpower_contractor_trans') +
        _asInt(form, 'manpower_fixed_term_trans') +
        _asInt(form, 'manpower_interstate_migrant_trans') +
        _asInt(form, 'manpower_motor_transport_trans');
  }

  /// Grand total across all 5 categories x 3 genders (Section B footer
  /// cell). Apprentice deliberately excluded -- see [apprenticeTotal].
  static int computedTotal(Map<String, dynamic> form) {
    return totalMale(form) + totalFemale(form) + totalTrans(form);
  }

  /// Auto-computed cells for the Section B matrix, merged into the form
  /// data map before rendering/saving -- Dart equivalent of
  /// `manpower_render_context()`.
  static Map<String, int> renderContext(Map<String, dynamic> form) {
    return {
      'manpower_direct_total': directTotal(form),
      'manpower_contractor_total': contractorTotal(form),
      'manpower_fixed_term_total': fixedTermTotal(form),
      'manpower_interstate_migrant_total': interstateMigrantTotal(form),
      'manpower_motor_transport_total': motorTransportTotal(form),
      'manpower_total_male': totalMale(form),
      'manpower_total_female': totalFemale(form),
      'manpower_total_trans': totalTrans(form),
      'manpower_apprentice_total': apprenticeTotal(form),
      'computed_manpower_total': computedTotal(form),
    };
  }
}

/// Ported from engine.py's `BankGuaranteeCalculator`. Constants and
/// formula unchanged from the Python original.
///
/// Rounding note: Python's `round(x, 2)` uses banker's rounding;
/// `double.parse(x.toStringAsFixed(2))` below uses round-half-away-from-
/// zero. Verified against a range of realistic (labour, contract_value)
/// inputs with zero divergence for this specific formula shape (labour
/// count multiplied by a clean 500.0, contract value by a clean 0.02, both
/// then maxed against a flat floor) -- the two rounding modes only differ
/// exactly at a .xx5 boundary, which this formula rarely if ever produces
/// in practice. Flagged here rather than silently assumed identical.
class BankGuaranteeCalculator {
  static const double baseRatePerWorker = 500.0;
  static const double minBgAmount = 25000.0;

  static double calculate({required int totalLabour, double contractValue = 0.0}) {
    final byLabour = totalLabour * baseRatePerWorker;
    final byValue = contractValue * 0.02; // 2% of contract value
    final amount = [byLabour, byValue, minBgAmount].reduce((a, b) => a > b ? a : b);
    return double.parse(amount.toStringAsFixed(2));
  }
}
