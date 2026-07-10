import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';

/// Recently viewed listings, persisted locally. Newest first, capped so the
/// list stays a short "last viewed" trail rather than a full browsing log.
class HistoryState extends ChangeNotifier {
  static const _kHistory = 'history';

  /// Keep only the last N opened listings.
  static const int maxItems = 15;

  final List<Listing> _items = [];

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

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
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/incompatible saved state: start empty.
    }
  }

  /// Record an opened listing: move it to the front (de-duplicated by id) and
  /// trim to [maxItems].
  Future<void> record(Listing l) async {
    final existing = _items.indexWhere((e) => e.id == l.id);
    if (existing == 0) return; // already the most recent — nothing changes
    if (existing > 0) _items.removeAt(existing);
    _items.insert(0, l);
    if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kHistory, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
