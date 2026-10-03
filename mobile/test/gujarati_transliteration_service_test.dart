import 'package:flutter_test/flutter_test.dart';
import 'package:setumitra/services/gujarati_transliteration_service.dart';

void main() {
  group('GujaratiTransliterationService', () {
    test('transliterates રાજેશભાઈ પટેલ to RAJESHBHAI PATEL (proper-name transliteration)', () {
      expect(GujaratiTransliterationService.transliterate('રાજેશભાઈ પટેલ'), 'RAJESHBHAI PATEL');
    });

    test('transliterates ગુજરાત to GUJARAT', () {
      expect(GujaratiTransliterationService.transliterate('ગુજરાત'), 'GUJARAT');
    });

    test('transliterates બોટાદ to BOTAD (word-final schwa deletion)', () {
      expect(GujaratiTransliterationService.transliterate('બોટાદ'), 'BOTAD');
    });

    test('does NOT reproduce the English exonym for અમદાવાદ (that is master data\'s job)', () {
      // Documented, deliberate: algorithmic transliteration of અમદાવાદ is
      // "AMDAVAD"/"AMADAVAD", never the historical exonym "AHMEDABAD" --
      // GujaratMasterData is responsible for that, not this service.
      final result = GujaratiTransliterationService.transliterate('અમદાવાદ');
      expect(result, isNot(equals('AHMEDABAD')));
      expect(result, anyOf('AMADAVAD', 'AMDAVAD'));
    });

    test('passes through pure English/Latin text unchanged (English -> English)', () {
      expect(GujaratiTransliterationService.transliterate('ABC Industries Pvt Ltd'), 'ABC Industries Pvt Ltd');
    });

    test('transliterates only the Gujarati run inside mixed-script text', () {
      expect(GujaratiTransliterationService.transliterate('ABC ગુજરાત Ltd'), 'ABC GUJARAT Ltd');
    });

    test('converts Gujarati digits to Latin digits', () {
      expect(GujaratiTransliterationService.transliterate('૧૨૩'), '123');
    });

    test('containsGujarati detects Gujarati-script text', () {
      expect(GujaratiTransliterationService.containsGujarati('ગુજરાત'), isTrue);
      expect(GujaratiTransliterationService.containsGujarati('GUJARAT'), isFalse);
      expect(GujaratiTransliterationService.containsGujarati(''), isFalse);
    });

    test('degrades gracefully (never throws) on an orphan vowel sign with no preceding consonant', () {
      expect(() => GujaratiTransliterationService.transliterate('ા'), returnsNormally);
    });

    test('handles empty input', () {
      expect(GujaratiTransliterationService.transliterate(''), '');
    });
  });
}
