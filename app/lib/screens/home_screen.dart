import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/filters.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../state/favorites.dart';
import '../state/history.dart';
import '../state/settings.dart';
import '../utils/format.dart';
import '../utils/share_link.dart';
import '../utils/sort.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/listing_card.dart';
import '../widgets/map_view.dart';
import '../widgets/stats_sheet.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'listing_detail.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Quick views layered on top of the active filters/search results.
enum _ViewTab { all, fresh, favorites, viewed }

class _HomeScreenState extends State<HomeScreen> {
  bool _mapMode = false;
  _ViewTab _tab = _ViewTab.all;
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;
  final ScrollController _resultsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _resultsScroll.addListener(_loadMoreNearEnd);
  }

  void _loadMoreNearEnd() {
    if (!_resultsScroll.hasClients) return;
    if (_resultsScroll.position.extentAfter < 600) {
      context.read<AppState>().loadMore();
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _resultsScroll.dispose();
    super.dispose();
  }

  /// Listen for `flatfinder://search?…` deep links (a shared search opening the
  /// app) and apply the encoded filters. Handles both a cold start (initial
  /// link) and links received while the app is already running.
  Future<void> _initDeepLinks() async {
    try {
      _appLinks = AppLinks();
      final initial = await _appLinks!.getInitialLink();
      if (initial != null) _applyLink(initial);
      _linkSub = _appLinks!.uriLinkStream.listen(_applyLink, onError: (_) {});
    } catch (_) {
      // Deep links are best-effort; a platform without support just no-ops.
    }
  }

  void _applyLink(Uri uri) {
    final publicId = parseListingLink(uri);
    if (publicId != null) {
      _openSharedListing(publicId);
      return;
    }
    final filters = parseSearchUrl(uri);
    if (filters == null || !mounted) return;
    final state = context.read<AppState>();
    state.updateFilters(filters);
    state.search();
    setState(() => _mapMode = false);
  }

  /// Opens a listing shared via `flatfinder://listing?id=<publicId>`. A
  /// listing scraped moments ago may not be indexed yet, so retry a few
  /// times before giving up — same fallback the site's `?adv=` link uses.
  Future<void> _openSharedListing(int publicId) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!mounted) return;
      final listing = await _api.fetchListingByPublicId(publicId);
      if (listing != null) {
        if (!mounted) return;
        _openListing(listing);
        return;
      }
      if (attempt < 4) await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  Future<void> _openFilters(AppState state) async {
    final result = await showModalBottomSheet<Filters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => FilterSheet(
        initial: state.filters,
        countries: state.countries,
        onChanged: (filters) async {
          state.updateFilters(filters);
          await state.search();
          if (_mapMode) state.loadMapListings();
        },
      ),
    );
    if (result != null) {
      state.updateFilters(result);
      await state.search();
      if (_mapMode) state.loadMapListings();
    }
  }

  Future<void> _applyCompactFilters(AppState state, Filters filters) async {
    state.updateFilters(filters);
    await state.search();
    if (_mapMode) state.loadMapListings();
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openFavorites() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FavoritesScreen()));
  }

  void _openHistory() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
  }

  final ApiService _api = ApiService();

  void _openStats(AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => StatsSheet(api: _api, filters: state.filters),
    );
  }

  void _openListing(Listing l) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: l)));
  }

  void _showMapPreview(Listing l) async {
    Listing? full;
    for (final item in context.read<AppState>().listings) {
      if (item.id == l.id && item.source == l.source) {
        full = item;
        break;
      }
    }
    full ??= await _api.reloadListing(l) ?? l;
    if (!mounted) return;
    final resolved = full;
    showModalBottomSheet(
      context: context,
      builder: (_) => ListingCard(
        listing: resolved,
        onTap: () {
          Navigator.pop(context);
          _openListing(resolved);
        },
      ),
    );
  }

  LatLng _centerFor(AppState state) {
    // "Show on map" from a card takes priority over the country default.
    if (_focusListing?.hasLocation == true) {
      return LatLng(_focusListing!.lat!, _focusListing!.lng!);
    }
    // Center on the first selected country's capital.
    final code = state.filters.countries.isNotEmpty
        ? state.filters.countries.first
        : 'RO';
    final c = state.countryByCode(code);
    if (c != null) return LatLng(c.centerLat, c.centerLng);
    return const LatLng(45, 30);
  }

  // Set by a card's "show on map" button (mirrors the site's
  // `flat-map-focus` custom event) — switches to map view centered there.
  Listing? _focusListing;

  void _showOnMap(Listing l) {
    setState(() {
      _focusListing = l;
      _mapMode = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<SettingsState>();
    final favorites = context.watch<FavoritesState>();
    final history = context.watch<HistoryState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('appTitle')),
        actions: [
          IconButton(
            tooltip: settings.t('reloadAll'),
            icon: const Icon(Icons.refresh),
            onPressed: (state.loading || state.reloadAllCoolingDown)
                ? null
                : state.reloadAll,
          ),
          IconButton(
            tooltip: _mapMode ? settings.t('listView') : settings.t('mapView'),
            icon: Icon(_mapMode ? Icons.view_list : Icons.map_outlined),
            onPressed: () {
              setState(() => _mapMode = !_mapMode);
              if (_mapMode) state.loadMapListings();
            },
          ),
          IconButton(
            tooltip: settings.t('filters'),
            icon: const Icon(Icons.tune),
            onPressed: () => _openFilters(state),
          ),
          PopupMenuButton<String>(
            tooltip: settings.t('more'),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'history':
                  _openHistory();
                case 'favorites':
                  _openFavorites();
                case 'statistics':
                  _openStats(state);
                case 'settings':
                  _openSettings();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(settings.t('history')),
                ),
              ),
              PopupMenuItem(
                value: 'favorites',
                child: ListTile(
                  leading: const Icon(Icons.favorite_border),
                  title: Text(settings.t('favorites')),
                ),
              ),
              PopupMenuItem(
                value: 'statistics',
                child: ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: Text(settings.t('statistics')),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(settings.t('settings')),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(state: state, settings: settings),
          if (MediaQuery.sizeOf(context).width < 700)
            _MobilePrimaryFilters(
              filters: state.filters,
              countries: state.countries,
              settings: settings,
              onChanged: (filters) => _applyCompactFilters(state, filters),
            ),
          _ViewTabBar(
            current: _tab,
            settings: settings,
            onChanged: (t) => setState(() => _tab = t),
          ),
          if (state.degradedCountries.isNotEmpty)
            _Banner(
              text: settings.t('demoBanner', {
                'countries': state.degradedCountries.join(', '),
              }),
            ),
          if (state.sourceErrors.isNotEmpty)
            _SourceErrorBanner(errors: state.sourceErrors, settings: settings),
          Expanded(child: _body(state, settings, favorites, history)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openFilters(state),
        icon: const Icon(Icons.tune),
        label: Text(settings.t('filters')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _body(
    AppState state,
    SettingsState settings,
    FavoritesState favorites,
    HistoryState history,
  ) {
    if (state.loading && state.listings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.listings.isEmpty) {
      return _ErrorView(
        message: state.error!,
        onRetry: state.search,
        settings: settings,
      );
    }

    final center = _centerFor(state);
    final listings = _applyTab(
      sortListings(
        state.listings,
        state.filters.sort,
        centerLat: center.latitude,
        centerLng: center.longitude,
        rates: state.rates,
        displayCurrency: settings.displayCurrency,
      ),
      favorites,
      history,
    );

    if (listings.isEmpty) {
      return Center(child: Text(_emptyLabel(settings)));
    }

    if (_mapMode) {
      return MapView(
        listings: state.mapListings.isNotEmpty ? state.mapListings : listings,
        center: center,
        centerZoom: _focusListing?.hasLocation == true ? 15 : 6,
        onTapListing: _showMapPreview,
        rates: state.rates,
        displayCurrency: settings.displayCurrency,
        country: state.filters.countries.isNotEmpty
            ? state.filters.countries.first
            : '',
        city: state.filters.city,
      );
    }
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = _columnsFor(constraints.maxWidth);
            // A single column keeps the original full-width card list; multiple
            // columns lay the cards out in a responsive grid.
            if (columns == 1) {
              return ListView.builder(
                controller: _resultsScroll,
                padding: const EdgeInsets.only(bottom: 90, top: 4),
                itemCount: listings.length + (state.loadingMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == listings.length) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final l = listings[i];
                  return ListingCard(
                    listing: l,
                    onTap: () => _openListing(l),
                    onShowOnMap: () => _showOnMap(l),
                  );
                },
              );
            }
            return GridView.builder(
              controller: _resultsScroll,
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 90),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.82,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: listings.length + (state.loadingMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == listings.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final l = listings[i];
                return ListingCard(
                  listing: l,
                  grid: true,
                  onTap: () => _openListing(l),
                  onShowOnMap: () => _showOnMap(l),
                );
              },
            );
          },
        ),
        if (state.loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  /// Restrict the visible listings to the selected quick view (on top of the
  /// active filters/search). "Fresh" keeps only posts from the last 24 hours.
  List<Listing> _applyTab(
    List<Listing> listings,
    FavoritesState fav,
    HistoryState hist,
  ) {
    switch (_tab) {
      case _ViewTab.all:
        return listings;
      case _ViewTab.favorites:
        return listings.where((l) => fav.isFavorite(l.id)).toList();
      case _ViewTab.viewed:
        return listings.where((l) => hist.isViewed(l.id)).toList();
      case _ViewTab.fresh:
        final cutoff = DateTime.now().toUtc().subtract(
          const Duration(hours: 24),
        );
        return listings
            .where(
              (l) =>
                  l.createdAt != null && l.createdAt!.toUtc().isAfter(cutoff),
            )
            .toList();
    }
  }

  String _emptyLabel(SettingsState settings) => switch (_tab) {
    _ViewTab.favorites => settings.t('noFavoritesHere'),
    _ViewTab.viewed => settings.t('noViewedHere'),
    _ViewTab.fresh => settings.t('noFreshHere'),
    _ViewTab.all => settings.t('noListings'),
  };

  /// Column count from the available width: 1 on phones, up to 4 on wide
  /// desktop windows.
  int _columnsFor(double width) {
    if (width >= 1500) return 4;
    if (width >= 1100) return 3;
    if (width >= 700) return 2;
    return 1;
  }
}

/// The primary web filters stay visible on phones. Advanced filters remain in
/// the bottom sheet, but the common search path never requires opening it.
class _MobilePrimaryFilters extends StatefulWidget {
  const _MobilePrimaryFilters({
    required this.filters,
    required this.countries,
    required this.settings,
    required this.onChanged,
  });

  final Filters filters;
  final List<Country> countries;
  final SettingsState settings;
  final ValueChanged<Filters> onChanged;

  @override
  State<_MobilePrimaryFilters> createState() => _MobilePrimaryFiltersState();
}

class _MobilePrimaryFiltersState extends State<_MobilePrimaryFilters> {
  late final TextEditingController _query;
  late final TextEditingController _priceMin;
  late final TextEditingController _priceMax;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.filters.query);
    _priceMin = TextEditingController(
      text: _numberText(widget.filters.priceMin),
    );
    _priceMax = TextEditingController(
      text: _numberText(widget.filters.priceMax),
    );
  }

  @override
  void didUpdateWidget(covariant _MobilePrimaryFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_query, widget.filters.query);
    _sync(_priceMin, _numberText(widget.filters.priceMin));
    _sync(_priceMax, _numberText(widget.filters.priceMax));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _priceMin.dispose();
    _priceMax.dispose();
    super.dispose();
  }

  static String _numberText(num? value) => value?.toString() ?? '';

  void _sync(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _schedule(Filters filters, {bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      widget.onChanged(filters);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => widget.onChanged(filters),
    );
  }

  Filters _withTextValues() {
    final min = num.tryParse(_priceMin.text.trim());
    final max = num.tryParse(_priceMax.text.trim());
    return widget.filters.copyWith(
      query: _query.text.trim(),
      priceMin: min,
      priceMax: max,
      clearPriceMin: min == null,
      clearPriceMax: max == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final selectedCountry = widget.filters.countries.isNotEmpty
        ? widget.filters.countries.first
        : null;
    Country? country;
    for (final item in widget.countries) {
      if (item.code == selectedCountry) country = item;
    }
    final cities = country?.cities ?? const <String>[];
    final selectedCity = cities.contains(widget.filters.city)
        ? widget.filters.city
        : null;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          children: [
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: s.t('keyword'),
                hintText: s.t('keywordHint'),
              ),
              onChanged: (_) => _schedule(_withTextValues()),
              onSubmitted: (_) => _schedule(_withTextValues(), immediate: true),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedCountry,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: s.t('country')),
                    items: widget.countries
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.code,
                            child: Text(
                              '${countryFlags[item.code] ?? ''} ${s.countryName(item.code, item.name)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      _schedule(
                        _withTextValues().copyWith(
                          countries: {value},
                          city: '',
                          district: '',
                          microdistrict: '',
                          quartal: '',
                          area: '',
                          metro: '',
                        ),
                        immediate: true,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedCity,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: s.t('city')),
                    hint: Text(s.t('anyCity')),
                    items: cities
                        .map(
                          (city) => DropdownMenuItem(
                            value: city,
                            child: Text(city, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => _schedule(
                      _withTextValues().copyWith(
                        city: value ?? '',
                        district: '',
                        microdistrict: '',
                        quartal: '',
                        area: '',
                        metro: '',
                      ),
                      immediate: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<AgencyFilter>(
                    value: widget.filters.agency,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: s.t('realEstateAgency'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: AgencyFilter.any,
                        child: Text(s.t('any')),
                      ),
                      DropdownMenuItem(
                        value: AgencyFilter.owner,
                        child: Text(s.t('owner')),
                      ),
                      DropdownMenuItem(
                        value: AgencyFilter.agency,
                        child: Text(s.t('agency')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _schedule(
                        _withTextValues().copyWith(agency: value),
                        immediate: true,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _priceMin,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: s.t('min'),
                            hintText: s.t('minPlaceholder'),
                          ),
                          onChanged: (_) => _schedule(_withTextValues()),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _priceMax,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: s.t('max'),
                            hintText: s.t('maxPlaceholder'),
                          ),
                          onChanged: (_) => _schedule(_withTextValues()),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal quick-view selector (All / Fresh / Favorites / Viewed) shown above
/// the results, layered on top of the active filters.
class _ViewTabBar extends StatelessWidget {
  const _ViewTabBar({
    required this.current,
    required this.settings,
    required this.onChanged,
  });

  final _ViewTab current;
  final SettingsState settings;
  final ValueChanged<_ViewTab> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(_ViewTab, String, IconData)>[
      (_ViewTab.all, 'tabAll', Icons.list),
      (_ViewTab.fresh, 'tabFresh', Icons.bolt),
      (_ViewTab.favorites, 'tabFavorites', Icons.favorite),
      (_ViewTab.viewed, 'tabViewed', Icons.visibility),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          for (final (tab, key, icon) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: current == tab,
                avatar: Icon(icon, size: 16),
                label: Text(settings.t(key)),
                onSelected: (_) => onChanged(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.state, required this.settings});
  final AppState state;
  final SettingsState settings;

  @override
  Widget build(BuildContext context) {
    final f = state.filters;
    final flags = f.countries.map((c) => countryFlags[c] ?? c).join(' ');
    final type = switch (f.propertyType) {
      PropertyType.flat => settings.t('apartments'),
      PropertyType.house => settings.t('houses'),
      PropertyType.any => settings.t('allTypes'),
    };
    final agency = switch (f.agency) {
      AgencyFilter.owner => settings.t('owner'),
      AgencyFilter.agency => settings.t('agency'),
      AgencyFilter.any => settings.t('anySeller'),
    };
    final parts = [flags, type, agency];
    if (f.sources.isNotEmpty && f.sources.length < kAllSources.length) {
      parts.add(f.sources.map((s) => kSourceLabels[s] ?? s).join('/'));
    }
    parts.add(
      settings.t('results', {
        'n': '${state.total > 0 ? state.total : state.listings.length}',
      }),
    );
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        parts.join('   ·   '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

/// Red, expandable banner listing sources that failed during the last search
/// (a blocked scraper, or a custom URL that returned nothing / was unreachable).
class _SourceErrorBanner extends StatelessWidget {
  const _SourceErrorBanner({required this.errors, required this.settings});
  final List<SourceError> errors;
  final SettingsState settings;

  String _label(SourceError e) {
    final who = e.url ?? (kSourceLabels[e.source] ?? e.source);
    return '$who — ${e.message}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(
            Icons.error_outline,
            size: 20,
            color: Colors.red.shade700,
          ),
          title: Text(
            '${settings.t('sourceErrorsTitle')} (${errors.length})',
            style: TextStyle(fontSize: 13, color: Colors.red.shade900),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          children: [
            for (final e in errors)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _label(e),
                    style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.settings,
  });
  final String message;
  final VoidCallback onRetry;
  final SettingsState settings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48),
            const SizedBox(height: 12),
            Text(
              '${settings.t('couldNotReach')}\n\n$message\n\n${settings.t('backendHint')}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(settings.t('retry'))),
          ],
        ),
      ),
    );
  }
}
