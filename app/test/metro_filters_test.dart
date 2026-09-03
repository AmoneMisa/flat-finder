import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('metro query params', () {
    test('several stations round-trip as a CSV list, order-independent', () {
      final filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        metro: {'Novza', 'Chilonzor'},
      );
      final params = filters.toQueryParams();
      expect(params['metro']!.split(',').toSet(), {'Novza', 'Chilonzor'});

      final restored = Filters.fromQueryParams(params);
      expect(restored.metro, {'Novza', 'Chilonzor'});
    });

    test('the arc round-trips as "<from>,<to>" and both ends are required', () {
      final filters = Filters(
        countries: {'UZ'},
        metro: {'Novza'},
        metroMaxM: 780,
        metroBearingFrom: 252,
        metroBearingTo: 288,
      );
      final params = filters.toQueryParams();
      expect(params['metroArc'], '252,288');

      final restored = Filters.fromQueryParams(params);
      expect(restored.metroBearingFrom, 252);
      expect(restored.metroBearingTo, 288);
    });

    test('a malformed metroArc is dropped instead of producing a half arc', () {
      for (final raw in ['252', '252,288,10', 'west,288', '']) {
        final restored = Filters.fromQueryParams({'metroArc': raw});
        expect(restored.metroBearingFrom, isNull, reason: raw);
        expect(restored.metroBearingTo, isNull, reason: raw);
      }
    });

    test('no stations means no metro or metroArc param at all', () {
      final params = Filters(countries: {'UZ'}).toQueryParams();
      expect(params.containsKey('metro'), isFalse);
      expect(params.containsKey('metroArc'), isFalse);
    });
  });

  group('metro JSON persistence', () {
    test('the station set and arc survive a save/restore round trip', () {
      final filters = Filters(
        countries: {'UZ'},
        metro: {'Novza', 'Chilonzor'},
        metroMaxM: 780,
        metroBearingFrom: 252,
        metroBearingTo: 288,
      );
      final restored = Filters.fromJson(filters.toJson());
      expect(restored.metro, {'Novza', 'Chilonzor'});
      expect(restored.metroBearingFrom, 252);
      expect(restored.metroBearingTo, 288);
    });
  });

  group('AppState normalization', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('clearing the last station also clears its radius and arc', () {
      final api = ApiService(baseUrl: 'http://test.invalid');
      final state = AppState(api)
        ..filters = Filters(
          countries: {'UZ'},
          metro: {'Novza'},
          metroMaxM: 780,
          metroBearingFrom: 252,
          metroBearingTo: 288,
        );

      state.updateFilters(state.filters.copyWith(metro: {}));

      expect(state.filters.metroMaxM, isNull);
      expect(state.filters.metroBearingFrom, isNull);
      expect(state.filters.metroBearingTo, isNull);
    });

    test('picking a different station drops the old arc, like the radius', () {
      final api = ApiService(baseUrl: 'http://test.invalid');
      final state = AppState(api)
        ..filters = Filters(
          countries: {'UZ'},
          city: 'Tashkent',
          metro: {'Novza'},
          metroMaxM: 780,
          metroBearingFrom: 252,
          metroBearingTo: 288,
        );

      // A control that does not know about the arc (e.g. the filter sheet
      // rebuilding a fresh Filters from its own fields) submits a payload
      // that implicitly carries the old bearings forward via copyWith's
      // preserve-by-default semantics -- exactly like the existing radius
      // scenario this mirrors.
      state.updateFilters(
        state.filters.copyWith(metro: {'Chilonzor'}, metroMaxM: 780),
      );

      expect(state.filters.metro, {'Chilonzor'});
      expect(state.filters.metroBearingFrom, isNull);
      expect(state.filters.metroBearingTo, isNull);
    });

    test('an explicit arc submitted alongside the same station set survives',
        () {
      final api = ApiService(baseUrl: 'http://test.invalid');
      final state = AppState(api)
        ..filters =
            Filters(countries: {'UZ'}, metro: {'Novza'}, metroMaxM: 500);

      state.updateFilters(
        state.filters.copyWith(metroBearingFrom: 90, metroBearingTo: 180),
      );

      expect(state.filters.metroBearingFrom, 90);
      expect(state.filters.metroBearingTo, 180);
    });
  });

  group('upstream query params', () {
    test('one station still narrows server-side, arc dropped', () {
      final filters = Filters(
        countries: {'UZ'},
        metro: {'Novza'},
        metroMaxM: 780,
        metroBearingFrom: 252,
        metroBearingTo: 288,
      );
      final params = filters.toUpstreamQueryParams();
      expect(params['metro'], 'Novza');
      expect(params['metroMaxM'], '780');
      expect(params.containsKey('metroArc'), isFalse);
    });

    test('several stations send nothing metro-related upstream', () {
      final filters = Filters(
        countries: {'UZ'},
        metro: {'Novza', 'Chilonzor'},
        metroMaxM: 780,
      );
      final params = filters.toUpstreamQueryParams();
      expect(params.containsKey('metro'), isFalse);
      expect(params.containsKey('metroMaxM'), isFalse);
    });

    test('the full representation (sharing/JSON) is untouched', () {
      final filters = Filters(
        countries: {'UZ'},
        metro: {'Novza', 'Chilonzor'},
        metroBearingFrom: 252,
        metroBearingTo: 288,
      );
      final full = filters.toQueryParams();
      expect(full['metro']!.split(',').toSet(), {'Novza', 'Chilonzor'});
      expect(full['metroArc'], '252,288');
    });
  });
}
