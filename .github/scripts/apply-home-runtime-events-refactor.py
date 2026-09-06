from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)

controller = Path('app/lib/controllers/home_runtime_events.dart')
controller.parent.mkdir(parents=True, exist_ok=True)
controller.write_text("""import 'dart:async';

import 'package:app_links/app_links.dart';

import '../services/push_service.dart';

/// Owns HomeScreen's external event subscriptions without owning navigation UI.
///
/// The screen still decides what a link/push means; this object only manages
/// lifecycle, initial-link delivery and stream cancellation. Keeping these
/// concerns outside the widget makes rebuilds independent from platform event
/// wiring and gives the lifecycle behavior a small unit-testable surface.
class HomeRuntimeEvents {
  HomeRuntimeEvents({
    required Future<Uri?> Function() loadInitialLink,
    required Stream<Uri> links,
    required Stream<int> listingOpens,
    required Stream<ForegroundPush> foregroundPushes,
    required void Function(Uri) onLink,
    required void Function(int) onListingOpen,
    required void Function(ForegroundPush) onForegroundPush,
  })  : _loadInitialLink = loadInitialLink,
        _links = links,
        _listingOpens = listingOpens,
        _foregroundPushes = foregroundPushes,
        _onLink = onLink,
        _onListingOpen = onListingOpen,
        _onForegroundPush = onForegroundPush;

  factory HomeRuntimeEvents.production({
    required void Function(Uri) onLink,
    required void Function(int) onListingOpen,
    required void Function(ForegroundPush) onForegroundPush,
  }) {
    final appLinks = AppLinks();
    final push = PushService.instance;
    return HomeRuntimeEvents(
      loadInitialLink: appLinks.getInitialLink,
      links: appLinks.uriLinkStream,
      listingOpens: push.listingOpens,
      foregroundPushes: push.foregroundPushes,
      onLink: onLink,
      onListingOpen: onListingOpen,
      onForegroundPush: onForegroundPush,
    );
  }

  final Future<Uri?> Function() _loadInitialLink;
  final Stream<Uri> _links;
  final Stream<int> _listingOpens;
  final Stream<ForegroundPush> _foregroundPushes;
  final void Function(Uri) _onLink;
  final void Function(int) _onListingOpen;
  final void Function(ForegroundPush) _onForegroundPush;

  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<int>? _listingSub;
  StreamSubscription<ForegroundPush>? _foregroundSub;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;

    // Subscribe before awaiting the cold-start link so a link delivered while
    // the platform call is pending cannot fall into a startup gap.
    _linkSub = _links.listen(_onLink, onError: (_) {});
    _listingSub = _listingOpens.listen(_onListingOpen, onError: (_) {});
    _foregroundSub =
        _foregroundPushes.listen(_onForegroundPush, onError: (_) {});
    unawaited(_deliverInitialLink());
  }

  Future<void> _deliverInitialLink() async {
    try {
      final initial = await _loadInitialLink();
      if (!_disposed && initial != null) _onLink(initial);
    } catch (_) {
      // Deep links are best-effort on platforms/providers without support.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_linkSub?.cancel());
    unawaited(_listingSub?.cancel());
    unawaited(_foregroundSub?.cancel());
  }
}
""", encoding='utf-8')

test = Path('app/test/home_runtime_events_test.dart')
test.write_text("""import 'dart:async';

import 'package:flat_finder/controllers/home_runtime_events.dart';
import 'package:flat_finder/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live events are subscribed before a slow initial-link lookup resolves',
      () async {
    final initial = Completer<Uri?>();
    final links = StreamController<Uri>.broadcast();
    final listings = StreamController<int>.broadcast();
    final pushes = StreamController<ForegroundPush>.broadcast();
    final seenLinks = <Uri>[];
    final seenListings = <int>[];
    final seenPushes = <ForegroundPush>[];

    final events = HomeRuntimeEvents(
      loadInitialLink: () => initial.future,
      links: links.stream,
      listingOpens: listings.stream,
      foregroundPushes: pushes.stream,
      onLink: seenLinks.add,
      onListingOpen: seenListings.add,
      onForegroundPush: seenPushes.add,
    );
    events.start();

    final live = Uri.parse('flatfinder://search?city=Tashkent');
    links.add(live);
    listings.add(42);
    pushes.add(const ForegroundPush(title: 'New', body: null, publicId: 42));
    await Future<void>.delayed(Duration.zero);

    expect(seenLinks, [live]);
    expect(seenListings, [42]);
    expect(seenPushes.single.publicId, 42);

    final cold = Uri.parse('flatfinder://listing?id=7');
    initial.complete(cold);
    await Future<void>.delayed(Duration.zero);
    expect(seenLinks, [live, cold]);

    events.dispose();
    await links.close();
    await listings.close();
    await pushes.close();
  });

  test('dispose suppresses a late cold-start link and cancels streams', () async {
    final initial = Completer<Uri?>();
    final links = StreamController<Uri>.broadcast();
    final listings = StreamController<int>.broadcast();
    final pushes = StreamController<ForegroundPush>.broadcast();
    var calls = 0;

    final events = HomeRuntimeEvents(
      loadInitialLink: () => initial.future,
      links: links.stream,
      listingOpens: listings.stream,
      foregroundPushes: pushes.stream,
      onLink: (_) => calls++,
      onListingOpen: (_) => calls++,
      onForegroundPush: (_) => calls++,
    )..start();

    events.dispose();
    initial.complete(Uri.parse('flatfinder://listing?id=9'));
    links.add(Uri.parse('flatfinder://search?city=Odesa'));
    listings.add(9);
    pushes.add(const ForegroundPush(title: null, body: null, publicId: 9));
    await Future<void>.delayed(Duration.zero);

    expect(calls, 0);
    await links.close();
    await listings.close();
    await pushes.close();
  });
}
""", encoding='utf-8')

path = Path('app/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(text, "import 'dart:async';\n\n", '', 'remove home async import')
text = replace_once(text, "import 'package:app_links/app_links.dart';\n", '', 'remove app links import')
text = replace_once(
    text,
    "import '../l10n/review_strings.dart';\n",
    "import '../controllers/home_runtime_events.dart';\nimport '../l10n/review_strings.dart';\n",
    'home runtime controller import',
)
text = replace_once(text, "import '../services/push_service.dart';\n", '', 'remove push service import')
text = replace_once(
    text,
    """  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<int>? _pushListingSub;
  StreamSubscription<ForegroundPush>? _foregroundPushSub;
  final ScrollController _resultsScroll = ScrollController();
""",
    """  late final HomeRuntimeEvents _runtimeEvents;
  final ScrollController _resultsScroll = ScrollController();
""",
    'replace home event subscription fields',
)
text = replace_once(
    text,
    """    _initDeepLinks();
    _pushListingSub = PushService.instance.listingOpens.listen(
      _openSharedListing,
    );
    _foregroundPushSub = PushService.instance.foregroundPushes.listen(
      _showForegroundPush,
    );
""",
    """    _runtimeEvents = HomeRuntimeEvents.production(
      onLink: _applyLink,
      onListingOpen: _openSharedListing,
      onForegroundPush: _showForegroundPush,
    )..start();
""",
    'home runtime startup',
)
text = replace_once(
    text,
    """    _linkSub?.cancel();
    _pushListingSub?.cancel();
    _foregroundPushSub?.cancel();
""",
    """    _runtimeEvents.dispose();
""",
    'home runtime disposal',
)
start = text.find("  /// Listen for `flatfinder://search?…` deep links")
end = text.find("  void _applyLink(Uri uri) {", start)
if start < 0 or end < 0:
    raise SystemExit('deep-link bootstrap method block not found')
text = text[:start] + text[end:]
if 'AppLinks' in text or 'StreamSubscription<' in text or '_initDeepLinks' in text:
    raise SystemExit('HomeScreen still owns external subscription plumbing')
path.write_text(text, encoding='utf-8')
