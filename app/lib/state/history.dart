import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';
import '../models/listing_identity.dart';

/// Recently viewed listings, persisted locally. Newest first, capped so the
/// list stays a short "last viewed" trail rather than a full browsing log.
class HistoryState extends ChangeNotifier {
  static const _kHistory = 'history';
  static const _kViewedKeys = 'viewed_listing_keys_v2';
  static const _kLegacyViewedIds = 'viewed_ids';

  /// Keep only the last N opened listings in the rich "recently viewed" trail.
  static const int maxItems = 15;

  /// Keep a much larger set of stable keys of everything ever opened, so the
  /// "viewed" tag/tab still recognises a listing long after it fell out of the
  /// 15-item trail. Capped (FIFO) so it can't grow without bound.
  static const int maxViewedIds = 5000;

  final List<Listing> _items = [];
  final Set<String> _viewedKeys = {};

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  bool isViewed(Listing listing) => _viewedKeys.contains(listingKey(listing));

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kHistory);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items
          ..clear()
          ..addAll(
            list.map((e) => Listing.fromJson(Map<String, dynamic>.from(e))),
          );
        // Guard against an oversized list from an older build.
        if (_items.length > maxItems) {
          _items.removeRange(maxItems, _items.length);
        }
      }

      _viewedKeys.clear();
      final rawKeys = p.getString(_kViewedKeys);
      if (rawKeys != null) {
        _viewedKeys.addAll(
          (jsonDecode(rawKeys) as List).map((e) => e.toString()),
        );
      } else {
        // v1 stored source-local ids only. They cannot be safely mapped once a
        // listing has fallen out of the rich trail, because the same id may
        // exist in another country/source. Backfill only entries for which the
        // rich history still gives us an unambiguous full identity.
        final rawLegacy = p.getString(_kLegacyViewedIds);
        if (rawLegacy != null) {
          final legacyIds = (jsonDecode(rawLegacy) as List)
              .map((e) => e.toString())
              .toSet();
          _viewedKeys.addAll(
            _items.where((item) => legacyIds.contains(item.id)).map(listingKey),
          );
        }
      }

      // Backfill from the trail so nothing already opened loses its mark.
      _viewedKeys.addAll(_items.map(listingKey));
      await _save();
      await p.remove(_kLegacyViewedIds);
      notifyListeners();
    } catch (_) {
      // Corrupt/incompatible saved state: start empty.
    }
  }

  /// Record an opened listing: move it to the front (de-duplicated by stable
  /// identity) and trim to [maxItems]. Also remember its key long-term.
  Future<void> record(Listing listing) async {
    final key = listingKey(listing);
    _viewedKeys.add(key);
    if (_viewedKeys.length > maxViewedIds) {
      // Set preserves insertion order — drop the oldest keys first.
      _viewedKeys.remove(_viewedKeys.first);
    }
    final existing = _items.indexWhere((item) => listingKey(item) == key);
    if (existing == 0) {
      // Refresh the stored snapshot as the caller may have opened a richer copy.
      _items[0] = listing;
      notifyListeners();
      await _save();
      return;
    }
    if (existing > 0) _items.removeAt(existing);
    _items.insert(0, listing);
    if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    if (_items.isEmpty && _viewedKeys.isEmpty) return;
    _items.clear();
    _viewedKeys.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kHistory,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
      await p.setString(_kViewedKeys, jsonEncode(_viewedKeys.toList()));
    } catch (_) {}
  }
}
