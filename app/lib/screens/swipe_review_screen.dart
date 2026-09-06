import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/review_strings.dart';
import '../models/filters.dart';
import '../models/listing.dart';
import '../models/listing_identity.dart';
import '../state/app_state.dart';
import '../state/favorites.dart';
import '../state/hidden.dart';
import '../state/presets.dart';
import '../state/settings.dart';
import '../state/sorted.dart';
import '../widgets/listing_card.dart';
import 'listing_detail.dart';

/// Dating-style review for the currently selected search result set.
class SwipeReviewScreen extends StatefulWidget {
  const SwipeReviewScreen({super.key, required this.listings});

  final List<Listing> listings;

  @override
  State<SwipeReviewScreen> createState() => _SwipeReviewScreenState();
}

class _SwipeReviewScreenState extends State<SwipeReviewScreen> {
  var _index = 0;

  FilterPreset? _matchingPreset(Filters filters) {
    final encoded = jsonEncode(filters.toJson());
    for (final preset in context.read<PresetsState>().presets) {
      if (jsonEncode(preset.filters.toJson()) == encoded) return preset;
    }
    return null;
  }

  _SortTarget _sortTarget(Listing listing) {
    final state = context.read<AppState>();
    final settings = context.read<SettingsState>();
    final filters = state.filters;
    final preset = _matchingPreset(filters);

    if (preset != null) {
      return _SortTarget(
        id: 'preset:${preset.id}',
        title: '${preset.name} · ${settings.s.presetLabel}',
        isPreset: true,
        presetName: preset.name,
      );
    }

    final country = state.countryByCode(listing.country);
    final parts = <String>[];
    final countryName = country == null
        ? listing.country
        : settings.s.countryName(country.code, country.name);
    if (countryName.trim().isNotEmpty) parts.add(countryName.trim());

    final city = listing.city.trim();
    if (city.isNotEmpty) parts.add(country?.cityLabel(city) ?? city);

    final filtersApplyToListing = filters.countries.contains(listing.country) &&
        (filters.city.isEmpty || filters.city == listing.city);
    if (filtersApplyToListing) {
      void add(String value) {
        final clean = value.trim();
        if (clean.isNotEmpty && !parts.contains(clean)) parts.add(clean);
      }

      switch (filters.dealType) {
        case DealType.sale:
          add(settings.t('sale'));
        case DealType.longRent:
          add(filters.roomOnly
              ? settings.t('cardRoomRent')
              : settings.t('longRentLong'));
        case DealType.shortRent:
          add(settings.t('shortRentLong'));
        case DealType.any:
          break;
      }

      switch (filters.agency) {
        case AgencyFilter.owner:
          add(settings.t('owner'));
        case AgencyFilter.agency:
          add(settings.t('agency'));
        case AgencyFilter.any:
          break;
      }

      for (final value in [
        filters.district,
        filters.microdistrict,
        filters.quartal,
        filters.area,
      ]) {
        add(value);
      }
      for (final station in filters.metro) {
        add(station);
      }

      String range(num? min, num? max, String unit) {
        if (min != null && max != null)
          return '${min.toString()}–${max.toString()} $unit';
        if (min != null) return '≥ ${min.toString()} $unit';
        if (max != null) return '≤ ${max.toString()} $unit';
        return '';
      }

      final roomRange = range(
        filters.roomsMin,
        filters.roomsMax,
        settings.s.roomsUnitShort,
      );
      add(roomRange);

      final priceCurrency = filters.priceCurrency ?? listing.currency;
      add(range(filters.priceMin, filters.priceMax, priceCurrency));

      if (filters.pets) {
        add(settings.t('badgePet'));
      }
      if (filters.children) {
        add(settings.t('badgeChildren'));
      }
      if (filters.withPhotos) {
        add(settings.t('withPhotos'));
      }
      if (filters.query.trim().isNotEmpty) add('“${filters.query.trim()}”');
      for (final amenity in filters.amenities.toList()..sort()) {
        add(amenity);
      }
    }

    final title = parts.isEmpty ? settings.s.sortedTitle : parts.join(' · ');
    final scope = filtersApplyToListing ? jsonEncode(filters.toJson()) : '';
    return _SortTarget(
      id: 'filters:${listing.country}:${listing.city}:$scope',
      title: title,
    );
  }

  Future<void> _decide(DismissDirection direction) async {
    if (_index >= widget.listings.length) return;
    final listing = widget.listings[_index];

    switch (direction) {
      case DismissDirection.startToEnd:
        // Explicitly: swipe RIGHT => sorted/saved.
        final target = _sortTarget(listing);
        await context.read<SortedState>().add(
              listing,
              collectionId: target.id,
              collectionTitle: target.title,
              isPreset: target.isPreset,
              presetName: target.presetName,
            );
      case DismissDirection.endToStart:
        // Explicitly: swipe LEFT => hidden/dismissed.
        final hidden = context.read<HiddenState>();
        if (!hidden.isHidden(listing)) await hidden.toggle(listing);
      default:
        return;
    }

    // Review is fed from saved selections. Once the apartment is classified it
    // must leave the source list instead of remaining there to be reviewed again.
    await context.read<FavoritesState>().remove(listing);

    if (!mounted) return;
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final remaining = widget.listings.length - _index;
    return Scaffold(
      appBar: AppBar(
        title: Text(settings.s.reviewSelectionTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: Text('$remaining')),
          ),
        ],
      ),
      body: SafeArea(
        child: remaining <= 0
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.done_all, size: 56),
                    const SizedBox(height: 12),
                    Text(settings.s.selectionReviewed),
                  ],
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text(
                      settings.s.swipeReviewHint,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Dismissible(
                      key: ValueKey(listingKey(widget.listings[_index])),
                      direction: DismissDirection.horizontal,
                      confirmDismiss: (direction) async {
                        await _decide(direction);
                        return false;
                      },
                      background: _DecisionBackground(
                        alignment: Alignment.centerLeft,
                        color: const Color(0xFF159957),
                        icon: Icons.done_all,
                        label: settings.s.sortAction,
                      ),
                      secondaryBackground: _DecisionBackground(
                        alignment: Alignment.centerRight,
                        color: const Color(0xFFB23A48),
                        icon: Icons.visibility_off,
                        label: settings.t('hideListing'),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        // ListingCard normally becomes a 148 px horizontal
                        // summary on a phone. Swipe review intentionally keeps
                        // the complete vertical card so nothing is lost while
                        // deciding.
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            size: Size(
                              720,
                              MediaQuery.sizeOf(context).height,
                            ),
                          ),
                          child: ListingCard(
                            listing: widget.listings[_index],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ListingDetailScreen(
                                  listing: widget.listings[_index],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FloatingActionButton(
                          heroTag: 'swipe-hide',
                          backgroundColor: const Color(0xFFB23A48),
                          onPressed: () => _decide(DismissDirection.endToStart),
                          child: const Icon(Icons.close),
                        ),
                        FloatingActionButton(
                          heroTag: 'swipe-save',
                          backgroundColor: const Color(0xFF159957),
                          onPressed: () => _decide(DismissDirection.startToEnd),
                          child: const Icon(Icons.done_all),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SortTarget {
  const _SortTarget({
    required this.id,
    required this.title,
    this.isPreset = false,
    this.presetName,
  });

  final String id;
  final String title;
  final bool isPreset;
  final String? presetName;
}

class _DecisionBackground extends StatelessWidget {
  const _DecisionBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        color: color,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 38),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
}
