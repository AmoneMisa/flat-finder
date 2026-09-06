import 'dart:convert';
import 'dart:io';

import 'package:flat_finder/services/api_service_base.dart' as base;
import 'package:flat_finder/services/request_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translation cancellation stops subsequent polling', () async {
    var polls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' && request.uri.path == '/api/translation') {
        await utf8.decoder.bind(request).join();
        request.response.write(jsonEncode({'status': 'queued', 'key': 'job-1'}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/translation/job-1') {
        polls += 1;
        request.response.write(jsonEncode({'status': 'pending', 'key': 'job-1'}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'not found'}));
      }
      await request.response.close();
    });

    addTearDown(() async {
      await server.close(force: true);
      await serving.cancel();
    });

    final api = base.ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
    final cancellation = RequestCancellation();
    final future = api.translateText(
      'Apartment description',
      targetLanguage: 'en',
      timeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 10),
      cancellation: cancellation,
    );

    final pollDeadline = DateTime.now().add(const Duration(seconds: 1));
    while (polls < 2 && DateTime.now().isBefore(pollDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(polls, greaterThanOrEqualTo(2));

    cancellation.cancel();
    await expectLater(future, throwsA(isA<RequestCancelledException>()));
    final pollsAtCancel = polls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(polls, pollsAtCancel);
  });

  test('already-cancelled request never submits translation', () async {
    final cancellation = RequestCancellation()..cancel();
    final api = base.ApiService(baseUrl: 'http://127.0.0.1:1');

    await expectLater(
      api.translateText(
        'Apartment description',
        targetLanguage: 'en',
        cancellation: cancellation,
      ),
      throwsA(isA<RequestCancelledException>()),
    );
  });
}
