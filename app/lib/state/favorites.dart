import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';

/// Saved listings, persisted locally. Exposes them grouped into
/// country → city "folders" for the favorites screen.
class FavoritesState extends ChangeNotifier {
  static const _kFavorites = 'favorites';

  final List<Listing> _items = [];

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  bool isFavorite(String id) => _items.any((l) => l.id == id);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kFavorites);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items
          ..clear()
          ..addAll(list.map((e) => Listing.fromJson(Map<String, dynamic>.from(e))));
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/incompatible saved state: start empty.
    }
  }

  Future<void> toggle(Listing l) async {
    final i = _items.indexWhere((e) => e.id == l.id);
    if (i >= 0) {
      _items.removeAt(i);
    } else {
      _items.insert(0, l);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
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

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kFavorites, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
