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

  test('custom remains independently selectable', () {
    final filters = Filters(sources: {'custom'});
    expect(filters.toQueryParams()['sources'], 'custom');
  });
}
