import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
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

  /// When true the card is laid out for a fixed-height grid cell: the photo
  /// flexes to fill the cell and the meta section is kept compact so nothing
  /// overflows. When false it renders as a full-width list card.
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final rates = context.watch<AppState>().rates;
    final favorites = context.watch<FavoritesState>();
    final s = settings.s;
    final isFav = favorites.isFavorite(listing.id);
    final isViewed = context.watch<HistoryState>().isViewed(listing.id);

    // Prominent photo with the price and badges overlaid on a scrim.
    final photo = Stack(
      fit: StackFit.expand,
      children: [
        _CardPhotoCarousel(listing: listing),
        // Bottom gradient so the white price text stays readable.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.center,
              colors: [Color(0xB3000000), Color(0x00000000)],
            ),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 8,
          right: 10,
          child: Text(
            formatPrice(listing,
                rates: rates, displayCurrency: settings.displayCurrency, s: s),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ),
        Positioned(
          top: 4,
          left: 4,
          child: _FavButton(
            isFav: isFav,
            tooltip: isFav ? s.t('removeFavorite') : s.t('addFavorite'),
            onPressed: () => favorites.toggle(listing),
          ),
        ),
        if (isViewed)
          Positioned(
            top: 44,
            left: 6,
            child: _ViewedTag(text: s.t('viewedTag')),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              if (dealTypeLabel(listing.dealType, s) != null) ...[
                _Badge(
                  text: dealTypeLabel(listing.dealType, s)!,
                  color: theme.colorScheme.tertiaryContainer,
                ),
                const SizedBox(width: 4),
              ],
              _Badge(
                text: sourceLabel(listing.source, s),
                color: theme.colorScheme.secondaryContainer,
              ),
            ],
          ),
        ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      // Favorite listings get a soft pink glow so they stand out in the list.
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
            grid ? _meta(theme, s, compact: true) : _meta(theme, s),
          ],
        ),
      ),
    );
  }

  /// Title, location subtitle and (in list mode) the extra icon lines + tags.
  Widget _meta(ThemeData theme, AppStrings s, {bool compact = false}) => Padding(
        padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, compact ? 8 : 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              listing.title,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style:
                  theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${countryFlags[listing.country] ?? ''} ',
                    style: const TextStyle(fontSize: 14)),
                Expanded(
                  child: Text(
                    subtitleFor(listing, s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
              ],
            ),
            if (!compact) ...[
              if (postedLabel(listing.createdAt, s) != null)
                _iconLine(theme, Icons.schedule, postedLabel(listing.createdAt, s)!),
              if (listing.metro != null)
                _iconLine(theme, Icons.subway, listing.metro!),
              if (listing.nearby.isNotEmpty)
                _iconLine(theme, Icons.place_outlined, listing.nearby.join(' · ')),
              if (listing.contact != null)
                _iconLine(theme, Icons.call, listing.contact!),
              if (listing.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 24,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: listing.tags.length > 6 ? 6 : listing.tags.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (_, i) => _TagChip(text: tagLabel(listing.tags[i], s)),
                  ),
                ),
              ],
            ],
          ],
        ),
      );

  /// A single small icon + text row (metro, nearby landmarks, contact, …).
  Widget _iconLine(ThemeData theme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 13, color: theme.hintColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
          ],
        ),
      );
}

/// Swipeable photo strip filling its parent, with a "current/total" counter
/// badge when the listing has more than one photo. Falls back to a neutral
/// home placeholder when there are no photos.
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined,
                      color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text('${_index + 1}/${photos.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Heart toggle overlaid on a card photo. Uses a dark scrim so it stays visible
/// over any image; filled red when the listing is saved.
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
      color: Colors.black38,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
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

/// "Already viewed" marker overlaid on the card photo, shown once the listing
/// has been opened at least once.
class _ViewedTag extends StatelessWidget {
  const _ViewedTag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility, color: Colors.white70, size: 12),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
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
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
