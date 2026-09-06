import 'dart:convert';

import 'package:flat_finder/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('one injected client serves base and facade requests', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/api/rates') {
        return http.Response(
          jsonEncode({
            'rates': {'USD': 1.0, 'EUR': 0.9},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/translation') {
        return http.Response(
          jsonEncode({
            'status': 'completed',
            'data': {'translatedText': 'Translated'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
    final api = ApiService(baseUrl: 'https://example.test', client: client);

    addTearDown(() {
      api.dispose();
      client.close();
    });

    final rates = await api.fetchRates();
    final translated = await api.translateText(
      'Original',
      targetLanguage: 'en',
    );

    expect(rates['EUR'], 0.9);
    expect(translated, 'Translated');
    expect(paths, hasLength(2));
    expect(paths, ['/api/rates', '/api/translation']);
  });
}
