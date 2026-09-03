import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/filters.dart';
import '../lib/services/api_service.dart';

const _etag = 'W/"stats-1756900000000"';

Map<String, dynamic> _snapshotBody({int total = 2}) => {
      'statistics': {
        'total': total,
        'currency': 'USD',
        'dealTypes': [
          {'key': 'longRent', 'count': total, 'medianUsd': 500},
        ],
        'geographies': {
          'city': [
            {'label': 'Tashkent', 'count': total},
          ],
        },
      },
      'generatedAt': '2026-09-03T12:00:00.000Z',
      'maxAgeDays': 14,
    };

class _StatsApi extends ApiService {
  _StatsApi(this.responder) : super(baseUrl: 'http://test.invalid');

  final http.Response Function(Map<String, String> headers) responder;
  final List<Map<String, String>> requests = <Map<String, String>>[];

  @override
  Future<http.Response> sendStatisticsRequest(
    Uri uri,
    Map<String, String> headers,
  ) async {
    requests.add(headers);
    return responder(headers);
  }
}

class _OfflineStatsApi extends ApiService {
  _OfflineStatsApi() : super(baseUrl: 'http://test.invalid');

  int calls = 0;

  @override
  Future<http.Response> sendStatisticsRequest(
    Uri uri,
    Map<String, String> headers,
  ) async {
    calls++;
    throw Exception('network down');
  }
}

void main() {
  final filters = Filters();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('first fetch stores the snapshot and its ETag', () async {
    final api = _StatsApi(
      (_) => http.Response(
        jsonEncode(_snapshotBody()),
        200,
        headers: const {'etag': _etag},
      ),
    );

    final stats = await api.fetchSearchStatistics(filters);
    expect(stats, isNotNull);
    expect(stats!.total, 2);
    expect(api.requests.single.containsKey('If-None-Match'), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('statistics.snapshot.etag'), _etag);
    expect(prefs.getString('statistics.snapshot.payload'), isNotNull);
  });

  test('a later launch revalidates and renders the stored copy on 304',
      () async {
    final seed = _StatsApi(
      (_) => http.Response(
        jsonEncode(_snapshotBody(total: 7)),
        200,
        headers: const {'etag': _etag},
      ),
    );
    await seed.fetchSearchStatistics(filters);

    // A new ApiService is what a cold app start gets: no in-memory future.
    final revalidating = _StatsApi((_) => http.Response('', 304));
    final stats = await revalidating.fetchSearchStatistics(filters);

    expect(revalidating.requests.single['If-None-Match'], _etag);
    expect(stats, isNotNull, reason: '304 must resolve from the stored copy');
    expect(stats!.total, 7);
  });

  test('the stored copy still answers when the request fails', () async {
    final seed = _StatsApi(
      (_) => http.Response(
        jsonEncode(_snapshotBody(total: 5)),
        200,
        headers: const {'etag': _etag},
      ),
    );
    await seed.fetchSearchStatistics(filters);

    final offline = _OfflineStatsApi();
    final stats = await offline.fetchSearchStatistics(filters);

    expect(offline.calls, 1);
    expect(stats?.total, 5);
  });

  test('no stored copy and a failed request stays null', () async {
    final offline = _OfflineStatsApi();
    expect(await offline.fetchSearchStatistics(filters), isNull);
  });

  test('a snapshot served from cache after a failure is retried later',
      () async {
    final seed = _StatsApi(
      (_) => http.Response(
        jsonEncode(_snapshotBody(total: 3)),
        200,
        headers: const {'etag': _etag},
      ),
    );
    await seed.fetchSearchStatistics(filters);

    final offline = _OfflineStatsApi();
    expect((await offline.fetchSearchStatistics(filters))?.total, 3);
    // Serving the stored copy must not pin it for the rest of the session.
    expect((await offline.fetchSearchStatistics(filters))?.total, 3);
    expect(offline.calls, 2);
  });

  test('a 304 does not count as stale and is answered once per session',
      () async {
    final seed = _StatsApi(
      (_) => http.Response(
        jsonEncode(_snapshotBody(total: 9)),
        200,
        headers: const {'etag': _etag},
      ),
    );
    await seed.fetchSearchStatistics(filters);

    final revalidating = _StatsApi((_) => http.Response('', 304));
    expect((await revalidating.fetchSearchStatistics(filters))?.total, 9);
    expect((await revalidating.fetchSearchStatistics(filters))?.total, 9);
    expect(revalidating.requests.length, 1);
  });
}
