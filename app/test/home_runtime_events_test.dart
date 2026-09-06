import 'dart:async';

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
