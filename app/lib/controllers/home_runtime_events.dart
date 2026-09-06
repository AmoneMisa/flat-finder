import 'dart:async';

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
