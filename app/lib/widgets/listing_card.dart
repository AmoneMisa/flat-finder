import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/listing.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../utils/format.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final rates = context.watch<AppState>().rates;
    final s = settings.s;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 120,
              child: listing.photo != null
                  ? CachedNetworkImage(
                      imageUrl: listing.photo!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const ColoredBox(color: Color(0x11000000)),
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.home_outlined, size: 40),
                    )
                  : const ColoredBox(
                      color: Color(0x11000000),
                      child: Icon(Icons.home_outlined, size: 40),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatPrice(listing,
                                rates: rates,
                                displayCurrency: settings.displayCurrency,
                                s: s),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
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
                    const SizedBox(height: 2),
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('${countryFlags[listing.country] ?? ''} ',
                            style: const TextStyle(fontSize: 13)),
                        Expanded(
                          child: Text(
                            subtitleFor(listing, s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor),
                          ),
                        ),
                      ],
                    ),
                    if (listing.metro != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.subway, size: 12, color: theme.hintColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              listing.metro!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (listing.contact != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.call, size: 12, color: theme.hintColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              listing.contact!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (listing.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 22,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: listing.tags.length > 4 ? 4 : listing.tags.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 4),
                          itemBuilder: (_, i) => _TagChip(text: listing.tags[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
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
