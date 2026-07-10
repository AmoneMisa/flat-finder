import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/listing.dart';
import '../state/favorites.dart';
import '../state/settings.dart';
import '../utils/format.dart';
import '../widgets/listing_card.dart';
import 'listing_detail.dart';

/// Saved listings organized into country → city folders.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  void _open(BuildContext context, Listing l) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: l)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final favorites = context.watch<FavoritesState>();
    final s = settings.s;
    final grouped = favorites.grouped();

    return Scaffold(
      appBar: AppBar(title: Text(s.t('favorites'))),
      body: favorites.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_border, size: 48),
                    const SizedBox(height: 12),
                    Text(s.t('noFavorites'), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                for (final country in grouped.keys)
                  _CountryFolder(
                    country: country,
                    byCity: grouped[country]!,
                    onOpen: (l) => _open(context, l),
                    otherLabel: s.t('otherCity'),
                  ),
              ],
            ),
    );
  }
}

class _CountryFolder extends StatelessWidget {
  const _CountryFolder({
    required this.country,
    required this.byCity,
    required this.onOpen,
    required this.otherLabel,
  });

  final String country;
  final Map<String, List<Listing>> byCity;
  final void Function(Listing) onOpen;
  final String otherLabel;

  @override
  Widget build(BuildContext context) {
    final total = byCity.values.fold<int>(0, (a, b) => a + b.length);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Text(countryFlags[country] ?? '📁',
            style: const TextStyle(fontSize: 22)),
        title: Text(country),
        subtitle: Text('$total'),
        children: [
          for (final city in byCity.keys)
            ExpansionTile(
              tilePadding: const EdgeInsets.only(left: 32, right: 16),
              leading: const Icon(Icons.location_city, size: 20),
              title: Text(city.isEmpty ? otherLabel : city),
              subtitle: Text('${byCity[city]!.length}'),
              children: [
                for (final l in byCity[city]!)
                  ListingCard(listing: l, onTap: () => onOpen(l)),
              ],
            ),
        ],
      ),
    );
  }
}
