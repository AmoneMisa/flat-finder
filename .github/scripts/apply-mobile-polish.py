from pathlib import Path
import re


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


def regex_once(text, pattern, repl, label, flags=0):
    out, count = re.subn(pattern, lambda _m: repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return out


# ---------------------------------------------------------------------------
# Explicit quick-filter strings. These labels are intentionally separate from
# the longer advanced-filter copy so the compact mobile header never falls
# back to English or to wording that is too wide for one row.
# ---------------------------------------------------------------------------
path = "app/lib/l10n/strings.dart"
text = read(path)
text = replace_once(
    text,
    "      'filters': 'Filters',\n",
    """      'filters': 'Filters',
      'quickSearch': 'Search',
      'quickCountry': 'Country',
      'quickCity': 'City',
      'quickAgency': 'Owner / agency',
      'quickPriceMin': 'Price min',
      'quickPriceMax': 'Price max',
""",
    "english quick filter strings",
)
text = replace_once(
    text,
    "      'filters': 'Фильтры',\n",
    """      'filters': 'Фильтры',
      'quickSearch': 'Поиск',
      'quickCountry': 'Страна',
      'quickCity': 'Город',
      'quickAgency': 'Собственник / агентство',
      'quickPriceMin': 'Цена от',
      'quickPriceMax': 'Цена до',
""",
    "russian quick filter strings",
)
write(path, text)


# ---------------------------------------------------------------------------
# Searchable dropdowns share the same dense geometry as normal form fields.
# ---------------------------------------------------------------------------
path = "app/lib/widgets/searchable_dropdown.dart"
text = read(path)
text = replace_once(
    text,
    """          isDense: true,
          // A floating label (not a hint) so this reads the same as every
""",
    """          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          constraints: const BoxConstraints(minHeight: 42),
          // A floating label (not a hint) so this reads the same as every
""",
    "searchable dropdown compact geometry",
)
text = text.replace("minWidth: 26,\n            minHeight: 20,", "minWidth: 30,\n            minHeight: 20,", 1)
text = text.replace("minWidth: 26,\n            minHeight: 20,", "minWidth: 30,\n            minHeight: 20,", 1)
write(path, text)


# ---------------------------------------------------------------------------
# Main screen: tighter app bar and one consistent compact input system.
# The location-i18n patch runs before this script in CI, so this section targets
# its 32x40 action style and localized city metadata.
# ---------------------------------------------------------------------------
path = "app/lib/screens/home_screen.dart"
text = read(path)
text = replace_once(
    text,
    """    final headerActionStyle = IconButton.styleFrom(
      minimumSize: const Size(32, 40),
      maximumSize: const Size(32, 40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );""",
    """    final headerActionStyle = IconButton.styleFrom(
      minimumSize: const Size(28, 38),
      maximumSize: const Size(28, 38),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );""",
    "compact header action slots",
)
text = text.replace("toolbarHeight: 40,", "toolbarHeight: 38,", 1)

start = text.index("class _MobilePrimaryFiltersState")
end = text.index("/// The quick-filter deal-type segments", start)
mobile = text[start:end]
mobile = replace_once(
    mobile,
    """    return Theme(
      data: theme.copyWith(textTheme: inputTextTheme),""",
    """    final compactInputTheme = theme.inputDecorationTheme.copyWith(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(minHeight: 42),
      border: const OutlineInputBorder(),
    );
    return Theme(
      data: theme.copyWith(
        textTheme: inputTextTheme,
        inputDecorationTheme: compactInputTheme,
      ),""",
    "mobile compact input theme",
)
mobile = mobile.replace(
    "padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),",
    "padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),",
    1,
)
mobile = mobile.replace("const SizedBox(height: 8),", "const SizedBox(height: 5),")
mobile = mobile.replace("const SizedBox(width: 8),", "const SizedBox(width: 5),")
mobile = mobile.replace("const SizedBox(width: 6),", "const SizedBox(width: 5),")
mobile = mobile.replace("labelText: s.t('keyword'),", "labelText: s.t('quickSearch'),", 1)
mobile = replace_once(
    mobile,
    """                  prefixIcon: const Icon(Icons.search),
                  labelText: s.t('quickSearch'),""",
    """                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 20,
                  ),
                  labelText: s.t('quickSearch'),""",
    "mobile search icon geometry",
)
mobile = mobile.replace("labelText: s.t('country')", "labelText: s.t('quickCountry')", 1)
mobile = replace_once(
    mobile,
    """                      hint: s.t('anyCity'),
                      options: cities,""",
    """                      hint: s.t('quickCity'),
                      placeholder: s.t('anyCity'),
                      options: cities,""",
    "mobile city label",
)
mobile = mobile.replace(
    "country?.cityLabel(city) ?? cityLabel(city, s.lang)",
    "country?.cityLabel(city) ?? city",
    1,
)
mobile = mobile.replace("labelText: s.t('realEstateAgency')", "labelText: s.t('quickAgency')", 1)
mobile = mobile.replace("labelText: s.t('priceFrom')", "labelText: s.t('quickPriceMin')", 1)
mobile = mobile.replace("labelText: s.t('priceTo')", "labelText: s.t('quickPriceMax')", 1)
text = text[:start] + mobile + text[end:]
write(path, text)


# ---------------------------------------------------------------------------
# Mobile listing cards: actions are pinned to the lower edge of the metadata
# panel instead of following the last badge/location line.
# ---------------------------------------------------------------------------
path = "app/lib/widgets/listing_card.dart"
text = read(path)
text = replace_once(
    text,
    """                          geographyCountry: geographyCountry,
                          compact: true,""",
    """                          geographyCountry: geographyCountry,
                          compact: true,
                          pinActionsBottom: true,""",
    "pin mobile card actions",
)
text = replace_once(
    text,
    """    required Country? geographyCountry,
    bool compact = false,
  }) {""",
    """    required Country? geographyCountry,
    bool compact = false,
    bool pinActionsBottom = false,
  }) {""",
    "card meta bottom pin option",
)
text = replace_once(
    text,
    """          SizedBox(height: (compact ? 4 : 8) + 4),
          Align(alignment: Alignment.centerRight, child: actions),""",
    """          if (pinActionsBottom)
            const Spacer()
          else
            SizedBox(height: (compact ? 4 : 8) + 4),
          Align(alignment: Alignment.centerRight, child: actions),""",
    "card actions spacer",
)
write(path, text)


# ---------------------------------------------------------------------------
# Map clusters: wheel capacity is 10; clusters larger than that zoom to the
# first level where every resulting screen-space subcluster is <=10. The radial
# wheel contains only colored price circles and has no pagination/photos.
# ---------------------------------------------------------------------------
path = "app/lib/widgets/map_view.dart"
text = read(path)
text = text.replace("import 'package:cached_network_image/cached_network_image.dart';\n", "", 1)
text = text.replace("  static const _pageSize = 9;", "  static const _radialCapacity = 10;", 1)
text = text.replace("  final Map<String, int> _groupPage = {};\n", "", 1)
text = regex_once(
    text,
    r"  Offset _worldPixel\(LatLng point\) \{.*?\n  \}\n\n  double _wrappedDx\(double a, double b\) \{.*?\n  \}",
    """  Offset _worldPixel(LatLng point, [double? zoom]) {
    final z = zoom ?? _zoom;
    final worldSize = 256.0 * math.pow(2, z).toDouble();
    final lat = point.latitude.clamp(-85.05112878, 85.05112878).toDouble();
    final sinLat = math.sin(lat * math.pi / 180);
    final x = (point.longitude + 180) / 360 * worldSize;
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        worldSize;
    return Offset(x, y);
  }

  double _wrappedDx(double a, double b, [double? zoom]) {
    final z = zoom ?? _zoom;
    final worldSize = 256.0 * math.pow(2, z).toDouble();
    final raw = (a - b).abs();
    return math.min(raw, worldSize - raw);
  }""",
    "map pixel helpers with candidate zoom",
    flags=re.S,
)
text = text.replace(
    "List<_PinGroup> _groupsFor(List<Listing> located) {",
    "List<_PinGroup> _groupsFor(List<Listing> located, {double? zoom}) {",
    1,
)
text = text.replace(
    "final point = _worldPixel(LatLng(listing.lat!, listing.lng!));",
    "final point = _worldPixel(LatLng(listing.lat!, listing.lng!), zoom);",
    1,
)
text = text.replace(
    "final dx = _wrappedDx(cluster.x, point.dx);",
    "final dx = _wrappedDx(cluster.x, point.dx, zoom);",
    1,
)
text = replace_once(
    text,
    """  bool _hasRealSpread(_PinGroup group) {
    final first = group.listings.first;
    return group.listings
        .skip(1)
        .any((listing) => listing.lat != first.lat || listing.lng != first.lng);
  }
""",
    """  bool _hasRealSpread(_PinGroup group) {
    final first = group.listings.first;
    return group.listings
        .skip(1)
        .any((listing) => listing.lat != first.lat || listing.lng != first.lng);
  }

  double _zoomForRadialCapacity(_PinGroup group) {
    var candidate = _zoom + 0.5;
    while (candidate <= _clusterZoomMax + 0.001) {
      final groups = _groupsFor(group.listings, zoom: candidate);
      if (groups.every((item) => item.listings.length <= _radialCapacity)) {
        return candidate;
      }
      candidate += 0.5;
    }
    return _clusterZoomMax;
  }
""",
    "map radial capacity zoom helper",
)
text = regex_once(
    text,
    r"  void _openGroup\(_PinGroup group\) \{.*?\n  \}\n\n  List<Marker> _markersForGroup",
    """  void _openGroup(_PinGroup group) {
    if (group.listings.length == 1) {
      widget.onTapListing(group.listings.first);
      return;
    }
    if (group.listings.length > _radialCapacity &&
        _hasRealSpread(group) &&
        _zoom < _clusterZoomMax - 0.01) {
      final targetZoom = _zoomForRadialCapacity(group);
      setState(() => _expandedGroupKey = null);
      _controller.move(group.point, targetZoom);
      return;
    }
    setState(() => _expandedGroupKey = group.key);
  }

  List<Marker> _markersForGroup""",
    "map open group behavior",
    flags=re.S,
)
text = regex_once(
    text,
    r"  Marker _radialMarkerForGroup\(_PinGroup group\) \{.*?\n  \}\n\n  void _onMapTap",
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

  void _onMapTap""",
    "map radial marker without pagination",
    flags=re.S,
)
# Replace the old photo-card radial implementation and pager hub wholesale.
text = regex_once(
    text,
    r"class _RadialClusterMarker extends StatelessWidget \{.*\Z",
    """class _RadialClusterMarker extends StatelessWidget {
  const _RadialClusterMarker({
    required this.items,
    required this.rates,
    required this.displayCurrency,
    required this.onTapListing,
    required this.onClose,
  });

  final List<Listing> items;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final void Function(Listing) onTapListing;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const size = 280.0;
    const center = size / 2;
    final radius = switch (items.length) {
      <= 4 => 66.0,
      <= 7 => 84.0,
      _ => 104.0,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < items.length; i++)
            () {
              final angle =
                  (-90 + (360 / math.max(1, items.length)) * i) * math.pi / 180;
              return Positioned(
                left: center + math.cos(angle) * radius - 24,
                top: center + math.sin(angle) * radius - 24,
                child: _RadialPriceDot(
                  listing: items[i],
                  rates: rates,
                  displayCurrency: displayCurrency,
                  onTap: () => onTapListing(items[i]),
                ),
              );
            }(),
          Positioned(
            left: center - 18,
            top: center - 18,
            child: _RadialHub(onClose: onClose),
          ),
        ],
      ),
    );
  }
}

class _RadialHub extends StatelessWidget {
  const _RadialHub({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 8,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onClose,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.close, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _RadialPriceDot extends StatelessWidget {
  const _RadialPriceDot({
    required this.listing,
    required this.rates,
    required this.displayCurrency,
    required this.onTap,
  });

  final Listing listing;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratesOrEmpty = rates ?? const <String, double>{};
    final color = priceToneColor(listingPriceTone(listing, ratesOrEmpty));
    final price = pinPriceLabel(
      listing,
      rates: rates,
      displayCurrency: displayCurrency,
    );
    return Material(
      color: color.withValues(alpha: 0.97),
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              price,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black38, blurRadius: 2)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
""",
    "map radial price-dot implementation",
    flags=re.S,
)
write(path, text)


# The location patch removes cityLabel usage from stats, so its old format
# helper import is obsolete and should not turn analyzer warnings fatal.
path = "app/lib/widgets/stats_sheet.dart"
text = read(path)
text = text.replace("import '../utils/format.dart';\n", "", 1)
write(path, text)

print('Mobile polish patch applied')
