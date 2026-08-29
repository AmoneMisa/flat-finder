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

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
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
    final filters = parseSearchUrl(uri);
    if (filters == null || !mounted) return;
    final state = context.read<AppState>();
    state.updateFilters(filters);
    state.search();
    setState(() => _mapMode = false);
  }

  Future<void> _openFilters(AppState state) async {
    final result = await showModalBottomSheet<Filters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => FilterSheet(initial: state.filters, countries: state.countries),
    );
    if (result != null) {
      state.updateFilters(result);
      await state.search();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openFavorites() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: l)),
    );
  }

  void _showMapPreview(Listing l) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListingCard(listing: l, onTap: () {
        Navigator.pop(context);
        _openListing(l);
      }),
    );
  }

  LatLng _centerFor(AppState state) {
    // "Show on map" from a card takes priority over the country default.
    if (_focusListing?.hasLocation == true) {
      return LatLng(_focusListing!.lat!, _focusListing!.lng!);
    }
    // Center on the first selected country's capital.
    final code = state.filters.countries.isNotEmpty ? state.filters.countries.first : 'RO';
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
            onPressed: () => setState(() => _mapMode = !_mapMode),
          ),
          IconButton(
            tooltip: settings.t('history'),
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: settings.t('favorites'),
            icon: const Icon(Icons.favorite_border),
            onPressed: _openFavorites,
          ),
          IconButton(
            tooltip: settings.t('statistics'),
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => _openStats(state),
          ),
          IconButton(
            tooltip: settings.t('filters'),
            icon: const Icon(Icons.tune),
            onPressed: () => _openFilters(state),
          ),
          IconButton(
            tooltip: settings.t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(state: state, settings: settings),
          _ViewTabBar(
            current: _tab,
            settings: settings,
            onChanged: (t) => setState(() => _tab = t),
          ),
          if (state.degradedCountries.isNotEmpty)
            _Banner(
              text: settings.t('demoBanner', {'countries': state.degradedCountries.join(', ')}),
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
    );
  }

  Widget _body(
      AppState state, SettingsState settings, FavoritesState favorites, HistoryState history) {
    if (state.loading && state.listings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.listings.isEmpty) {
      return _ErrorView(message: state.error!, onRetry: state.search, settings: settings);
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
        listings: listings,
        center: center,
        centerZoom: _focusListing?.hasLocation == true ? 15 : 6,
        onTapListing: _showMapPreview,
        rates: state.rates,
        displayCurrency: settings.displayCurrency,
        country: state.filters.countries.isNotEmpty ? state.filters.countries.first : '',
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
                padding: const EdgeInsets.only(bottom: 90, top: 4),
                itemCount: listings.length,
                itemBuilder: (_, i) {
                  final l = listings[i];
                  return ListingCard(
                      listing: l, onTap: () => _openListing(l), onShowOnMap: () => _showOnMap(l));
                },
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 90),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.82,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: listings.length,
              itemBuilder: (_, i) {
                final l = listings[i];
                return ListingCard(
                    listing: l,
                    grid: true,
                    onTap: () => _openListing(l),
                    onShowOnMap: () => _showOnMap(l));
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
  List<Listing> _applyTab(List<Listing> listings, FavoritesState fav, HistoryState hist) {
    switch (_tab) {
      case _ViewTab.all:
        return listings;
      case _ViewTab.favorites:
        return listings.where((l) => fav.isFavorite(l.id)).toList();
      case _ViewTab.viewed:
        return listings.where((l) => hist.isViewed(l.id)).toList();
      case _ViewTab.fresh:
        final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24));
        return listings
            .where((l) => l.createdAt != null && l.createdAt!.toUtc().isAfter(cutoff))
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
    parts.add(settings.t('results', {'n': '${state.listings.length}'}));
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
          leading: Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
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
                  child: Text(_label(e),
                      style: TextStyle(fontSize: 12, color: Colors.red.shade900)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry, required this.settings});
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
