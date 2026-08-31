from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAP_VIEW = ROOT / "app/lib/widgets/map_view.dart"
PAGINATION = ROOT / "app/lib/utils/map_group_pagination.dart"
PAGINATION_TEST = ROOT / "app/test/map_group_pagination_test.dart"

text = MAP_VIEW.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "import '../utils/format.dart';\nimport '../utils/price_tone.dart';",
    "import '../utils/format.dart';\nimport '../utils/map_group_pagination.dart';\nimport '../utils/price_tone.dart';",
    "pagination import",
)

replace_once(
    """    final cityChanged =
        old.country != widget.country || old.city != widget.city;
    final localeChanged = old.locale != widget.locale;
""",
    """    final cityChanged =
        old.country != widget.country || old.city != widget.city;
    final listingsChanged = !identical(old.listings, widget.listings);
    final localeChanged = old.locale != widget.locale;
    if (cityChanged || listingsChanged) {
      _expandedGroupKey = null;
      _expandedGroupPage = 0;
    }
""",
    "reset pagination when data scope changes",
)

replace_once(
    "if ((cityChanged || !identical(old.listings, widget.listings)) &&",
    "if ((cityChanged || listingsChanged) &&",
    "reuse listingsChanged",
)

replace_once(
    "  String? _expandedGroupKey;\n",
    "  String? _expandedGroupKey;\n  int _expandedGroupPage = 0;\n",
    "expanded group page state",
)

replace_once(
    """  void _openGroup(_PinGroup group) {
    if (group.listings.length == 1) {
      widget.onTapListing(group.listings.first);
      return;
    }
    if (group.listings.length > _radialCapacity) {
      if (_zoom < _clusterZoomMax - 0.01) {
        final targetZoom = math.min(_zoom + 1.0, _clusterZoomMax);
        setState(() => _expandedGroupKey = null);
        _controller.move(group.point, targetZoom);
      } else {
        _controller.move(group.point, _zoom);
      }
      return;
    }
    _controller.move(group.point, _zoom);
    setState(() => _expandedGroupKey = group.key);
  }
""",
    """  void _openGroup(_PinGroup group) {
    if (group.listings.length == 1) {
      widget.onTapListing(group.listings.first);
      return;
    }
    if (group.listings.length > _radialCapacity &&
        _zoom < _clusterZoomMax - 0.01) {
      final targetZoom = math.min(_zoom + 1.0, _clusterZoomMax);
      setState(() {
        _expandedGroupKey = null;
        _expandedGroupPage = 0;
      });
      _controller.move(group.point, targetZoom);
      return;
    }
    _controller.move(group.point, _zoom);
    setState(() {
      _expandedGroupKey = group.key;
      _expandedGroupPage = 0;
    });
  }
""",
    "open dense group at max zoom",
)

replace_once(
    """  Marker _radialMarkerForGroup(_PinGroup group) {
    return Marker(
      point: group.point,
      width: 280,
      height: 280,
      alignment: Alignment.center,
      child: _RadialClusterMarker(
        items: group.listings.take(_radialCapacity).toList(),
        rates: widget.rates,
        displayCurrency: widget.displayCurrency,
        onTapListing: widget.onTapListing,
        onClose: () => setState(() => _expandedGroupKey = null),
      ),
    );
  }
""",
    """  Marker _radialMarkerForGroup(_PinGroup group) {
    final page = paginateMapGroup(
      group.listings,
      pageIndex: _expandedGroupPage,
      pageSize: _radialCapacity,
    );
    return Marker(
      point: group.point,
      width: 280,
      height: 280,
      alignment: Alignment.center,
      child: _RadialClusterMarker(
        items: page.items,
        pageIndex: page.pageIndex,
        pageCount: page.pageCount,
        rates: widget.rates,
        displayCurrency: widget.displayCurrency,
        onTapListing: widget.onTapListing,
        onPreviousPage: page.hasPrevious
            ? () => setState(() => _expandedGroupPage = page.pageIndex - 1)
            : null,
        onNextPage: page.hasNext
            ? () => setState(() => _expandedGroupPage = page.pageIndex + 1)
            : null,
        onClose: () => setState(() {
          _expandedGroupKey = null;
          _expandedGroupPage = 0;
        }),
      ),
    );
  }
""",
    "paginate radial marker",
)

replace_once(
    """                setState(() {
                  _zoom = z;
                  _expandedGroupKey = null;
                });
""",
    """                setState(() {
                  _zoom = z;
                  _expandedGroupKey = null;
                  _expandedGroupPage = 0;
                });
""",
    "reset page on map movement",
)

replace_once(
    """    if (_expandedGroupKey != null) {
      setState(() => _expandedGroupKey = null);
    }
""",
    """    if (_expandedGroupKey != null) {
      setState(() {
        _expandedGroupKey = null;
        _expandedGroupPage = 0;
      });
    }
""",
    "reset page on map tap",
)

replace_once(
    """  const _RadialClusterMarker({
    required this.items,
    required this.rates,
    required this.displayCurrency,
    required this.onTapListing,
    required this.onClose,
  });

  final List<MapListingPoint> items;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final void Function(MapListingPoint) onTapListing;
  final VoidCallback onClose;
""",
    """  const _RadialClusterMarker({
    required this.items,
    required this.pageIndex,
    required this.pageCount,
    required this.rates,
    required this.displayCurrency,
    required this.onTapListing,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onClose,
  });

  final List<MapListingPoint> items;
  final int pageIndex;
  final int pageCount;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final void Function(MapListingPoint) onTapListing;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback onClose;
""",
    "radial pagination props",
)

replace_once(
    """    final radius = switch (items.length) {
      <= 4 => 66.0,
      <= 7 => 84.0,
      _ => 104.0,
    };
""",
    """    final radius = pageCount > 1
        ? 104.0
        : switch (items.length) {
            <= 4 => 66.0,
            <= 7 => 84.0,
            _ => 104.0,
          };
""",
    "keep paginated radial ring clear",
)

replace_once(
    """          Positioned(
            left: center - 18,
            top: center - 18,
            child: _RadialHub(onClose: onClose),
          ),
""",
    """          Positioned(
            left: center - 18,
            top: center - 18,
            child: _RadialHub(onClose: onClose),
          ),
          if (pageCount > 1)
            Positioned(
              left: center - 59,
              top: center + 28,
              child: _RadialPager(
                pageIndex: pageIndex,
                pageCount: pageCount,
                onPreviousPage: onPreviousPage,
                onNextPage: onNextPage,
              ),
            ),
""",
    "radial pager UI",
)

replace_once(
    "class _RadialPriceDot extends StatelessWidget {",
    """class _RadialPager extends StatelessWidget {
  const _RadialPager({
    required this.pageIndex,
    required this.pageCount,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final int pageIndex;
  final int pageCount;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.80),
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: Container(
        width: 118,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            _RadialPagerButton(
              icon: Icons.chevron_left,
              onTap: onPreviousPage,
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${pageIndex + 1}/$pageCount',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _RadialPagerButton(
              icon: Icons.chevron_right,
              onTap: onNextPage,
            ),
          ],
        ),
      ),
    );
  }
}

class _RadialPagerButton extends StatelessWidget {
  const _RadialPagerButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Icon(
          icon,
          size: 19,
          color: onTap == null ? Colors.white30 : Colors.white,
        ),
      ),
    );
  }
}

class _RadialPriceDot extends StatelessWidget {""",
    "radial pager widgets",
)

MAP_VIEW.write_text(text, encoding="utf-8")

PAGINATION.write_text(
    """class MapGroupPage<T> {
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
    return MapGroupPage<T>(
      items: <T>[],
      pageIndex: 0,
      pageCount: 0,
    );
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
""",
    encoding="utf-8",
)

PAGINATION_TEST.write_text(
    """import 'package:flat_finder/utils/map_group_pagination.dart';
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
""",
    encoding="utf-8",
)
