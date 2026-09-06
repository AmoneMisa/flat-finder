import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ApiService sends multi-metro radius and directional arc to backend',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestSeen = Completer<HttpRequest>();
    server.listen((request) async {
      if (!requestSeen.isCompleted) requestSeen.complete(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'count': 0,
        'listings': <Object>[],
        'degradedCountries': <Object>[],
        'sourceErrors': <Object>[],
        'nextCursor': null,
      }));
      await request.response.close();
    });

    try {
      final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
      final filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        district: 'Chilanzar',
        metro: {'Novza', 'Chilonzor'},
        metroMaxM: 780,
        metroBearingFrom: 340,
        metroBearingTo: 20,
      );

      await api.fetchListings(filters);
      final request = await requestSeen.future.timeout(const Duration(seconds: 2));
      final query = request.uri.queryParameters;

      expect(request.uri.path, '/api/mobile/listings');
      expect(query['district'], 'Chilanzar');
      expect(query['metro']!.split(',').toSet(), {'Novza', 'Chilonzor'});
      expect(query['metroMaxM'], '780');
      expect(query['metroArc'], '340,20');
    } finally {
      await server.close(force: true);
    }
  });
}
