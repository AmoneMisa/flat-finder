import 'package:flutter_test/flutter_test.dart';

import '../lib/models/filters.dart';

void main() {
  test('title ordering is not offered as a sort', () {
    // The sort menu is built from SortBy.values, so absence here is what keeps
    // the app off the backend's general search path.
    expect(
      SortBy.values.map((v) => v.name),
      isNot(anyElement(anyOf('titleAsc', 'titleDesc'))),
    );
  });

  test('a stored or shared title sort decodes to the server order', () {
    expect(
      Filters.fromJson(const {'sort': 'titleAsc'}).sort,
      SortBy.relevance,
      reason: 'saved presets from an older build must stay loadable',
    );
    expect(
      Filters.fromQueryParams(const {'sort': 'titleDesc'}).sort,
      SortBy.relevance,
      reason: 'shared links from an older build must stay openable',
    );
  });

  test('the remaining sorts still round-trip', () {
    for (final sort in SortBy.values) {
      final restored = Filters.fromJson(Filters(sort: sort).toJson()).sort;
      expect(restored, sort);
    }
  });
}
