import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';
import '../models/listing_identity.dart';

/// Saved listings, persisted locally. Exposes them grouped into
/// country → city "folders" for the favorites screen.
class FavoritesState extends ChangeNotifier {
  static const _kFavorites = 'favorites';

  final List<Listing> _items = [];
  final Set<String> _keys = {};

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  bool isFavorite(Listing listing) => _keys.contains(listingKey(listing));

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kFavorites);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items
          ..clear()
          ..addAll(
            list.map((e) => Listing.fromJson(Map<String, dynamic>.from(e))),
          );
        _rebuildIndex();
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/incompatible saved state: start empty and keep the list/index
      // consistent rather than leaving a partially decoded collection behind.
      _items.clear();
      _keys.clear();
    }
  }

  Future<void> toggle(Listing listing) async {
    final key = listingKey(listing);
    final i = _items.indexWhere((item) => listingKey(item) == key);
    if (i >= 0) {
      _items.removeAt(i);
      _keys.remove(key);
    } else {
      _items.insert(0, listing);
      _keys.add(key);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(Listing listing) async {
    final key = listingKey(listing);
    _items.removeWhere((item) => listingKey(item) == key);
    _keys.remove(key);
    notifyListeners();
    await _save();
  }

  /// Grouped as country code → (city name → listings). Cities with no name are
  /// bucketed under an empty-string key that the UI labels "Other".
  Map<String, Map<String, List<Listing>>> grouped() {
    final out = <String, Map<String, List<Listing>>>{};
    for (final l in _items) {
      final byCity = out.putIfAbsent(l.country, () => {});
      byCity.putIfAbsent(l.city, () => []).add(l);
    }
    return out;
  }

  void _rebuildIndex() {
    _keys
      ..clear()
      ..addAll(_items.map(listingKey));
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kFavorites,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }
}
