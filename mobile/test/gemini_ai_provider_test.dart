// Tests for [GeminiProvider] -- the concrete AI Provider implementation.
//
// These exercise the two HTTP call paths (backend-proxy and direct-to-Gemini)
// using `package:http/testing.dart`'s [MockClient], which ships inside the
// `http` package itself (already a declared dependency), so no mocking
// framework or extra dev dependency is needed.
//
// Covers master-spec required test scenario #13 ("Backend unavailable"),
// which was not exercised by `ai_mapping_service_test.dart` (that file tests
// the *orchestrator's* handling of "provider unavailable" via a hand-written
// fake provider, never the real [GeminiProvider] HTTP code paths).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setumitra/models/ai_mapping_models.dart';
import 'package:setumitra/services/ai_provider.dart';
import 'package:setumitra/services/ai_provider_config_service.dart';
import 'package:setumitra/services/gemini_ai_provider.dart';

AiMappingRequest _requestWithOneField() => const AiMappingRequest(
      portalName: 'Shramsetu',
      serviceName: 'Contract Labour Registration',
      fields: [
        AiMappingRequestField(
          portalField: AiPortalFieldDescriptor(name: 'EstablishmentName', type: 'text'),
        ),
      ],
      sourceCandidates: {'establishment_name': 'ABC INDUSTRIES PVT LTD'},
    );

void main() {
  group('GeminiProvider.mapFields -- backend-proxy path (scenario #13: backend unavailable)', () {
    test('backend unreachable (network throws) returns a failure response, never a thrown exception', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection refused');
      });
      final config = AiProviderConfigService();
      await config.setBackendUrl('https://backend.example.invalid');
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isFalse);
      expect(response.mappings, isEmpty);
      expect(response.providerError, isNotNull);
    });

    test('backend responds with a non-200 status returns a failure response, never a thrown exception', () async {
      final mockClient = MockClient((request) async => http.Response('Service Unavailable', 503));
      final config = AiProviderConfigService();
      await config.setBackendUrl('https://backend.example.invalid');
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isFalse);
      expect(response.providerError, contains('503'));
    });

    test('backend responds with malformed JSON returns a failure response (never a half-trusted mapping)', () async {
      final mockClient = MockClient((request) async => http.Response('not json at all', 200));
      final config = AiProviderConfigService();
      await config.setBackendUrl('https://backend.example.invalid');
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isFalse);
      expect(response.mappings, isEmpty);
    });

    test('backend responds with a well-formed mapping succeeds and parses it', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'https://backend.example.invalid/ai-autofill/map');
        return http.Response(
          jsonEncode({
            'mappings': [
              {
                'portal_field': 'EstablishmentName',
                'source_field': 'establishment_name',
                'value': 'ABC INDUSTRIES PVT LTD',
                'confidence': 0.98,
                'reason': 'Exact semantic match',
              },
            ],
            'missing': [],
            'conflicts': [],
            'review_required': [],
          }),
          200,
        );
      });
      final config = AiProviderConfigService();
      await config.setBackendUrl('https://backend.example.invalid');
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isTrue);
      expect(response.mappings, hasLength(1));
      expect(response.mappings.first.value, 'ABC INDUSTRIES PVT LTD');
      expect(response.mappings.first.status, MappingStatus.matched);
    });

    test('testConnection() surfaces backend unavailability as AiProviderUnavailableException', () async {
      final mockClient = MockClient((request) async => http.Response('down', 502));
      final config = AiProviderConfigService();
      await config.setBackendUrl('https://backend.example.invalid');
      final provider = GeminiProvider(config, httpClient: mockClient);

      expect(provider.testConnection(), throwsA(isA<AiProviderUnavailableException>()));
    });
  });

  group('GeminiProvider.mapFields -- direct-to-Gemini path (no backend configured)', () {
    test('no API key and no backend configured returns a failure response without any HTTP call', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response('should not be called', 200);
      });
      final config = AiProviderConfigService();
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isFalse);
      expect(callCount, 0);
    });

    test('direct Gemini call with a configured API key parses the envelope and extracts the JSON text', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'generativelanguage.googleapis.com');
        expect(request.headers['x-goog-api-key'], 'test-api-key');
        final innerJson = jsonEncode({
          'mappings': [
            {
              'portal_field': 'EstablishmentName',
              'value': 'ABC INDUSTRIES PVT LTD',
              'confidence': 0.96,
              'reason': 'Matched',
            },
          ],
          'missing': [],
          'conflicts': [],
          'review_required': [],
        });
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': innerJson},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final config = AiProviderConfigService();
      await config.setApiKey(AiProviderId.gemini, 'test-api-key');
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isTrue);
      expect(response.mappings.single.value, 'ABC INDUSTRIES PVT LTD');
    });

    test('direct Gemini call with an unparseable envelope returns a failure response', () async {
      final mockClient = MockClient((request) async => http.Response(jsonEncode({'candidates': []}), 200));
      final config = AiProviderConfigService();
      await config.setApiKey(AiProviderId.gemini, 'test-api-key');
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isFalse);
    });

    test('a non-2xx Gemini response is reported as a failure, never thrown', () async {
      final mockClient = MockClient((request) async => http.Response('quota exceeded', 429));
      final config = AiProviderConfigService();
      await config.setApiKey(AiProviderId.gemini, 'test-api-key');
      final provider = GeminiProvider(config, httpClient: mockClient);

      final response = await provider.mapFields(_requestWithOneField());

      expect(response.succeeded, isFalse);
      expect(response.providerError, contains('429'));
    });
  });

  group('GeminiProvider.mapFields -- sensitive-field guard (defense in depth)', () {
    test('refuses to send a sensitive field, failing before any HTTP call is made', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response('should not be called', 200);
      });
      final config = AiProviderConfigService();
      await config.setApiKey(AiProviderId.gemini, 'test-api-key');
      final provider = GeminiProvider(config, httpClient: mockClient);

      const sensitiveRequest = AiMappingRequest(
        portalName: 'Shramsetu',
        serviceName: 'Login',
        fields: [
          AiMappingRequestField(
            portalField: AiPortalFieldDescriptor(name: 'otp', type: 'text'),
          ),
        ],
      );

      final response = await provider.mapFields(sensitiveRequest);

      expect(response.succeeded, isFalse);
      expect(callCount, 0);
    });
  });

  group('GeminiProvider.mapFields -- empty request', () {
    test('an empty field list succeeds trivially without any HTTP call', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response('should not be called', 200);
      });
      final config = AiProviderConfigService();
      await config.setApiKey(AiProviderId.gemini, 'test-api-key');
      final provider = GeminiProvider(config, httpClient: mockClient);

      const emptyRequest = AiMappingRequest(portalName: 'Shramsetu', serviceName: 'X', fields: []);
      final response = await provider.mapFields(emptyRequest);

      expect(response.succeeded, isTrue);
      expect(response.mappings, isEmpty);
      expect(callCount, 0);
    });
  });
}
