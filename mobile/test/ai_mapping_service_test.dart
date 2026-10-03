import 'package:flutter_test/flutter_test.dart';
import 'package:setumitra/models/ai_mapping_models.dart';
import 'package:setumitra/models/form_model.dart';
import 'package:setumitra/services/ai_mapping_service.dart';
import 'package:setumitra/services/ai_provider.dart';
import 'package:setumitra/services/ai_provider_config_service.dart';
import 'package:setumitra/services/database_service.dart';

import 'test_helpers/sqflite_ffi_setup.dart';

/// Hand-written fake provider (no mocking framework needed): lets tests
/// control exactly what "the AI" returns -- including unavailability and
/// a thrown error -- without any real network call, per
/// AiMappingService(providerOverride:)'s documented test seam.
class _FakeAiProvider implements AiProvider {
  _FakeAiProvider({this.configured = true, this.response, this.throwOnMapFields});

  final bool configured;
  final AiMappingResponse? response;
  final Object? throwOnMapFields;

  AiMappingRequest? lastRequest;

  @override
  AiProviderId get id => AiProviderId.gemini;

  @override
  String get displayName => 'Fake';

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<String> testConnection() async => 'ok';

  @override
  Future<AiMappingResponse> mapFields(AiMappingRequest request) async {
    lastRequest = request;
    if (throwOnMapFields != null) throw throwOnMapFields!;
    return response ?? const AiMappingResponse();
  }
}

AiPortalFieldDescriptor _field(
  String name, {
  String type = 'text',
  String? label,
  List<AiDropdownOption> options = const [],
}) {
  return AiPortalFieldDescriptor(name: name, type: type, label: label, options: options);
}

void main() {
  setUpAll(() {
    initSqfliteFfiForTests();
  });

  late AiProviderConfigService config;

  setUp(() {
    config = AiProviderConfigService();
  });

  group('AiMappingService -- deterministic + master data (no AI call needed)', () {
    test('resolves a field already known to the existing deterministic AutoFill (exact field mapping)', () async {
      final service = AiMappingService(configService: config);
      final formData = ShramsetuFormModel(fields: {'establishment_name': 'abc industries pvt ltd'});

      final response = await service.generateMappings(
        domFields: [_field('EstablishmentName', label: 'Name of Establishment')],
        formData: formData,
        serviceName: 'TEST_EXACT',
      );

      final m = response.mappings.singleWhere((x) => x.portalField == 'EstablishmentName');
      expect(m.sourceField, 'establishment_name');
      expect(m.value, 'ABC INDUSTRIES PVT LTD');
      expect(m.status, MappingStatus.matched);
      expect(m.mappingMethod, MappingMethod.deterministic);
    });

    test('Master Data priority: district resolves via GujaratMasterData even from Gujarati-script source data', () async {
      final service = AiMappingService(configService: config);
      final formData = ShramsetuFormModel(fields: {'district': 'અમદાવાદ'});

      final response = await service.generateMappings(
        domFields: [_field('DistrictID', label: 'District')],
        formData: formData,
        serviceName: 'TEST_MASTER_DATA',
      );

      final m = response.mappings.singleWhere((x) => x.portalField == 'DistrictID');
      expect(m.value, 'AHMEDABAD');
      expect(m.mappingMethod, MappingMethod.masterData);
      expect(m.status, MappingStatus.matched);
    });

    test('dropdown matching selects an existing live option value, never free text', () async {
      final service = AiMappingService(configService: config);
      final formData = ShramsetuFormModel(fields: {'district': 'બોટાદ'});

      final response = await service.generateMappings(
        domFields: [
          _field(
            'DistrictID',
            type: 'select',
            label: 'District',
            options: const [
              AiDropdownOption(value: '7', label: 'AHMEDABAD'),
              AiDropdownOption(value: '8', label: 'BOTAD'),
              AiDropdownOption(value: '9', label: 'AMRELI'),
            ],
          ),
        ],
        formData: formData,
        serviceName: 'TEST_DROPDOWN',
      );

      final m = response.mappings.singleWhere((x) => x.portalField == 'DistrictID');
      expect(m.value, '8');
      expect(m.status, MappingStatus.matched);
    });

    test('OTP and CAPTCHA fields are entirely excluded -- not mapped, not missing, not sent anywhere', () async {
      final service = AiMappingService(configService: config);
      final formData = ShramsetuFormModel(fields: {'registration_otp': '123456'});

      final response = await service.generateMappings(
        domFields: [_field('OTP', label: 'Enter OTP'), _field('captchaCode', label: 'Captcha')],
        formData: formData,
        serviceName: 'TEST_SENSITIVE',
      );

      expect(response.mappings, isEmpty);
      expect(response.missing, isEmpty);
      expect(response.conflicts, isEmpty);
    });
  });

  group('AiMappingService -- AI semantic mapping (fake provider)', () {
    test('AI disabled in settings: AI-eligible fields become missing, provider never called', () async {
      await config.setEnabled(false);
      final fakeProvider = _FakeAiProvider();
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {'principal_employer_name': 'XYZ COMPANY'});

      final response = await service.generateMappings(
        domFields: [_field('UnmappedPortalField')],
        formData: formData,
        serviceName: 'TEST_AI_DISABLED',
      );

      expect(response.missing, contains('UnmappedPortalField'));
      expect(fakeProvider.lastRequest, isNull);
    });

    test('AI provider unavailable: AI-only fields become missing, deterministic fields are unaffected', () async {
      await config.setEnabled(true);
      final fakeProvider = _FakeAiProvider(configured: false);
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {
        'establishment_name': 'abc industries',
        'principal_employer_name': 'XYZ COMPANY',
      });

      final response = await service.generateMappings(
        domFields: [_field('EstablishmentName'), _field('UnmappedPortalField')],
        formData: formData,
        serviceName: 'TEST_PROVIDER_UNAVAILABLE',
      );

      expect(response.mappings.any((m) => m.portalField == 'EstablishmentName'), isTrue);
      expect(response.missing, contains('UnmappedPortalField'));
    });

    test('semantic mapping: AI resolves a field the deterministic mapping does not know (synonym understanding)', () async {
      await config.setEnabled(true);
      final fakeProvider = _FakeAiProvider(
        response: const AiMappingResponse(
          mappings: [
            AiFieldMapping(
              portalField: 'NameOfUnit',
              sourceField: 'establishment_name',
              value: 'ABC INDUSTRIES',
              confidence: 0.96,
              reason: 'Synonym of "Establishment Name"',
              status: MappingStatus.matched,
            ),
          ],
        ),
      );
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {'establishment_name': 'abc industries'});

      final response = await service.generateMappings(
        domFields: [_field('NameOfUnit', label: 'Name of Unit')],
        formData: formData,
        serviceName: 'TEST_SYNONYM',
      );

      final m = response.mappings.singleWhere((x) => x.portalField == 'NameOfUnit');
      expect(m.value, 'ABC INDUSTRIES');
      expect(m.mappingMethod, MappingMethod.aiSemantic);
      expect(m.status, MappingStatus.matched);
      expect(fakeProvider.lastRequest, isNotNull);
      expect(fakeProvider.lastRequest!.sourceCandidates['establishment_name'], 'abc industries');
    });

    test('low confidence mapping is never eligible for automatic fill, even if the provider claims matched', () async {
      await config.setEnabled(true);
      final fakeProvider = _FakeAiProvider(
        response: const AiMappingResponse(
          mappings: [
            AiFieldMapping(
              portalField: 'SomeField',
              value: 'GUESS',
              confidence: 0.5,
              reason: 'low confidence guess',
              status: MappingStatus.matched,
            ),
          ],
        ),
      );
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {'x': 'y'});

      final response = await service.generateMappings(
        domFields: [_field('SomeField')],
        formData: formData,
        serviceName: 'TEST_LOW_CONFIDENCE',
      );

      final m = response.mappings.singleWhere((x) => x.portalField == 'SomeField');
      expect(m.status, isNot(MappingStatus.matched));
    });

    test('AI-proposed dropdown value not matching any real option is downgraded to review required', () async {
      await config.setEnabled(true);
      final fakeProvider = _FakeAiProvider(
        response: const AiMappingResponse(
          mappings: [
            AiFieldMapping(
              portalField: 'RiskCategory',
              value: 'SOMETHING NOT A REAL OPTION',
              confidence: 0.99,
              reason: 'AI guess',
              status: MappingStatus.matched,
            ),
          ],
        ),
      );
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {'x': 'y'});

      final response = await service.generateMappings(
        domFields: [
          _field(
            'RiskCategory',
            type: 'select',
            options: const [
              AiDropdownOption(value: '1', label: 'LOW'),
              AiDropdownOption(value: '2', label: 'MEDIUM'),
              AiDropdownOption(value: '3', label: 'HIGH'),
            ],
          ),
        ],
        formData: formData,
        serviceName: 'TEST_DROPDOWN_NO_MATCH',
      );

      final m = response.mappings.singleWhere((x) => x.portalField == 'RiskCategory');
      expect(m.status, MappingStatus.reviewRequired);
    });

    test('missing and conflicting fields reported by the AI are surfaced; unanswered fields are conservatively missing', () async {
      await config.setEnabled(true);
      final fakeProvider = _FakeAiProvider(
        response: const AiMappingResponse(missing: ['factory_registration'], conflicts: ['district']),
      );
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {'x': 'y'});

      final response = await service.generateMappings(
        domFields: [_field('FactoryRegNo'), _field('ConflictedField')],
        formData: formData,
        serviceName: 'TEST_MISSING_CONFLICT',
      );

      expect(response.missing, containsAll(['factory_registration', 'FactoryRegNo', 'ConflictedField']));
      expect(response.conflicts, contains('district'));
    });

    test('provider throwing is not swallowed into a false "success" (defense in depth, never silently trusted)', () async {
      await config.setEnabled(true);
      final fakeProvider = _FakeAiProvider(throwOnMapFields: Exception('network down'));
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {'x': 'y'});

      expect(
        () => service.generateMappings(
          domFields: [_field('UnmappedPortalField')],
          formData: formData,
          serviceName: 'TEST_PROVIDER_THROWS',
        ),
        throwsException,
      );
    });

    test('sensitive fields are never included in the request sent to the AI provider', () async {
      await config.setEnabled(true);
      final fakeProvider = _FakeAiProvider(response: const AiMappingResponse());
      final service = AiMappingService(configService: config, providerOverride: fakeProvider);
      final formData = ShramsetuFormModel(fields: {'x': 'y'});

      await service.generateMappings(
        domFields: [_field('UnmappedPortalField'), _field('OTP', label: 'OTP')],
        formData: formData,
        serviceName: 'TEST_SENSITIVE_EXCLUDED_FROM_AI',
      );

      final sentFieldNames = fakeProvider.lastRequest!.fields.map((f) => f.portalField.name);
      expect(sentFieldNames, isNot(contains('OTP')));
    });
  });

  group('AiMappingService -- audit trail', () {
    test('recordAudit writes one traceable row per mapping, with the user-confirmation outcome recorded', () async {
      final service = AiMappingService(configService: config);
      await service.recordAudit(
        mappings: const [
          AiFieldMapping(
            portalField: 'UniqueAuditTestField_12345',
            sourceField: 'establishment_name',
            value: 'ABC INDUSTRIES',
            confidence: 1.0,
            reason: 'test',
            status: MappingStatus.matched,
            mappingMethod: MappingMethod.deterministic,
          ),
        ],
        confirmedPortalFields: const {'UniqueAuditTestField_12345'},
        serviceName: 'TEST_AUDIT',
      );

      final trail = await DatabaseService.getAuditTrail();
      final match = trail.firstWhere(
        (row) => (row['details'] as String).contains('UniqueAuditTestField_12345'),
      );
      expect(match['action'], 'AI_AUTOFILL_FIELD_MAPPED');
      expect(match['details'], contains('"user_confirmed":true'));
      expect(match['details'], isNot(contains('password')));
      expect(match['details'], isNot(contains('otp')));
    });
  });
}
