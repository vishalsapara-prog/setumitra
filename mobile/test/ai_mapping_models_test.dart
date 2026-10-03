import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:setumitra/models/ai_mapping_models.dart';

void main() {
  group('AiConfidenceThresholds.classify (Confidence rules)', () {
    const thresholds = AiConfidenceThresholds.defaults();

    test('>= 95% is eligible for automatic mapping (matched)', () {
      expect(thresholds.classify(0.95), MappingStatus.matched);
      expect(thresholds.classify(0.99), MappingStatus.matched);
      expect(thresholds.classify(1.0), MappingStatus.matched);
    });

    test('80%-94% requires review', () {
      expect(thresholds.classify(0.80), MappingStatus.reviewRequired);
      expect(thresholds.classify(0.94), MappingStatus.reviewRequired);
    });

    test('< 80% is never eligible for automatic fill (still reviewRequired, never matched)', () {
      expect(thresholds.classify(0.0), isNot(MappingStatus.matched));
      expect(thresholds.classify(0.79), isNot(MappingStatus.matched));
    });
  });

  group('AiPortalFieldDescriptor.isSensitive', () {
    test('flags an OTP field', () {
      final d = AiPortalFieldDescriptor(name: 'registration_otp', type: 'text', label: 'OTP');
      expect(d.isSensitive, isTrue);
    });

    test('flags a CAPTCHA field', () {
      final d = AiPortalFieldDescriptor(name: 'captchaCode', type: 'text');
      expect(d.isSensitive, isTrue);
    });

    test('flags a password-typed field even with an unrelated name', () {
      final d = AiPortalFieldDescriptor(name: 'secret1', type: 'password');
      expect(d.isSensitive, isTrue);
    });

    test('does not flag an ordinary text field', () {
      final d = AiPortalFieldDescriptor(name: 'EstablishmentName', type: 'text');
      expect(d.isSensitive, isFalse);
    });
  });

  group('AiMappingResponse.fromJsonString (structured JSON output / validation)', () {
    test('parses a well-formed response matching the spec-mandated shape exactly', () {
      final raw = jsonEncode({
        'mappings': [
          {
            'portal_field': 'EstablishmentName',
            'source_field': 'establishment_name',
            'value': 'ABC INDUSTRIES PVT LTD',
            'confidence': 0.97,
            'reason': 'Matched establishment-name semantic label',
          },
        ],
        'missing': ['factory_registration'],
        'conflicts': [],
        'review_required': [],
      });

      final response = AiMappingResponse.fromJsonString(raw);
      expect(response.succeeded, isTrue);
      expect(response.mappings, hasLength(1));
      expect(response.mappings.first.portalField, 'EstablishmentName');
      expect(response.mappings.first.value, 'ABC INDUSTRIES PVT LTD');
      expect(response.mappings.first.status, MappingStatus.matched);
      expect(response.missing, ['factory_registration']);
    });

    test('rejects non-JSON input safely (never partially trusts it)', () {
      expect(
        () => AiMappingResponse.fromJsonString('this is not json'),
        throwsA(isA<AiMappingFormatException>()),
      );
    });

    test('rejects a JSON root that is not an object', () {
      expect(
        () => AiMappingResponse.fromJsonString('[1, 2, 3]'),
        throwsA(isA<AiMappingFormatException>()),
      );
    });

    test('rejects a response missing the required "mappings" array', () {
      expect(
        () => AiMappingResponse.fromJsonString(jsonEncode({'missing': [], 'conflicts': [], 'review_required': []})),
        throwsA(isA<AiMappingFormatException>()),
      );
    });

    test('rejects a mapping entry with a non-numeric confidence', () {
      final raw = jsonEncode({
        'mappings': [
          {'portal_field': 'X', 'value': 'Y', 'confidence': 'high', 'reason': 'r'},
        ],
        'missing': [],
        'conflicts': [],
        'review_required': [],
      });
      expect(() => AiMappingResponse.fromJsonString(raw), throwsA(isA<AiMappingFormatException>()));
    });

    test('rejects a mapping entry with confidence out of [0, 1] range', () {
      final raw = jsonEncode({
        'mappings': [
          {'portal_field': 'X', 'value': 'Y', 'confidence': 1.5, 'reason': 'r'},
        ],
        'missing': [],
        'conflicts': [],
        'review_required': [],
      });
      expect(() => AiMappingResponse.fromJsonString(raw), throwsA(isA<AiMappingFormatException>()));
    });

    test('rejects a mapping entry missing portal_field', () {
      final raw = jsonEncode({
        'mappings': [
          {'value': 'Y', 'confidence': 0.9, 'reason': 'r'},
        ],
        'missing': [],
        'conflicts': [],
        'review_required': [],
      });
      expect(() => AiMappingResponse.fromJsonString(raw), throwsA(isA<AiMappingFormatException>()));
    });

    test('AiMappingResponse.failure marks the response as not succeeded, with no mappings', () {
      const response = AiMappingResponse.failure('AI provider unavailable');
      expect(response.succeeded, isFalse);
      expect(response.mappings, isEmpty);
      expect(response.providerError, 'AI provider unavailable');
    });
  });
}
