class MapGroupPage<T> {
  const MapGroupPage({
    required this.items,
    required this.pageIndex,
    required this.pageCount,
  });

  final List<T> items;
  final int pageIndex;
  final int pageCount;

  bool get hasPrevious => pageIndex > 0;
  bool get hasNext => pageIndex + 1 < pageCount;
}

MapGroupPage<T> paginateMapGroup<T>(
  List<T> items, {
  required int pageIndex,
  int pageSize = 10,
}) {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be greater than 0');
  }
  if (items.isEmpty) {
    return MapGroupPage<T>(items: <T>[], pageIndex: 0, pageCount: 0);
  }

  final pageCount = (items.length + pageSize - 1) ~/ pageSize;
  final safePage = pageIndex.clamp(0, pageCount - 1).toInt();
  final start = safePage * pageSize;
  final end = start + pageSize < items.length ? start + pageSize : items.length;

  return MapGroupPage<T>(
    items: items.sublist(start, end),
    pageIndex: safePage,
    pageCount: pageCount,
  );
}
