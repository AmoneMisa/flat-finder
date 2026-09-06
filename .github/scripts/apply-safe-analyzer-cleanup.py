from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


def patch(path: str, replacements: list[tuple[str, str, str]]) -> None:
    p = Path(path)
    text = p.read_text()
    for old, new, label in replacements:
        text = replace_once(text, old, new, label)
    p.write_text(text)


patch('app/lib/models/filters.dart', [
    ("""    if (maxAgeDays != null && maxAgeDays! > 0)
      p['maxAgeDays'] = maxAgeDays.toString();
""", """    if (maxAgeDays != null && maxAgeDays! > 0) {
      p['maxAgeDays'] = maxAgeDays.toString();
    }
""", 'filters max age braces'),
    ("""    if (nearbyKind != null && nearbyKind!.isNotEmpty)
      p['nearbyKind'] = nearbyKind!;
""", """    if (nearbyKind != null && nearbyKind!.isNotEmpty) {
      p['nearbyKind'] = nearbyKind!;
    }
""", 'filters nearby braces'),
    ("""    if (microdistrict.trim().isNotEmpty)
      p['microdistrict'] = microdistrict.trim();
""", """    if (microdistrict.trim().isNotEmpty) {
      p['microdistrict'] = microdistrict.trim();
    }
""", 'filters microdistrict braces'),
])

patch('app/lib/screens/listing_detail.dart', [
    ("""    if (listing.rooms != null)
      info.add(s.t('roomsN', {'n': '${listing.rooms}'}));
""", """    if (listing.rooms != null) {
      info.add(s.t('roomsN', {'n': '${listing.rooms}'}));
    }
""", 'detail rooms braces'),
    ("""    if (listing.publicId != null)
      b.writeln(buildListingWebShareUrl(listing.publicId!));
""", """    if (listing.publicId != null) {
      b.writeln(buildListingWebShareUrl(listing.publicId!));
    }
""", 'detail public id braces'),
    ("""  if (value.isEmpty || value.startsWith('@') || value.contains('+'))
    return value;
""", """  if (value.isEmpty || value.startsWith('@') || value.contains('+')) {
    return value;
  }
""", 'detail contact braces'),
])

patch('app/lib/screens/swipe_review_screen.dart', [
    ("""      String range(num? min, num? max, String unit) {
        if (min != null && max != null)
          return '${min.toString()}–${max.toString()} $unit';
        if (min != null) return '≥ ${min.toString()} $unit';
        if (max != null) return '≤ ${max.toString()} $unit';
        return '';
      }
""", """      String range(num? min, num? max, String unit) {
        if (min != null && max != null) {
          return '${min.toString()}–${max.toString()} $unit';
        }
        if (min != null) return '≥ ${min.toString()} $unit';
        if (max != null) return '≤ ${max.toString()} $unit';
        return '';
      }
""", 'swipe range braces'),
    ("""  Future<void> _decide(DismissDirection direction) async {
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
""", """  Future<void> _decide(DismissDirection direction) async {
    if (_index >= widget.listings.length) return;
    final listing = widget.listings[_index];
    final sorted = context.read<SortedState>();
    final hidden = context.read<HiddenState>();
    final favorites = context.read<FavoritesState>();

    switch (direction) {
      case DismissDirection.startToEnd:
        // Explicitly: swipe RIGHT => sorted/saved.
        final target = _sortTarget(listing);
        await sorted.add(
          listing,
          collectionId: target.id,
          collectionTitle: target.title,
          isPreset: target.isPreset,
          presetName: target.presetName,
        );
      case DismissDirection.endToStart:
        // Explicitly: swipe LEFT => hidden/dismissed.
        if (!hidden.isHidden(listing)) {
          await hidden.toggle(listing);
        }
      default:
        return;
    }

    // Review is fed from saved selections. Once the apartment is classified it
    // must leave the source list instead of remaining there to be reviewed again.
    await favorites.remove(listing);

    if (!mounted) return;
    setState(() => _index++);
  }
""", 'swipe context capture'),
])

patch('app/lib/utils/format.dart', [
    ("""  if (d.inDays >= 1)
    return s?.t('daysAgo', {'n': '${d.inDays}'}) ?? '${d.inDays}d ago';
  if (d.inHours >= 1)
    return s?.t('hoursAgo', {'n': '${d.inHours}'}) ?? '${d.inHours}h ago';
""", """  if (d.inDays >= 1) {
    return s?.t('daysAgo', {'n': '${d.inDays}'}) ?? '${d.inDays}d ago';
  }
  if (d.inHours >= 1) {
    return s?.t('hoursAgo', {'n': '${d.inHours}'}) ?? '${d.inHours}h ago';
  }
""", 'relative date braces'),
])

patch('app/lib/utils/price_tone.dart', [
    ("""  if (medianUsd == null || medianUsd <= 0 || priceUsd == null || priceUsd <= 0)
    return null;
""", """  if (medianUsd == null || medianUsd <= 0 || priceUsd == null || priceUsd <= 0) {
    return null;
  }
""", 'price tone braces'),
])

patch('app/lib/services/api_service_base.dart', [
    ("""      if (point['photo'] != null)
        point['photo'] = _resolvePhoto(point['photo']);
""", """      if (point['photo'] != null) {
        point['photo'] = _resolvePhoto(point['photo']);
      }
""", 'map photo braces'),
    ("""    if (job.status == 'failed')
      throw Exception(job.error ?? 'translation failed');
""", """    if (job.status == 'failed') {
      throw Exception(job.error ?? 'translation failed');
    }
""", 'translation failed braces'),
])

patch('app/lib/services/api_service.dart', [
    ("""  Future<Listing?> reloadListing(Listing listing) async {
    final fresh = await super.reloadListing(listing);
""", """  Future<Listing?> reloadListing(Listing l) async {
    final fresh = await super.reloadListing(l);
""", 'override parameter name'),
])

patch('app/test/country_locale_retry_test.dart', [
    ("""import '../lib/models/filters.dart';
import '../lib/services/api_service.dart';
import '../lib/state/app_state.dart';
""", """import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/state/app_state.dart';
""", 'country locale package imports'),
])

patch('app/test/sort_options_test.dart', [
    ("""import '../lib/models/filters.dart';
import '../lib/models/listing.dart';
import '../lib/utils/sort.dart';
""", """import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/utils/sort.dart';
""", 'sort options package imports'),
])

patch('app/test/sorted_collection_test.dart', [
    ("""import '../lib/state/sorted.dart';
""", """import 'package:flat_finder/state/sorted.dart';
""", 'sorted collection package import'),
])

patch('app/test/statistics_snapshot_cache_test.dart', [
    ("""import '../lib/models/filters.dart';
import '../lib/services/api_service.dart';
""", """import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/services/api_service.dart';
""", 'statistics package imports'),
])

patch('app/test/metro_proximity_integration_test.dart', [
    ("""import 'dart:async';

""", '', 'remove redundant async import'),
])
