from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


api_path = Path('app/lib/services/api_service.dart')
text = api_path.read_text()
text = replace_once(
    text,
    "import '../models/map_listing_point.dart';\n",
    "import '../models/map_listing_point.dart';\nimport 'request_cancellation.dart';\n",
    'cancellation import',
)
text = replace_once(
    text,
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
    Duration pollInterval = const Duration(seconds: 1),
    RequestCancellation? cancellation,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return '';
    cancellation?.throwIfCancelled();

    var job = await _startTranslation(normalized, targetLanguage);
    cancellation?.throwIfCancelled();
""",
    'facade translation signature',
)
text = replace_once(
    text,
    """    var consecutivePollErrors = 0;
    var delay = const Duration(seconds: 1);
    const maxDelay = Duration(seconds: 10);

    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(delay < remaining ? delay : remaining);

      try {
        job = await _translationResult(key);
        consecutivePollErrors = 0;
      } catch (_) {
""",
    """    var consecutivePollErrors = 0;
    var delay = pollInterval;
    const maxDelay = Duration(seconds: 10);

    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await waitForDelayOrCancellation(
        delay < remaining ? delay : remaining,
        cancellation,
      );

      try {
        cancellation?.throwIfCancelled();
        job = await _translationResult(key);
        cancellation?.throwIfCancelled();
        consecutivePollErrors = 0;
      } on RequestCancelledException {
        rethrow;
      } catch (_) {
""",
    'facade cancellable backoff',
)
api_path.write_text(text)

# Test the public facade used by AppState/ListingDetail, not only the base layer.
test_path = Path('app/test/translation_cancellation_test.dart')
test = test_path.read_text()
test = replace_once(
    test,
    "import 'package:flat_finder/services/api_service_base.dart' as base;\n",
    "import 'package:flat_finder/services/api_service.dart';\n",
    'public api import',
)
test = test.replace('base.ApiService(', 'ApiService(')
if 'base.ApiService(' in test:
    raise SystemExit('base ApiService reference remains')
test_path.write_text(test)
