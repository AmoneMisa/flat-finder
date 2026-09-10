import 'package:flutter_test/flutter_test.dart';
import 'package:flat_finder/models/filters.dart';

void main() {
  test('default source selection includes curated websites', () {
    final filters = Filters();

    expect(kAllSources, containsAll(<String>['olx', 'telegram', 'custom']));
    expect(filters.sources, containsAll(kAllSources));
    expect(kSourceLabels['custom'], 'Sites');

    // All sources selected means the query omits `sources`, so the backend
    // returns OLX, Telegram and curated custom-site listings together.
    expect(filters.toQueryParams().containsKey('sources'), isFalse);
  });

  test('legacy all-source preferences gain curated websites', () {
    final filters = Filters.fromJson({
      'countries': ['RO'],
      'sources': ['olx', 'telegram'],
    });

    expect(filters.sources, containsAll(kAllSources));
    expect(filters.toQueryParams().containsKey('sources'), isFalse);
  });

  test('narrow stored source selections stay narrow', () {
    final filters = Filters.fromJson({
      'countries': ['RO'],
      'sources': ['telegram'],
    });

    expect(filters.sources, {'telegram'});
    expect(filters.toQueryParams()['sources'], 'telegram');
  });

  test('custom remains independently selectable', () {
    final filters = Filters(sources: {'custom'});
    expect(filters.toQueryParams()['sources'], 'custom');
  });

  test('customSites narrows the Sites bucket without affecting sources', () {
    final filters = Filters(customSites: {'krisha.kz'});

    expect(filters.customSites, {'krisha.kz'});
    // Still "all sources" -- customSites only narrows within the custom bucket.
    expect(filters.toQueryParams().containsKey('sources'), isFalse);
    expect(filters.toQueryParams()['customSites'], 'krisha.kz');
  });

  test('customSites defaults to empty (all curated sites)', () {
    expect(Filters().customSites, isEmpty);
    expect(Filters().toQueryParams().containsKey('customSites'), isFalse);
  });

  test('customSites round-trips through JSON and query params', () {
    final restored = Filters.fromJson(
      Filters(customSites: {'krisha.kz', 'lun.ua'}).toJson(),
    );
    expect(restored.customSites, {'krisha.kz', 'lun.ua'});

    final fromQuery = Filters.fromQueryParams({'customSites': 'krisha.kz,lun.ua'});
    expect(fromQuery.customSites, {'krisha.kz', 'lun.ua'});
  });
}
