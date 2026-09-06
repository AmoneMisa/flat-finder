from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


# Cancellation primitive shared by the transport and feature layers.
cancellation_path = Path('app/lib/services/request_cancellation.dart')
if cancellation_path.exists():
    raise SystemExit('request_cancellation.dart already exists')
cancellation_path.write_text("""import 'dart:async';

/// Cooperative cancellation for long-lived request workflows such as
/// translation submit + polling. It cannot retroactively abort a top-level
/// `http.get`, but it interrupts waits immediately and prevents any subsequent
/// poll after the owning UI has gone away.
class RequestCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const RequestCancelledException();
  }
}

class RequestCancelledException implements Exception {
  const RequestCancelledException();

  @override
  String toString() => 'Request cancelled';
}

Future<void> waitForDelayOrCancellation(
  Duration duration,
  RequestCancellation? cancellation,
) async {
  if (cancellation == null) {
    await Future<void>.delayed(duration);
    return;
  }
  cancellation.throwIfCancelled();
  await Future.any<void>([
    Future<void>.delayed(duration),
    cancellation.whenCancelled,
  ]);
  cancellation.throwIfCancelled();
}
""")

base_path = Path('app/lib/services/api_service_base.dart')
base = base_path.read_text()
base = replace_once(
    base,
    "import '../models/search_statistics.dart';\n",
    "import '../models/search_statistics.dart';\nimport 'request_cancellation.dart';\n",
    'base cancellation import',
)
base = replace_once(
    base,
    """  Future<String> translateText(
    String text, {
    required String targetLanguage,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return '';

    var job = await _startTranslation(normalized, targetLanguage);
""",
    """  Future<String> translateText(
    String text, {
    required String targetLanguage,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 2),
    RequestCancellation? cancellation,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return '';
    cancellation?.throwIfCancelled();

    var job = await _startTranslation(normalized, targetLanguage);
    cancellation?.throwIfCancelled();
""",
    'translation signature and start cancellation',
)
base = replace_once(
    base,
    """    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        job = await _translationResult(key);
        consecutivePollErrors = 0;
      } catch (_) {
""",
    """    while (DateTime.now().isBefore(deadline)) {
      await waitForDelayOrCancellation(pollInterval, cancellation);
      try {
        cancellation?.throwIfCancelled();
        job = await _translationResult(key);
        cancellation?.throwIfCancelled();
        consecutivePollErrors = 0;
      } on RequestCancelledException {
        rethrow;
      } catch (_) {
""",
    'cancellable poll loop',
)
base = replace_once(
    base,
    """  Future<Map<String, double>> fetchRates() async {
    final res = await http.get(Uri.parse('$baseUrl/api/rates'));
""",
    """  Future<Map<String, double>> fetchRates() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/rates'))
        .timeout(const Duration(seconds: 15));
""",
    'rates timeout',
)
base_path.write_text(base)

state_path = Path('app/lib/state/app_state.dart')
state = state_path.read_text()
state = replace_once(
    state,
    "import '../services/api_service.dart';\n",
    "import '../services/api_service.dart';\nimport '../services/request_cancellation.dart';\n",
    'AppState cancellation import',
)
state = replace_once(
    state,
    """  Future<String> translateText(String text, {required String targetLanguage}) {
    return _api.translateText(text, targetLanguage: targetLanguage);
  }
""",
    """  Future<String> translateText(
    String text, {
    required String targetLanguage,
    RequestCancellation? cancellation,
  }) {
    return _api.translateText(
      text,
      targetLanguage: targetLanguage,
      cancellation: cancellation,
    );
  }
""",
    'AppState translation forwarding',
)
state_path.write_text(state)

detail_path = Path('app/lib/screens/listing_detail.dart')
detail = detail_path.read_text()
detail = replace_once(
    detail,
    "import '../services/api_service.dart';\n",
    "import '../services/api_service.dart';\nimport '../services/request_cancellation.dart';\n",
    'detail cancellation import',
)
detail = replace_once(
    detail,
    """class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _shareKey = GlobalKey();
""",
    """class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _shareKey = GlobalKey();
  final RequestCancellation _translationCancellation = RequestCancellation();
""",
    'detail cancellation field',
)
detail = replace_once(
    detail,
    """  /// Background OLX re-check on open, mirroring the web's
""",
    """  @override
  void dispose() {
    _translationCancellation.cancel();
    super.dispose();
  }

  /// Background OLX re-check on open, mirroring the web's
""",
    'detail dispose cancellation',
)
detail = replace_once(
    detail,
    """      final translated = await context.read<AppState>().translateText(
            sourceText,
            targetLanguage: lang,
          );
""",
    """      final translated = await context.read<AppState>().translateText(
            sourceText,
            targetLanguage: lang,
            cancellation: _translationCancellation,
          );
""",
    'detail passes cancellation',
)
detail = replace_once(
    detail,
    """    } catch (_) {
      _snack(
        _localized(
          settings,
          'Could not translate the listing. Try again.',
          'Не удалось перевести объявление. Попробуйте ещё раз.',
        ),
      );
""",
    """    } on RequestCancelledException {
      // Closing the detail page deliberately ends its polling workflow.
      return;
    } catch (_) {
      _snack(
        _localized(
          settings,
          'Could not translate the listing. Try again.',
          'Не удалось перевести объявление. Попробуйте ещё раз.',
        ),
      );
""",
    'detail silent cancellation',
)
detail_path.write_text(detail)

# VM-level regression: cancellation interrupts the poll delay and prevents any
# later GETs even though the server continues returning `pending` forever.
test_path = Path('app/test/translation_cancellation_test.dart')
if test_path.exists():
    raise SystemExit('translation_cancellation_test.dart already exists')
test_path.write_text("""import 'dart:convert';
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
""")
