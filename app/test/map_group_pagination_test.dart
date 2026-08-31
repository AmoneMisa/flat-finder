import 'package:flat_finder/utils/map_group_pagination.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
