import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/filters.dart';
import '../models/listing.dart';
import '../state/app_state.dart';
import '../state/favorites.dart';
import '../state/hidden.dart';
import '../state/history.dart';
import '../state/settings.dart';
import '../utils/format.dart';
import '../utils/price_tone.dart';

/// Deal-type badge colours, matching the site's `.flat-card__deal_*` tones.
enum _DealTone { sale, rent, room, shortTerm }

const _dealToneColors = {
  _DealTone.sale: Color(0xFFF58AB5),
  _DealTone.rent: Color(0xFFB79CFF),
  _DealTone.room: Color(0xFF77D9E8),
  _DealTone.shortTerm: Color(0xFFF4C86A),
};

_DealTone? _dealTone(Listing l) {
  if (l.dealType == 'shortRent') return _DealTone.shortTerm;
  if (l.roomOnly) return _DealTone.room;
  if (l.dealType == 'sale') return _DealTone.sale;
  if (l.dealType == 'longRent') return _DealTone.rent;
  return null;
}

String _dealBadgeLabel(AppStrings s, Listing l) {
  // Keep the same precedence and wording as the web cards. A daily room
  // listing remains short-term; otherwise roomOnly is its own transaction.
  if (l.dealType == 'shortRent') return s.t('cardDailyRent');
  if (l.roomOnly) return s.t('cardRoomRent');
  if (l.dealType == 'sale') return s.t('cardSale');
  if (l.dealType == 'longRent') return s.t('cardRent');
  return '';
}

class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.onShowOnMap,
    this.grid = false,
  });

  final Listing listing;
  final VoidCallback onTap;
  final VoidCallback? onShowOnMap;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final appState = context.watch<AppState>();
    final favorites = context.watch<FavoritesState>();
    final history = context.watch<HistoryState>();
    final hidden = context.watch<HiddenState>();
    final s = settings.s;
    final isFav = favorites.isFavorite(listing.id);
    final isViewed = history.isViewed(listing.id);
    final isHidden = hidden.isHidden(listing.id);
    final priceState = listingPriceTone(listing, appState.rates);
    final mobile = !grid && MediaQuery.sizeOf(context).width < 700;

    final dealTone = _dealTone(listing);
    final photo = Stack(
      fit: StackFit.expand,
      children: [
        _CardPhotoCarousel(listing: listing),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: mobile
                    ? const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: [0.52, 0.78, 1],
                        colors: [
                          Colors.transparent,
                          Color(0x660B102A),
                          Color(0xFF0B102A),
                        ],
                      )
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.42, 0.76, 1],
                        colors: [
                          Colors.transparent,
                          Color(0x660B102A),
                          Color(0xFF0B102A),
                        ],
                      ),
              ),
            ),
          ),
        ),
        if (dealTone != null)
          Positioned(
            top: 8,
            left: 8,
            child: _DealBadge(
              tone: dealTone,
              label: _dealBadgeLabel(s, listing),
            ),
          ),
        if (listing.marketComparison?.goodPrice == true)
          Positioned(
            left: 8,
            bottom: 8,
            child: Tooltip(
              message: _goodPriceTitle(listing, s),
              child: _GoodPriceBadge(text: s.t('goodPrice')),
            ),
          ),
        if (listing.potentiallyUnsafe)
          Positioned(
            left: 8,
            bottom: listing.marketComparison?.goodPrice == true ? 40 : 8,
            child: Tooltip(
              message: s.t('potentiallyUnsafeHint'),
              child: _WarningBadge(text: s.t('potentiallyUnsafe')),
            ),
          ),
        if (isViewed)
          Positioned(top: 8, right: 8, child: _ViewedIcon(tooltip: s.t('viewedTag'))),
      ],
    );

    // Map-pin/favorite actions used to float on top of the photo, where they
    // crowded and overlapped the deal badge on the narrow mobile thumbnail
    // (~42% card width). Rendered inline in the meta panel instead, next to
    // the price, where there's always room.
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onShowOnMap != null && listing.hasLocation)
          _CardActionButton(
            icon: Icons.pin_drop_outlined,
            tooltip: s.t('showOnMap'),
            onPressed: onShowOnMap,
          ),
        _CardActionButton(
          icon: isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          tooltip: isHidden ? s.t('restoreListing') : s.t('hideListing'),
          onPressed: () => hidden.toggle(listing),
        ),
        _FavButton(
          isFav: isFav,
          tooltip: isFav ? s.t('removeFavorite') : s.t('addFavorite'),
          onPressed: () => favorites.toggle(listing),
        ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isFav ? 5 : 0,
      shadowColor: isFav ? const Color(0x66E0679A) : Colors.transparent,
      color: const Color(0xFF0B102A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: listing.potentiallyUnsafe
              ? const Color(0x8FF2B86B)
              : isFav
              ? const Color(0x85E0679A)
              : Theme.of(context).dividerColor.withValues(alpha: .65),
        ),
      ),
      margin: grid
          ? const EdgeInsets.all(6)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: InkWell(
        onTap: onTap,
        child: mobile
            ? SizedBox(
                height: 148,
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: constraints.maxWidth * .42, child: photo),
                      Expanded(
                        child: _meta(
                          theme,
                          s,
                          filters: appState.filters,
                          rates: appState.rates,
                          displayCurrency: settings.displayCurrency,
                          priceState: priceState,
                          actions: actions,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  grid
                      ? Expanded(child: photo)
                      : AspectRatio(aspectRatio: 1.5, child: photo),
                  _meta(
                    theme,
                    s,
                    filters: appState.filters,
                    rates: appState.rates,
                    displayCurrency: settings.displayCurrency,
                    priceState: priceState,
                    actions: actions,
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
    required PriceTone priceState,
    required Widget actions,
    bool compact = false,
  }) {
    final badges = _contextBadges(filters, s);
    final location = _locationLabel(s);
    final date = postedLabel(listing.createdAt, s);
    final source = sourceLabel(listing.source, s);

    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(6, 7, 8, 7)
          : const EdgeInsets.fromLTRB(13, 11, 13, 12),
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
            compact: compact,
          ),
          SizedBox(height: compact ? 2 : 6),
          Text(
            listing.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: compact ? 11.5 : 14,
              height: compact ? 1.25 : 1.36,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 1 : 3),
          Text(
            _detailsLabel(s),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontSize: compact ? 9.5 : 12,
              height: 1.25,
            ),
          ),
          if (badges.isNotEmpty) ...[
            SizedBox(height: compact ? 3 : 6),
            SizedBox(
              height: compact ? 20 : 27,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: badges.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (_, i) =>
                    _TagChip(text: badges[i], compact: compact),
              ),
            ),
          ],
          SizedBox(height: compact ? 3 : 8),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: compact ? 10 : 14,
                color: theme.hintColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontSize: compact ? 8.5 : 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                date == null ? source : '$source · $date',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  fontSize: compact ? 8.5 : 11.5,
                ),
              ),
            ],
          ),
          // Actions sit at the very bottom of the card, clear of the photo,
          // badge, and viewed icon so nothing overlaps on narrow mobile cards.
          SizedBox(height: compact ? 4 : 8),
          Align(alignment: Alignment.centerRight, child: actions),
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
      final value = area == area.roundToDouble()
          ? area.toInt().toString()
          : area.toString();
      parts.add('$value m²');
    }
    final floor = floorLabel(listing, s);
    if (floor != null) parts.add(floor);
    return parts.join(' · ');
  }

  String _locationLabel(AppStrings s) {
    final parts = <String>[];
    final city = listing.city.trim();
    if (city.isNotEmpty) parts.add(cityLabel(city, s.lang));
    final district = listing.district?.trim();
    if (district != null && district.isNotEmpty) parts.add(district);
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  List<String> _contextBadges(Filters filters, AppStrings s) {
    final result = <String>[];
    final geoFiltered =
        filters.district.trim().isNotEmpty ||
        filters.metro.trim().isNotEmpty ||
        filters.microdistrict.trim().isNotEmpty ||
        filters.quartal.trim().isNotEmpty ||
        filters.area.trim().isNotEmpty;

    void add(String value) {
      final label = value.trim();
      if (label.isEmpty || result.contains(label)) return;
      result.add(label);
    }

    // Do not repeat a seller value that the user has already selected in filters.
    if (filters.agency == AgencyFilter.any) {
      add(listing.byAgency ? s.t('agency') : s.t('owner'));
    } else if (geoFiltered && listing.rooms != null) {
      // Once a geo facet is fixed by filters, room count is more useful than
      // repeating the selected district/metro on every card.
      add(s.t('roomsN', {'n': '${listing.rooms}'}));
    } else {
      // Seller is already fixed: use the most useful available geo context.
      final district = listing.district?.trim();
      final metro = listing.metro?.trim();
      if (district != null && district.isNotEmpty) {
        add(district);
      } else if (metro != null && metro.isNotEmpty) {
        add(metro);
      } else if (listing.nearby.isNotEmpty) {
        add(s.nearbyLabel(listing.nearby.first));
      }
    }

    if (listing.commission == false) {
      add(s.t('badgeNoCommission'));
    } else if (listing.commissionPercent != null) {
      add(s.t('badgeCommissionPercent', {'n': '${listing.commissionPercent}'}));
    } else if (listing.commission == true) {
      add(s.t('badgeCommission'));
    }
    if (listing.newBuilding == true) add(s.t('badgeNew'));
    if (listing.furnished == true) add(s.t('badgeFurnished'));
    if (listing.airConditioner == true) add(s.t('badgeAC'));
    if (listing.balcony == true) add(s.t('badgeBalcony'));
    if (listing.parking == true) add(s.t('badgeParking'));
    if (listing.elevator == true) add(s.t('badgeElevator'));
    if (listing.internet == true) add(s.t('badgeInternet'));
    if (listing.negotiable == true) add(s.t('badgeNegotiable'));
    if (listing.petsAllowed == true) add(s.t('badgePet'));
    if (listing.childrenAllowed == true) add(s.t('badgeChildren'));
    if (listing.communalSeparated == false) add(s.t('badgeUtilIncl'));
    if (listing.deposit == true) add(s.t('badgeDeposit'));
    if (listing.audience == 'family') add(s.t('badgeFamily'));
    if (listing.audience == 'women') add(s.t('badgeWomen'));
    if (listing.audience == 'men') add(s.t('badgeMen'));

    // Append normalized source tags after the structured badges.
    for (final raw in listing.tags) {
      final label = tagLabel(raw, s).trim();
      if (label.isEmpty || _isRedundantTag(label, s, result)) continue;
      add(label);
    }
    return result;
  }

  bool _isRedundantTag(String label, AppStrings s, List<String> current) {
    final lower = label.toLowerCase();
    final blocked = <String>{
      s.t('owner').toLowerCase(),
      s.t('agency').toLowerCase(),
      if (listing.rooms != null)
        s.t('roomsN', {'n': '${listing.rooms}'}).toLowerCase(),
      listing.city.toLowerCase(),
      if (listing.district != null) listing.district!.toLowerCase(),
      if (listing.metro != null) listing.metro!.toLowerCase(),
    };
    return blocked.contains(lower) ||
        current.any((e) => e.toLowerCase() == lower);
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.listing,
    required this.rates,
    required this.displayCurrency,
    required this.state,
    required this.s,
    this.compact = false,
  });

  final Listing listing;
  final Map<String, double> rates;
  final String? displayCurrency;
  final PriceTone state;
  final AppStrings s;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = priceToneColor(state);
    if (listing.price == null) {
      return Text(
        s.t('priceOnRequest'),
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: compact ? 14 : 18,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    final f = NumberFormat.decimalPattern();
    final native = '${f.format(listing.price!.round())} ${listing.currency}'
        .trim();
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
              color: color,
              fontSize: compact ? 14 : 18,
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
                fontSize: compact ? 9.5 : 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _goodPriceTitle(Listing listing, AppStrings s) {
  final comparison = listing.marketComparison;
  final median = comparison?.medianUsd;
  if (median == null) return s.t('goodPrice');
  final medianLabel = median == median.roundToDouble()
      ? median.toInt().toString()
      : median.toStringAsFixed(2);
  return s.t('goodPriceCompared', {
    'count': '${comparison?.comparableCount ?? 0}',
    'median': medianLabel,
  });
}

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
        border: Border.all(
          color: BrandColors.toneGreen.withValues(alpha: 0.75),
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_down, color: tint, size: 12),
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

class _WarningBadge extends StatelessWidget {
  const _WarningBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: BrandColors.toneOrange.withValues(alpha: .18),
      border: Border.all(color: BrandColors.toneOrange.withValues(alpha: .75)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: BrandColors.toneOrange,
          size: 12,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: BrandColors.toneOrange,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
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
                  const Icon(
                    Icons.photo_library_outlined,
                    color: Colors.white,
                    size: 11,
                  ),
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

/// A generic photo-overlay action button — same 32px dark square style as
/// [_FavButton] (matches the site's `.flat-card__action`), for actions that
/// don't need a filled/outline toggle state.
class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

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
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

/// Deal-type label on the photo's top-left corner, matching the site's
/// `.flat-card__deal` — a dark pill outlined and tinted per [_DealTone].
class _DealBadge extends StatelessWidget {
  const _DealBadge({required this.tone, required this.label});
  final _DealTone tone;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final color = _dealToneColors[tone]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1128),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
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
        child: const Icon(
          Icons.visibility_outlined,
          color: Colors.white70,
          size: 17,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text, this.compact = false});
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 8.5 : 10.5,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
