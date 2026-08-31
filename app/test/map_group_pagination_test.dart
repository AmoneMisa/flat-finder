import 'package:flat_finder/utils/map_group_pagination.dart';
import 'package:flat_finder/models/map_listing_point.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/state/app_state.dart';
import 'package:flat_finder/state/settings.dart';
import 'package:flat_finder/widgets/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

void main() {
  group('paginateMapGroup', () {
    test('keeps up to ten items on one page', () {
      final items = List.generate(10, (index) => index);
      final page = paginateMapGroup(items, pageIndex: 0);

      expect(page.items, items);
      expect(page.pageIndex, 0);
      expect(page.pageCount, 1);
      expect(page.hasPrevious, isFalse);
      expect(page.hasNext, isFalse);
    });

    test('splits dense groups into pages of ten', () {
      final items = List.generate(23, (index) => index);

      final first = paginateMapGroup(items, pageIndex: 0);
      final second = paginateMapGroup(items, pageIndex: 1);
      final third = paginateMapGroup(items, pageIndex: 2);

      expect(first.items, List.generate(10, (index) => index));
      expect(second.items, List.generate(10, (index) => index + 10));
      expect(third.items, [20, 21, 22]);
      expect(first.pageCount, 3);
      expect(second.hasPrevious, isTrue);
      expect(second.hasNext, isTrue);
      expect(third.hasNext, isFalse);
    });

    test('clamps stale page index after result set shrinks', () {
      final items = List.generate(11, (index) => index);
      final page = paginateMapGroup(items, pageIndex: 8);

      expect(page.pageIndex, 1);
      expect(page.pageCount, 2);
      expect(page.items, [10]);
    });

    test('rejects invalid page size', () {
      expect(
        () => paginateMapGroup([1], pageIndex: 0, pageSize: 0),
        throwsArgumentError,
      );
    });
  });

  testWidgets('cluster point opens a paginated listing group immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final points = List.generate(
      23,
      (index) => MapListingPoint(
        id: '$index',
        source: 'test',
        country: 'UZ',
        lat: 41.3,
        lng: 69.2,
        title: 'Listing $index',
        price: 100 + index,
        currency: 'USD',
        city: 'Tashkent',
        propertyType: 'flat',
      ),
    );
    final appState = AppState(ApiService(baseUrl: 'http://test.invalid'));
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider(create: (_) => SettingsState()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MapView(
              listings: points,
              center: const LatLng(41.3, 69.2),
              centerZoom: 12,
              onTapListing: (_) {},
              showBaseTiles: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final groupKeys = points.map((point) => point.key).toList()..sort();
    final cluster = find.byKey(Key('map-listing-group-${groupKeys.join('|')}'));
    expect(cluster, findsOneWidget);

    await tester.tap(cluster);
    await tester.pump();

    expect(find.byKey(const Key('map-listing-group-page')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(
      find.byKey(Key('map-listing-page-item-${points.first.key}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('map-listing-page-item-${points[10].key}')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('map-listing-page-next')));
    await tester.pump();

    expect(find.text('2/3'), findsOneWidget);
    expect(
      find.byKey(Key('map-listing-page-item-${points.first.key}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('map-listing-page-item-${points[10].key}')),
      findsOneWidget,
    );
  });
}
