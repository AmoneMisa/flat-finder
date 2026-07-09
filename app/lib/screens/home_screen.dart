import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/filters.dart';
import '../models/listing.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../utils/format.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/listing_card.dart';
import '../widgets/map_view.dart';
import 'listing_detail.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _mapMode = false;

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
    // Center on the first selected country's capital.
    final code = state.filters.countries.isNotEmpty ? state.filters.countries.first : 'RO';
    final c = state.countryByCode(code);
    if (c != null) return LatLng(c.centerLat, c.centerLng);
    return const LatLng(45, 30);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('appTitle')),
        actions: [
          IconButton(
            tooltip: _mapMode ? settings.t('listView') : settings.t('mapView'),
            icon: Icon(_mapMode ? Icons.view_list : Icons.map_outlined),
            onPressed: () => setState(() => _mapMode = !_mapMode),
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
          if (state.degradedCountries.isNotEmpty)
            _Banner(
              text: settings.t('demoBanner', {'countries': state.degradedCountries.join(', ')}),
            ),
          Expanded(child: _body(state, settings)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openFilters(state),
        icon: const Icon(Icons.tune),
        label: Text(settings.t('filters')),
      ),
    );
  }

  Widget _body(AppState state, SettingsState settings) {
    if (state.loading && state.listings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.listings.isEmpty) {
      return _ErrorView(message: state.error!, onRetry: state.search, settings: settings);
    }
    if (state.listings.isEmpty) {
      return Center(child: Text(settings.t('noListings')));
    }

    if (_mapMode) {
      return MapView(
        listings: state.listings,
        center: _centerFor(state),
        onTapListing: _showMapPreview,
      );
    }
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 90, top: 4),
          itemCount: state.listings.length,
          itemBuilder: (_, i) {
            final l = state.listings[i];
            return ListingCard(listing: l, onTap: () => _openListing(l));
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
