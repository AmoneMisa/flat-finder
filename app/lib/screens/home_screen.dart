import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/filters.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../state/hidden.dart';
import '../state/settings.dart';
import '../utils/format.dart';
import '../utils/share_link.dart';
import '../utils/sort.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/listing_card.dart';
import '../widgets/map_view.dart';
import '../widgets/searchable_dropdown.dart';
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
enum _ViewTab { all, fresh, hidden }

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

  /// Pushes the map as its own full-screen route (no app bar/filters above
  /// it), reusing the exact same listings/center already loaded.
  void _openFullScreenMap(
    AppState state,
    SettingsState settings,
    String country,
    List<Listing> listings,
    LatLng center,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(settings.t('mapView'))),
          body: MapView(
            key: ValueKey('fullscreen-map-$country-${state.filters.city}'),
            listings: listings,
            center: center,
            centerZoom: _focusListing?.hasLocation == true ? 18 : 6,
            onTapListing: _showMapPreview,
            rates: state.rates,
            displayCurrency: settings.displayCurrency,
            country: country,
            city: state.filters.city,
            locale: settings.lang,
          ),
        ),
      ),
    );
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

  void _showMapPreview(Listing l) {
    final state = context.read<AppState>();
    var initial = l;
    for (final item in state.listings) {
      if (item.id == l.id && item.source == l.source) {
        initial = item;
        break;
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _MapListingPreview(
        api: _api,
        initial: initial,
        onOpen: (resolved) {
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
    final hidden = context.watch<HiddenState>();
    final headerActionStyle = IconButton.styleFrom(
      minimumSize: const Size(30, 38),
      maximumSize: const Size(30, 38),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    // Cheap no-op once already fetched for this language; re-fetches with
    // localized city/district/metro names once settings finish loading (or
    // whenever the language changes).
    state.ensureCountriesLocale(settings.lang);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 38,
        title: Text(
          settings.t('appTitle'),
          style: const TextStyle(fontSize: 18),
        ),
        actionsPadding: EdgeInsets.zero,
        actions: [
          IconButton(
            tooltip: _mapMode ? settings.t('listView') : settings.t('mapView'),
            iconSize: 22,
            padding: EdgeInsets.zero,
            style: headerActionStyle,
            icon: Icon(_mapMode ? Icons.view_list : Icons.map_outlined),
            onPressed: () {
              setState(() => _mapMode = !_mapMode);
              if (_mapMode) state.loadMapListings();
            },
          ),
          // Sort used to live only inside the full filter sheet, then in a
          // separate summary-bar control — surfaced here as a plain icon,
          // alongside the rest of the header's icons, since it's changed far
          // more often than any other filter.
          PopupMenuButton<SortBy>(
            tooltip: settings.t('sortBy'),
            padding: EdgeInsets.zero,
            style: headerActionStyle,
            icon: Icon(
              Icons.sort,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
            initialValue: state.filters.sort,
            onSelected: (v) =>
                state.updateFilters(state.filters.copyWith(sort: v)),
            itemBuilder: (context) => SortBy.values
                .map(
                  (v) => PopupMenuItem(
                    value: v,
                    child: Text(sortLabel(settings.s, v)),
                  ),
                )
                .toList(),
          ),
          // The filter icon here duplicated the FAB below, which already
          // opens the same sheet — a currency switch is more useful to have
          // one tap away in the header. Icon-only, matching the rest of the
          // header's icons instead of carrying its own text label.
          PopupMenuButton<String?>(
            tooltip: settings.t('displayCurrency'),
            padding: EdgeInsets.zero,
            style: headerActionStyle,
            icon: Icon(
              Icons.currency_exchange,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
            onSelected: settings.setDisplayCurrency,
            itemBuilder: (_) => [
              PopupMenuItem<String?>(
                value: null,
                child: Text(settings.t('nativeCurrency')),
              ),
              for (final code in SettingsState.currencyOptions)
                if (code != null)
                  PopupMenuItem<String?>(value: code, child: Text(code)),
            ],
          ),
          IconButton(
            tooltip: settings.t('statistics'),
            iconSize: 22,
            padding: EdgeInsets.zero,
            style: headerActionStyle,
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => _openStats(state),
          ),
          PopupMenuButton<String>(
            tooltip: settings.t('more'),
            padding: EdgeInsets.zero,
            style: headerActionStyle,
            icon: const Icon(Icons.more_vert, size: 22),
            onSelected: (value) {
              switch (value) {
                case 'view_all':
                  setState(() => _tab = _ViewTab.all);
                case 'view_fresh':
                  setState(() => _tab = _ViewTab.fresh);
                case 'view_hidden':
                  setState(() => _tab = _ViewTab.hidden);
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
            itemBuilder: (_) {
              // Favorites/History have their own dedicated (grouped) screens
              // reachable below, so only the views without one of those get a
              // quick-switch entry here — no more duplicate favorites/viewed
              // entries.
              const views = <(_ViewTab, String, String, IconData)>[
                (_ViewTab.all, 'view_all', 'tabAll', Icons.list),
                (_ViewTab.fresh, 'view_fresh', 'tabFresh', Icons.bolt),
                (
                  _ViewTab.hidden,
                  'view_hidden',
                  'tabHidden',
                  Icons.visibility_off,
                ),
              ];
              return [
                for (final (tab, value, key, icon) in views)
                  PopupMenuItem(
                    value: value,
                    child: ListTile(
                      leading: Icon(
                        icon,
                        color: _tab == tab
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(settings.t(key)),
                      trailing: _tab == tab
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                  ),
                const PopupMenuDivider(),
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
                  value: 'settings',
                  child: ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(settings.t('settings')),
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (MediaQuery.sizeOf(context).width < 700)
            _MobilePrimaryFilters(
              filters: state.filters,
              countries: state.countries,
              settings: settings,
              onChanged: (filters) => _applyCompactFilters(state, filters),
            ),
          _SummaryBar(state: state, settings: settings),
          if (state.degradedCountries.isNotEmpty)
            _Banner(
              text: settings.t('demoBanner', {
                'countries': state.degradedCountries.join(', '),
              }),
            ),
          if (state.sourceErrors.isNotEmpty)
            _SourceErrorBanner(errors: state.sourceErrors, settings: settings),
          Expanded(child: _body(state, settings, hidden)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: settings.t('filters'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: () => _openFilters(state),
        child: const Icon(Icons.tune),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _body(AppState state, SettingsState settings, HiddenState hidden) {
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
      hidden,
    );

    if (listings.isEmpty) {
      return Center(child: Text(_emptyLabel(settings)));
    }

    if (_mapMode) {
      final mapCountry = state.filters.countries.isNotEmpty
          ? state.filters.countries.first
          : '';
      return MapView(
        // A fresh key on country/city change forces a clean remount instead
        // of relying on didUpdateWidget to notice and recenter — a country
        // switch was leaving the map showing the old country's tiles.
        key: ValueKey('map-$mapCountry-${state.filters.city}'),
        listings: state.mapListings.isNotEmpty ? state.mapListings : listings,
        center: center,
        centerZoom: _focusListing?.hasLocation == true ? 18 : 6,
        onTapListing: _showMapPreview,
        rates: state.rates,
        displayCurrency: settings.displayCurrency,
        country: mapCountry,
        city: state.filters.city,
        locale: settings.lang,
        onExpand: () => _openFullScreenMap(
          state,
          settings,
          mapCountry,
          state.mapListings.isNotEmpty ? state.mapListings : listings,
          center,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _pullRefresh(state),
      child: Stack(
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
          if (state.loading) ...[
            // Blocks taps on the (still-visible, now stale) list while a
            // reload is in flight, so a tap can't land on a card that's
            // about to be replaced.
            const Positioned.fill(
              child: AbsorbPointer(child: SizedBox.expand()),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          ],
        ],
      ),
    );
  }

  /// Pull-to-refresh replaces the old header refresh button: dragging the
  /// results down shows the platform loader and re-fetches. A fresh
  /// (uncached) re-scrape is used when it isn't cooling down, otherwise this
  /// falls back to a normal re-fetch of the current filters.
  Future<void> _pullRefresh(AppState state) {
    if (!state.loading && !state.reloadAllCoolingDown) return state.reloadAll();
    return state.search();
  }

  /// Restrict the visible listings to the selected quick view (on top of the
  /// active filters/search). "Fresh" keeps only posts from the last 24 hours.
  List<Listing> _applyTab(List<Listing> listings, HiddenState hidden) {
    if (_tab == _ViewTab.hidden) {
      return listings.where((l) => hidden.isHidden(l.id)).toList();
    }
    // Every other view excludes dismissed listings, matching the site's
    // `activeListings` (hidden ones only ever show up under the Hidden tab).
    final active = listings.where((l) => !hidden.isHidden(l.id));
    switch (_tab) {
      case _ViewTab.all:
        return active.toList();
      case _ViewTab.fresh:
        final cutoff = DateTime.now().toUtc().subtract(
              const Duration(hours: 24),
            );
        return active
            .where(
              (l) =>
                  l.createdAt != null && l.createdAt!.toUtc().isAfter(cutoff),
            )
            .toList();
      case _ViewTab.hidden:
        return const []; // unreachable, handled above
    }
  }

  String _emptyLabel(SettingsState settings) => switch (_tab) {
        _ViewTab.fresh => settings.t('noFreshHere'),
        _ViewTab.hidden => settings.t('noHiddenHere'),
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

class _MapListingPreview extends StatefulWidget {
  const _MapListingPreview({
    required this.api,
    required this.initial,
    required this.onOpen,
  });

  final ApiService api;
  final Listing initial;
  final ValueChanged<Listing> onOpen;

  @override
  State<_MapListingPreview> createState() => _MapListingPreviewState();
}

class _MapListingPreviewState extends State<_MapListingPreview> {
  late Listing _listing = widget.initial;
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    final needsHydration = _listing.marketComparison == null ||
        _listing.city.isEmpty ||
        (_listing.photos.isEmpty && _listing.photo == null);
    if (needsHydration) _hydrate();
  }

  Future<void> _hydrate() async {
    if (_hydrating) return;
    _hydrating = true;
    Listing? full;
    try {
      final publicId = _listing.publicId;
      if (publicId != null) {
        full = await widget.api.fetchListingByPublicId(publicId);
      }
    } catch (_) {
      // The preview is already usable from the map point; hydration is best effort.
    }
    if (!mounted) return;
    setState(() {
      if (full != null) _listing = full!;
      _hydrating = false;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Stack(
          children: [
            ListingCard(
              listing: _listing,
              onTap: () => widget.onOpen(_listing),
            ),
            if (_hydrating)
              const Positioned(
                left: 8,
                right: 8,
                top: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      );
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
    // Min/Max are always interpreted in the header's display currency now —
    // no separate currency picker next to the fields.
    final currency = widget.settings.displayCurrency;
    return widget.filters.copyWith(
      query: _query.text.trim(),
      priceMin: min,
      priceMax: max,
      clearPriceMin: min == null,
      clearPriceMax: max == null,
      priceCurrency: currency,
      clearPriceCurrency: currency == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final theme = Theme.of(context);
    final inputTextTheme = theme.textTheme.copyWith(
      bodyLarge: theme.textTheme.bodyLarge?.copyWith(
        fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) - 1.5,
      ),
      titleMedium: theme.textTheme.titleMedium?.copyWith(
        fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) - 1.5,
      ),
    );
    final selectedCountry = widget.filters.countries.isNotEmpty
        ? widget.filters.countries.first
        : null;
    Country? country;
    for (final item in widget.countries) {
      if (item.code == selectedCountry) country = item;
    }
    final cities = withPinnedCities(
      selectedCountry ?? '',
      country?.cities ?? const <String>[],
    );
    final selectedCity =
        cities.contains(widget.filters.city) ? widget.filters.city : null;

    final compactInputTheme = theme.inputDecorationTheme.copyWith(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints.tightFor(height: 42),
      border: const OutlineInputBorder(),
    );
    return Theme(
      data: theme.copyWith(
        textTheme: inputTextTheme,
        inputDecorationTheme: compactInputTheme,
      ),
      child: Material(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            children: [
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 20,
                  ),
                  labelText: s.t('quickSearch'),
                  hintText: s.t('keywordHint'),
                ),
                onChanged: (_) => _schedule(_withTextValues()),
                onSubmitted: (_) =>
                    _schedule(_withTextValues(), immediate: true),
              ),
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Collapsed, this only needs to show which flag is picked —
                  // the full country name still appears once the menu opens,
                  // freeing up width for the (more useful) city search field.
                  SizedBox(
                    width: 76,
                    child: DropdownButtonFormField<String>(
                      value: selectedCountry,
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: s.t('quickCountry'),
                      ),
                      selectedItemBuilder: (context) => widget.countries
                          .map(
                            (item) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                countryFlags[item.code] ?? item.code,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          )
                          .toList(),
                      items: widget.countries
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.code,
                              child: Text(
                                '${countryFlags[item.code] ?? ''} ${s.s.countryName(item.code, item.name)}',
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
                  const SizedBox(width: 5),
                  Expanded(
                    child: SearchableDropdown(
                      key: ValueKey('quick-city-$selectedCountry'),
                      hint: s.t('quickCity'),
                      placeholder: s.t('anyCity'),
                      options: cities,
                      value: selectedCity,
                      labelOf: (city) => country?.cityLabel(city) ?? city,
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
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<AgencyFilter>(
                      value: widget.filters.agency,
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: s.t('quickAgency'),
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
                  const SizedBox(width: 5),
                  Expanded(
                    child: DropdownButtonFormField<_QuickDeal>(
                      value: _quickDealFor(widget.filters),
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(labelText: s.t('dealType')),
                      items: [
                        DropdownMenuItem(
                          value: _QuickDeal.any,
                          child: Text(s.t('any')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.sale,
                          child: Text(s.t('sale')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.longRent,
                          child: Text(s.t('longTerm')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.room,
                          child: Text(s.t('roomOnly')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.shortRent,
                          child: Text(s.t('shortTerm')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _schedule(
                          _withQuickDeal(_withTextValues(), value),
                          immediate: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceMin,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.t('quickPriceMin'),
                        hintText: s.t('minPlaceholder'),
                      ),
                      onChanged: (_) => _schedule(_withTextValues()),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: TextField(
                      controller: _priceMax,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.t('quickPriceMax'),
                        hintText: s.t('maxPlaceholder'),
                      ),
                      onChanged: (_) => _schedule(_withTextValues()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _QuickDeal _quickDealFor(Filters f) {
    if (f.dealType == DealType.longRent && f.roomOnly) return _QuickDeal.room;
    return switch (f.dealType) {
      DealType.any => _QuickDeal.any,
      DealType.sale => _QuickDeal.sale,
      DealType.longRent => _QuickDeal.longRent,
      DealType.shortRent => _QuickDeal.shortRent,
    };
  }

  Filters _withQuickDeal(Filters f, _QuickDeal deal) => switch (deal) {
        _QuickDeal.any => f.copyWith(dealType: DealType.any, roomOnly: false),
        _QuickDeal.sale => f.copyWith(dealType: DealType.sale, roomOnly: false),
        _QuickDeal.longRent => f.copyWith(
            dealType: DealType.longRent,
            roomOnly: false,
          ),
        _QuickDeal.room =>
          f.copyWith(dealType: DealType.longRent, roomOnly: true),
        _QuickDeal.shortRent => f.copyWith(
            dealType: DealType.shortRent,
            roomOnly: false,
          ),
      };
}

/// The quick-filter deal-type segments: room-share rent is stored as
/// `dealType: longRent, roomOnly: true` in [Filters], not its own enum value,
/// so it's surfaced as a distinct option only in this control.
enum _QuickDeal { any, sale, longRent, room, shortRent }

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.state, required this.settings});
  final AppState state;
  final SettingsState settings;

  @override
  Widget build(BuildContext context) {
    final resultsLabel = settings.t('results', {
      'n': '${state.total > 0 ? state.total : state.listings.length}',
    });
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        resultsLabel,
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
