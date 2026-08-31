import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flat_finder/l10n/strings.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/widgets/nearby_transport_tables.dart';

const _stops = [
  NearbyTransportStop(
    id: 'bus-1',
    name: 'Chilanzar-19',
    mode: 'bus',
    distanceM: 120,
    routeRefs: ['48'],
  ),
  NearbyTransportStop(
    id: 'trolley-1',
    name: 'North station',
    mode: 'trolleybus',
    distanceM: 180,
    routeRefs: ['7'],
  ),
  NearbyTransportStop(
    id: 'tram-1',
    name: 'Sergeli',
    mode: 'tram',
    distanceM: 150,
    routeRefs: ['1'],
  ),
];

Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const NearbyTransportTables(
              stops: _stops,
              s: AppStrings('en'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('uses three transport columns above 768 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAtWidth(tester, 960);

    final bus = tester.getTopLeft(find.byKey(const Key('nearby-transport-bus')));
    final trolley = tester.getTopLeft(
      find.byKey(const Key('nearby-transport-trolleybus')),
    );
    final tram = tester.getTopLeft(find.byKey(const Key('nearby-transport-tram')));

    expect(trolley.dy, bus.dy);
    expect(tram.dy, bus.dy);
    expect(trolley.dx, greaterThan(bus.dx));
    expect(tram.dx, greaterThan(trolley.dx));
  });

  testWidgets('uses two transport columns at 768 logical pixels', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAtWidth(tester, 768);

    final bus = tester.getTopLeft(find.byKey(const Key('nearby-transport-bus')));
    final trolley = tester.getTopLeft(
      find.byKey(const Key('nearby-transport-trolleybus')),
    );
    final tram = tester.getTopLeft(find.byKey(const Key('nearby-transport-tram')));

    expect(trolley.dy, bus.dy);
    expect(trolley.dx, greaterThan(bus.dx));
    expect(tram.dy, greaterThan(bus.dy));
    expect(tram.dx, bus.dx);
  });

  testWidgets('sorts stops by distance inside a mode table', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const stops = [
      NearbyTransportStop(
        id: 'far',
        name: 'Far stop',
        mode: 'bus',
        distanceM: 500,
        routeRefs: ['9'],
      ),
      NearbyTransportStop(
        id: 'near',
        name: 'Near stop',
        mode: 'bus',
        distanceM: 100,
        routeRefs: ['1'],
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: NearbyTransportModeTable(
              title: 'Bus',
              icon: Icons.directions_bus_outlined,
              stops: stops,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Near stop')).dy,
      lessThan(tester.getTopLeft(find.text('Far stop')).dy),
    );
  });
}
