from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


base_path = Path('app/lib/services/api_service_base.dart')
base = base_path.read_text()
base = replace_once(
    base,
    """class ApiService {
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  final String baseUrl;
  Future<SearchStatistics?>? _statisticsSnapshotRequest;
  final Set<http.Client> _listingClients = <http.Client>{};
""",
    """class ApiService {
  ApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _defaultBaseUrl(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  Future<SearchStatistics?>? _statisticsSnapshotRequest;
  final Set<http.Client> _listingClients = <http.Client>{};

  /// Reused by ordinary metadata/detail/statistics requests. Listing pages keep
  /// dedicated clients because closing those clients is how a superseded
  /// cursor request is actively aborted.
  @protected
  http.Client get transportClient => _client;
""",
    'base constructor/shared client',
)

pattern = re.compile(r'\bhttp\s*\.\s*(get|post|put)\(')
matches = pattern.findall(base)
if len(matches) != 12:
    raise SystemExit(f'base top-level http calls: expected 12, got {len(matches)}: {matches}')
base = pattern.sub(lambda m: f'_client.{m.group(1)}(', base)

base = replace_once(
    base,
    """  void cancelListingRequests() {
    final clients = _listingClients.toList(growable: false);
    _listingClients.clear();
    for (final client in clients) {
      client.close();
    }
  }
""",
    """  void cancelListingRequests() {
    final clients = _listingClients.toList(growable: false);
    _listingClients.clear();
    for (final client in clients) {
      client.close();
    }
  }

  /// Closes transport resources owned by this service. An injected client is
  /// caller-owned and deliberately remains open; the app's Provider constructs
  /// the default owned client and disposes the service with the widget tree.
  void dispose() {
    cancelListingRequests();
    if (_ownsClient) _client.close();
  }
""",
    'base dispose',
)
base_path.write_text(base)

facade_path = Path('app/lib/services/api_service.dart')
facade = facade_path.read_text()
facade = replace_once(
    facade,
    "import 'package:http/http.dart' as http;\n",
    '',
    'remove facade http import',
)
facade = replace_once(
    facade,
    """class ApiService extends base.ApiService {
  ApiService({String? baseUrl}) : super(baseUrl: baseUrl);
""",
    """class ApiService extends base.ApiService {
  ApiService({super.baseUrl, super.client});
""",
    'facade super constructor',
)
facade_pattern = re.compile(r'\bhttp\s*\.\s*(get|post)\(')
facade_matches = facade_pattern.findall(facade)
if len(facade_matches) != 2:
    raise SystemExit(
        f'facade top-level http calls: expected 2, got {len(facade_matches)}: {facade_matches}'
    )
facade = facade_pattern.sub(lambda m: f'transportClient.{m.group(1)}(', facade)
facade_path.write_text(facade)

main_path = Path('app/lib/main.dart')
main = main_path.read_text()
main = replace_once(
    main,
    """        Provider<ApiService>(create: (_) => ApiService()),
""",
    """        Provider<ApiService>(
          create: (_) => ApiService(),
          dispose: (_, api) => api.dispose(),
        ),
""",
    'provider disposes api',
)
main_path.write_text(main)

# Prove one injected client is used across a base-layer endpoint and the public
# facade's own translation endpoint.
test_path = Path('app/test/api_service_client_test.dart')
if test_path.exists():
    raise SystemExit('api_service_client_test.dart already exists')
test_path.write_text("""import 'dart:convert';

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
    expect(paths, ['/api/rates', '/api/translation']);
  });
}
""")
