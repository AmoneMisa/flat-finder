import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/services/installation_identity.dart';
import 'package:flat_finder/services/update_service.dart';
import 'package:flat_finder/state/presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SyncCall {
  const _SyncCall({required this.enabled, required this.language});
  final bool enabled;
  final String language;
}

class _ControlledSubscriptionApi extends ApiService {
  _ControlledSubscriptionApi() : super(baseUrl: 'http://test.invalid');

  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  final calls = <_SyncCall>[];

  @override
  Future<void> syncMobileSubscriptions({
    required String deviceId,
    required String pushToken,
    required bool enabled,
    required String platform,
    required String language,
    required List<Map<String, dynamic>> presets,
  }) async {
    calls.add(_SyncCall(enabled: enabled, language: language));
    if (calls.length == 1) {
      if (!firstStarted.isCompleted) firstStarted.complete();
      await releaseFirst.future;
    }
  }
}

class _MemorySecretStore implements InstallationSecretStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('cold-start countries request prefetches the first feed concurrently',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final listingSeen = Completer<void>();
    final releaseCountries = Completer<void>();
    var listingRequests = 0;

    server.listen((request) async {
      try {
        if (request.uri.path == '/api/countries') {
          await releaseCountries.future;
          request.response.headers.contentType = ContentType.json;
          request.response.write('[]');
        } else if (request.uri.path == '/api/mobile/listings') {
          listingRequests += 1;
          if (!listingSeen.isCompleted) listingSeen.complete();
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'count': 1,
            'listings': [
              {
                'id': 'startup-1',
                'source': 'olx',
                'country': 'RO',
                'title': 'Startup listing',
                'propertyType': 'flat',
                'currency': 'EUR',
                'city': 'Bucharest',
                'url': 'javascript:alert(1)',
                'description': '',
                'tags': <String>[],
              }
            ],
            'degradedCountries': <Object>[],
            'sourceErrors': <Object>[],
            'nextCursor': null,
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
      } finally {
        await request.response.close();
      }
    });

    try {
      final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
      final countriesFuture = api.fetchCountries();

      await listingSeen.future.timeout(const Duration(seconds: 2));
      expect(listingRequests, 1);
      releaseCountries.complete();
      expect(await countriesFuture, isEmpty);

      final result = await api.fetchListings(Filters());
      expect(listingRequests, 1, reason: 'the prefetched page must be reused');
      expect(result.listings.single.id, 'startup-1');
      expect(
        result.listings.single.url,
        isEmpty,
        reason: 'non-http(s) scraped URLs must not reach launchUrl',
      );
    } finally {
      if (!releaseCountries.isCompleted) releaseCountries.complete();
      await server.close(force: true);
    }
  });

  test('update APK URL is restricted to whiteslove.me release files', () {
    expect(
      UpdateService.isTrustedApkUrl(
        'https://whiteslove.me/files/FlatFinder_v1.0.0_WhitesLove.apk',
      ),
      isTrue,
    );
    expect(
      UpdateService.isTrustedApkUrl('https://evil.example/files/app.apk'),
      isFalse,
    );
    expect(
      UpdateService.isTrustedApkUrl(
        'https://whiteslove.me.evil.example/files/app.apk',
      ),
      isFalse,
    );
    expect(
      UpdateService.isTrustedApkUrl('javascript:alert(1)'),
      isFalse,
    );
    expect(
      UpdateService.isTrustedApkUrl('https://whiteslove.me/other/app.apk'),
      isFalse,
    );
  });

  test('push sync queues a newer snapshot instead of dropping it', () async {
    SharedPreferences.setMockInitialValues({'lang': 'ru'});
    final api = _ControlledSubscriptionApi();
    final identity = InstallationIdentity(secretStore: _MemorySecretStore());
    final state = PresetsState(api, identity: identity);

    state.pushMasterEnabled = false;
    final first = state.syncPushSubscriptions();
    await api.firstStarted.future.timeout(const Duration(seconds: 2));

    state.pushMasterEnabled = true;
    final second = state.syncPushSubscriptions();
    api.releaseFirst.complete();

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(api.calls, hasLength(2));
    expect(api.calls.first.enabled, isFalse);
    expect(api.calls.last.enabled, isTrue);
    expect(api.calls.last.language, 'ru');
  });
}
