import 'package:flutter_test/flutter_test.dart';
import 'package:setumitra/services/text_normalization_service.dart';

void main() {
  group('TextNormalizationService.classify', () {
    test('classifies an OTP field as sensitiveNeverProcess', () {
      final kind = TextNormalizationService.classify(name: 'registration_otp', label: 'OTP');
      expect(kind, FieldKind.sensitiveNeverProcess);
    });

    test('classifies a CAPTCHA field as sensitiveNeverProcess', () {
      final kind = TextNormalizationService.classify(name: 'captchaInput', label: 'Enter Captcha');
      expect(kind, FieldKind.sensitiveNeverProcess);
    });

    test('classifies a password field as sensitiveNeverProcess (by type and by name)', () {
      expect(TextNormalizationService.classify(name: 'pwd', htmlType: 'password'), FieldKind.sensitiveNeverProcess);
      expect(TextNormalizationService.classify(name: 'LoginPassword'), FieldKind.sensitiveNeverProcess);
    });

    test('classifies an email field', () {
      expect(TextNormalizationService.classify(name: 'EmailID', htmlType: 'email'), FieldKind.email);
    });

    test('classifies a district field', () {
      expect(TextNormalizationService.classify(name: 'DistrictID', label: 'District'), FieldKind.district);
    });

    test('classifies a camelCase compound field name like "StateID" (no delimiter) as state', () {
      expect(TextNormalizationService.classify(name: 'StateID', label: 'State'), FieldKind.state);
    });

    test('classifies an establishment name field', () {
      expect(
        TextNormalizationService.classify(name: 'EstablishmentName', label: 'Name of Establishment'),
        FieldKind.establishmentName,
      );
    });

    test('classifies a person name field', () {
      // Deliberately NOT 'PrincipalEmployerName' here: a "Principal
      // Employer" is itself a business/establishment entity on this
      // portal (the counterpart of "Contractor"), so that field name
      // correctly classifies as FieldKind.establishmentName, not
      // properName -- classify() checks establishment keywords (which
      // include "employer") before person-name keywords precisely so a
      // field like that is not misclassified as a person's name.
      // 'AuthorizedPersonName' is unambiguously a natural person's name
      // (spec Section D, "Authorized Person").
      expect(TextNormalizationService.classify(name: 'AuthorizedPersonName'), FieldKind.properName);
    });

    test('classifies a registration/license number field', () {
      expect(TextNormalizationService.classify(name: 'EPFRegNo'), FieldKind.registrationOrCode);
      expect(TextNormalizationService.classify(name: 'GSTIN'), FieldKind.registrationOrCode);
    });

    test('defaults to genericText for an unrecognised field', () {
      expect(TextNormalizationService.classify(name: 'someRandomField123'), FieldKind.genericText);
    });
  });

  group('TextNormalizationService.normalize', () {
    test('uppercases and transliterates generic text (English CAPITAL output rule)', () {
      expect(TextNormalizationService.normalize('abc industries pvt ltd', FieldKind.genericText), 'ABC INDUSTRIES PVT LTD');
    });

    test('transliterates a Gujarati proper name then uppercases it', () {
      expect(TextNormalizationService.normalize('રાજેશભાઈ પટેલ', FieldKind.properName), 'RAJESHBHAI PATEL');
    });

    test('preserves email exactly (no uppercase, no transliteration)', () {
      expect(TextNormalizationService.normalize('Someone.Name@Example.com', FieldKind.email), 'Someone.Name@Example.com');
    });

    test('preserves URL exactly', () {
      expect(
        TextNormalizationService.normalize('https://ShramSetu.Gujarat.gov.in/Path?x=1', FieldKind.url),
        'https://ShramSetu.Gujarat.gov.in/Path?x=1',
      );
    });

    test('preserves a registration number\'s case/format, converting only Gujarati digits', () {
      expect(TextNormalizationService.normalize('AbC-1234/૫૬', FieldKind.registrationOrCode), 'AbC-1234/56');
    });

    test('never processes a sensitive field -- throws rather than silently returning a value', () {
      expect(
        () => TextNormalizationService.normalize('123456', FieldKind.sensitiveNeverProcess),
        throwsA(isA<StateError>()),
      );
    });

    test('district normalization defers to GujaratMasterData for a recognised value', () {
      expect(TextNormalizationService.normalize('અમદાવાદ', FieldKind.district), 'AHMEDABAD');
    });

    test('district normalization falls back to transliteration for an unrecognised value', () {
      expect(TextNormalizationService.normalize('અજ્ઞાત', FieldKind.district), isNot(isEmpty));
    });
  });
}
