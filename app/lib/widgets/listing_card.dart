import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/filters.dart';
import '../models/listing.dart';
import '../state/app_state.dart';
import '../state/favorites.dart';
import '../state/history.dart';
import '../state/settings.dart';
import '../utils/format.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.grid = false,
  });

  final Listing listing;
  final VoidCallback onTap;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final appState = context.watch<AppState>();
    final favorites = context.watch<FavoritesState>();
    final history = context.watch<HistoryState>();
    final s = settings.s;
    final isFav = favorites.isFavorite(listing.id);
    final isViewed = history.isViewed(listing.id);
    final priceState = _priceState(listing, appState.rates);

    final photo = Stack(
      fit: StackFit.expand,
      children: [
        _CardPhotoCarousel(listing: listing),
        if (listing.marketComparison?.goodPrice == true)
          Positioned(
            left: 8,
            bottom: 8,
            child: _GoodPriceBadge(text: _goodPriceLabel(s)),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: _FavButton(
            isFav: isFav,
            tooltip: isFav ? s.t('removeFavorite') : s.t('addFavorite'),
            onPressed: () => favorites.toggle(listing),
          ),
        ),
        if (isViewed)
          Positioned(
            top: 8,
            right: 46,
            child: _ViewedIcon(tooltip: s.t('viewedTag')),
          ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isFav ? 8 : null,
      shadowColor: isFav ? Colors.pink : null,
      margin: grid
          ? const EdgeInsets.all(6)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            grid
                ? Expanded(child: photo)
                : AspectRatio(aspectRatio: 16 / 8, child: photo),
            _meta(
              theme,
              s,
              filters: appState.filters,
              rates: appState.rates,
              displayCurrency: settings.displayCurrency,
              priceState: priceState,
              compact: grid,
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(
    ThemeData theme,
    AppStrings s, {
    required Filters filters,
    required Map<String, double> rates,
    required String? displayCurrency,
    required _PriceState priceState,
    bool compact = false,
  }) {
    final badges = _contextBadges(filters, s);
    final location = _locationLabel();
    final date = postedLabel(listing.createdAt, s);
    final source = sourceLabel(listing.source, s);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, compact ? 8 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PriceLine(
            listing: listing,
            rates: rates,
            displayCurrency: displayCurrency,
            state: priceState,
            s: s,
          ),
          const SizedBox(height: 8),
          Text(
            listing.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _detailsLabel(s),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: badges.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (_, i) => _TagChip(text: badges[i]),
              ),
            ),
          ],
          const SizedBox(height: 9),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.35)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 14, color: theme.hintColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                date == null ? source : '$source · $date',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _detailsLabel(AppStrings s) {
    final parts = <String>[];
    if (listing.rooms != null) {
      parts.add(s.t('roomsN', {'n': '${listing.rooms}'}));
    }
    if (listing.areaSqm != null) {
      final area = listing.areaSqm!;
      final value = area == area.roundToDouble() ? area.toInt().toString() : area.toString();
      parts.add('$value m²');
    }
    final floor = floorLabel(listing, s);
    if (floor != null) parts.add(floor);
    return parts.join(' · ');
  }

  String _locationLabel() {
    final parts = <String>[];
    if (listing.city.trim().isNotEmpty) parts.add(listing.city.trim());
    final district = listing.district?.trim();
    if (district != null && district.isNotEmpty) parts.add(district);
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  List<String> _contextBadges(Filters filters, AppStrings s) {
    final result = <String>[];
    final geoFiltered = filters.district.trim().isNotEmpty || filters.metro.trim().isNotEmpty;

    // Do not repeat a seller value that the user has already selected in filters.
    if (filters.agency == AgencyFilter.any) {
      result.add(listing.byAgency ? s.t('agency') : s.t('owner'));
    } else if (geoFiltered && listing.rooms != null) {
      // Once a geo facet is fixed by filters, room count is more useful than
      // repeating the selected district/metro on every card.
      result.add(s.t('roomsN', {'n': '${listing.rooms}'}));
    } else {
      // Seller is already fixed: use the most useful available geo context.
      final district = listing.district?.trim();
      final metro = listing.metro?.trim();
      if (district != null && district.isNotEmpty) {
        result.add(district);
      } else if (metro != null && metro.isNotEmpty) {
        result.add(metro);
      } else if (listing.nearby.isNotEmpty) {
        result.add(s.nearbyLabel(listing.nearby.first));
      }
    }

    // Keep cards compact: add at most two useful, non-duplicating listing tags.
    for (final raw in listing.tags) {
      if (result.length >= 3) break;
      final label = tagLabel(raw, s).trim();
      if (label.isEmpty || _isRedundantTag(label, s, result)) continue;
      result.add(label);
    }
    return result;
  }

  bool _isRedundantTag(String label, AppStrings s, List<String> current) {
    final lower = label.toLowerCase();
    final blocked = <String>{
      s.t('owner').toLowerCase(),
      s.t('agency').toLowerCase(),
      if (listing.rooms != null) s.t('roomsN', {'n': '${listing.rooms}'}).toLowerCase(),
      listing.city.toLowerCase(),
      if (listing.district != null) listing.district!.toLowerCase(),
      if (listing.metro != null) listing.metro!.toLowerCase(),
    };
    return blocked.contains(lower) || current.any((e) => e.toLowerCase() == lower);
  }
}

enum _PriceTier { low, belowAverage, average, high, veryHigh, unknown }

class _PriceState {
  const _PriceState(this.tier, this.ratio);
  final _PriceTier tier;
  final double? ratio;

  // whiteslove.me's own `--flat-tone-*` status palette (green/yellow/orange/
  // red), so a listing's price tier reads with the same colors as the site.
  Color get color => switch (tier) {
        _PriceTier.low => BrandColors.toneGreen,
        _PriceTier.belowAverage =>
          Color.lerp(BrandColors.toneGreen, BrandColors.toneYellow, 0.5)!,
        _PriceTier.average => BrandColors.textPrimary,
        _PriceTier.high => BrandColors.toneOrange,
        _PriceTier.veryHigh => BrandColors.toneRed,
        _PriceTier.unknown => BrandColors.textMuted,
      };
}

_PriceState _priceState(Listing listing, Map<String, double> rates) {
  final price = listing.price?.toDouble();
  final median = listing.marketComparison?.medianUsd?.toDouble();
  final rate = rates[listing.currency];
  if (price == null || median == null || median <= 0 || rate == null || rate <= 0) {
    return const _PriceState(_PriceTier.unknown, null);
  }
  final ratio = (price / rate) / median;
  if (ratio <= 0.80) return _PriceState(_PriceTier.low, ratio);
  if (ratio < 0.95) return _PriceState(_PriceTier.belowAverage, ratio);
  if (ratio <= 1.05) return _PriceState(_PriceTier.average, ratio);
  if (ratio <= 1.20) return _PriceState(_PriceTier.high, ratio);
  return _PriceState(_PriceTier.veryHigh, ratio);
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.listing,
    required this.rates,
    required this.displayCurrency,
    required this.state,
    required this.s,
  });

  final Listing listing;
  final Map<String, double> rates;
  final String? displayCurrency;
  final _PriceState state;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    if (listing.price == null) {
      return Text(
        s.t('priceOnRequest'),
        maxLines: 1,
        style: TextStyle(color: state.color, fontSize: 18, fontWeight: FontWeight.w800),
      );
    }

    final f = NumberFormat.decimalPattern();
    final native = '${f.format(listing.price!.round())} ${listing.currency}'.trim();
    String? secondary;
    final target = displayCurrency;
    final fromRate = rates[listing.currency];
    final targetRate = target == null ? null : rates[target];
    if (target != null &&
        target != listing.currency &&
        fromRate != null &&
        fromRate > 0 &&
        targetRate != null &&
        targetRate > 0) {
      final converted = listing.price! * targetRate / fromRate;
      secondary = '≈ ${f.format(converted.round())} $target';
    }

    return Row(
      children: [
        Flexible(
          child: Text(
            native,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: state.color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (secondary != null) ...[
          const SizedBox(width: 7),
          Text('·', style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

String _goodPriceLabel(AppStrings s) => s.lang == 'ru' ? 'Хорошая цена' : 'Good price';

class _GoodPriceBadge extends StatelessWidget {
  const _GoodPriceBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tint = Color.lerp(BrandColors.toneGreen, Colors.white, 0.25)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: BrandColors.toneGreen.withValues(alpha: 0.16),
        border: Border.all(color: BrandColors.toneGreen.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.savings_outlined, color: tint, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: tint,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPhotoCarousel extends StatefulWidget {
  const _CardPhotoCarousel({required this.listing});
  final Listing listing;

  @override
  State<_CardPhotoCarousel> createState() => _CardPhotoCarouselState();
}

class _CardPhotoCarouselState extends State<_CardPhotoCarousel> {
  final _controller = PageController();
  int _index = 0;

  List<String> get _photos {
    if (widget.listing.photos.isNotEmpty) return widget.listing.photos;
    final p = widget.listing.photo;
    return p != null ? [p] : const [];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget get _placeholder => const ColoredBox(
        color: Color(0x11000000),
        child: Icon(Icons.home_outlined, size: 56, color: Colors.black26),
      );

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    if (photos.isEmpty) return _placeholder;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => CachedNetworkImage(
            imageUrl: photos[i],
            fit: BoxFit.cover,
            placeholder: (_, __) => const ColoredBox(color: Color(0x11000000)),
            errorWidget: (_, __, ___) => _placeholder,
          ),
        ),
        if (photos.length > 1)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined, color: Colors.white, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    '${_index + 1}/${photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FavButton extends StatelessWidget {
  const _FavButton({
    required this.isFav,
    required this.tooltip,
    required this.onPressed,
  });

  final bool isFav;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 19,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
        onPressed: onPressed,
        icon: Icon(
          isFav ? Icons.favorite : Icons.favorite_border,
          color: isFav ? Colors.redAccent : Colors.white,
        ),
      ),
    );
  }
}

class _ViewedIcon extends StatelessWidget {
  const _ViewedIcon({required this.tooltip});
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.visibility_outlined, color: Colors.white70, size: 17),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
