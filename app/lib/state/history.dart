import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';

/// Recently viewed listings, persisted locally. Newest first, capped so the
/// list stays a short "last viewed" trail rather than a full browsing log.
class HistoryState extends ChangeNotifier {
  static const _kHistory = 'history';
  static const _kViewedIds = 'viewed_ids';

  /// Keep only the last N opened listings in the rich "recently viewed" trail.
  static const int maxItems = 15;

  /// Keep a much larger set of *ids* of everything ever opened, so the "viewed"
  /// tag/tab still recognises a listing long after it fell out of the 15-item
  /// trail. Capped (FIFO) so it can't grow without bound.
  static const int maxViewedIds = 5000;

  final List<Listing> _items = [];
  final Set<String> _viewedIds = {};

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  /// Whether this listing has ever been opened (by id).
  bool isViewed(String id) => _viewedIds.contains(id);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kHistory);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items
          ..clear()
          ..addAll(list.map((e) => Listing.fromJson(Map<String, dynamic>.from(e))));
        // Guard against an oversized list from an older build.
        if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
      }
      final rawIds = p.getString(_kViewedIds);
      if (rawIds != null) {
        _viewedIds
          ..clear()
          ..addAll((jsonDecode(rawIds) as List).map((e) => e.toString()));
      }
      // Backfill from the trail so nothing already opened loses its mark.
      _viewedIds.addAll(_items.map((e) => e.id));
      notifyListeners();
    } catch (_) {
      // Corrupt/incompatible saved state: start empty.
    }
  }

  /// Record an opened listing: move it to the front (de-duplicated by id) and
  /// trim to [maxItems]. Also remember its id in the long-lived viewed set.
  Future<void> record(Listing l) async {
    _viewedIds.add(l.id);
    if (_viewedIds.length > maxViewedIds) {
      // Set preserves insertion order — drop the oldest ids first.
      _viewedIds.remove(_viewedIds.first);
    }
    final existing = _items.indexWhere((e) => e.id == l.id);
    if (existing == 0) {
      notifyListeners();
      await _save();
      return; // already the most recent — trail order unchanged
    }
    if (existing > 0) _items.removeAt(existing);
    _items.insert(0, l);
    if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    if (_items.isEmpty && _viewedIds.isEmpty) return;
    _items.clear();
    _viewedIds.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kHistory, jsonEncode(_items.map((e) => e.toJson()).toList()));
      await p.setString(_kViewedIds, jsonEncode(_viewedIds.toList()));
    } catch (_) {}
  }
}
