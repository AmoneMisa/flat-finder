import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/listing.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../utils/format.dart';

class ListingDetailScreen extends StatelessWidget {
  const ListingDetailScreen({super.key, required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final rates = context.watch<AppState>().rates;
    final s = settings.s;
    return Scaffold(
      appBar: AppBar(title: Text('${countryFlags[listing.country] ?? ''} ${listing.city}')),
      body: ListView(
        children: [
          if (listing.photo != null)
            CachedNetworkImage(
              imageUrl: listing.photo!,
              height: 240,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  const SizedBox(height: 240, child: Icon(Icons.home, size: 80)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    formatPrice(listing,
                        rates: rates, displayCurrency: settings.displayCurrency, s: s),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(listing.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(Icons.home_work_outlined, propertyLabel(listing.propertyType, s)),
                    if (dealTypeLabel(listing.dealType, s) != null)
                      _chip(Icons.sell_outlined, dealTypeLabel(listing.dealType, s)!),
                    _chip(
                      listing.byAgency ? Icons.business : Icons.person,
                      listing.byAgency ? s.t('agency') : s.t('privateOwner'),
                    ),
                    if (listing.rooms != null)
                      _chip(Icons.meeting_room_outlined, s.t('roomsN', {'n': '${listing.rooms}'})),
                    if (listing.bedrooms != null)
                      _chip(Icons.bed_outlined, s.t('bedroomsN', {'n': '${listing.bedrooms}'})),
                    if (listing.areaSqm != null)
                      _chip(Icons.square_foot, '${listing.areaSqm} m²'),
                    if (floorLabel(listing, s) != null)
                      _chip(Icons.stairs_outlined, floorLabel(listing, s)!),
                    if (listing.buildingYear != null)
                      _chip(Icons.calendar_today_outlined,
                          s.t('yearBuiltN', {'n': '${listing.buildingYear}'})),
                    if (audienceLabel(listing.audience, s) != null)
                      _chip(Icons.groups_outlined, audienceLabel(listing.audience, s)!),
                    if (listing.district != null)
                      _chip(Icons.map_outlined, listing.district!),
                    if (listing.metro != null)
                      _chip(Icons.subway_outlined, listing.metro!),
                    _chip(Icons.source_outlined, sourceLabel(listing.source, s)),
                  ],
                ),
                if (listing.nearby.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(s.t('nearby'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.nearby
                        .map((n) => Chip(
                              avatar: const Icon(Icons.place_outlined, size: 18),
                              label: Text(n),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: theme.colorScheme.secondaryContainer,
                            ))
                        .toList(),
                  ),
                ],
                if (listing.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(s.t('tags'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.tags
                        .map((t) => Chip(
                              label: Text(t),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: theme.colorScheme.primaryContainer,
                            ))
                        .toList(),
                  ),
                ],
                if (listing.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(s.t('description'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(listing.description, style: theme.textTheme.bodyMedium),
                ],
                if (listing.contact != null) ...[
                  const SizedBox(height: 20),
                  Text(s.t('contact'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(_contactIcon(listing.contact!), size: 18, color: theme.hintColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(listing.contact!, style: theme.textTheme.bodyMedium),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final uri = _contactUri(listing.contact!);
                          if (uri != null) {
                            launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: Icon(
                            listing.contact!.startsWith('@') ? Icons.send : Icons.call,
                            size: 18),
                        label: Text(
                            listing.contact!.startsWith('@') ? s.t('message') : s.t('call')),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: listing.url.isEmpty
                      ? null
                      : () => launchUrl(Uri.parse(listing.url),
                          mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(s.t('openOriginal')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
      );

  IconData _contactIcon(String contact) =>
      contact.startsWith('@') ? Icons.alternate_email : Icons.call;

  /// A @handle opens the Telegram profile; a phone number opens the dialer.
  Uri? _contactUri(String contact) {
    if (contact.startsWith('@')) {
      return Uri.parse('https://t.me/${contact.substring(1)}');
    }
    final digits = contact.replaceAll(RegExp(r'[^\d+]'), '');
    return digits.isEmpty ? null : Uri.parse('tel:$digits');
  }
}
