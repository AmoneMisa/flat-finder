import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';
import '../models/listing_identity.dart';
import '../services/user_saved_state_repository.dart';

/// Saved listings. PostgreSQL is authoritative; SharedPreferences is retained
/// as an offline/instant cache so opening the favorites tab never depends on a
/// network round-trip.
class FavoritesState extends ChangeNotifier {
  FavoritesState(this._repository);

  static const _kFavorites = 'favorites';

  final UserSavedStateRepository _repository;
  final List<Listing> _items = [];
  final Set<String> _keys = {};

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  bool isFavorite(Listing listing) => _keys.contains(listingKey(listing));

  Future<void> load() async {
    await _loadLocalCache();
    try {
      final snapshot = await _repository.snapshot();
      final remote = <Listing>[];
      for (final entry in (snapshot['favorites'] as List? ?? const [])) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final payload = map['listing'];
        if (payload is! Map) continue;
        try {
          remote.add(Listing.fromJson(Map<String, dynamic>.from(payload)));
        } catch (_) {}
      }
      _items
        ..clear()
        ..addAll(remote);
      _rebuildIndex();
      await _saveLocalCache();
      notifyListeners();
    } catch (_) {
      // The local cache loaded above remains usable offline.
    }
  }

  Future<void> _loadLocalCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kFavorites);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _items
        ..clear()
        ..addAll(
          list.map((e) => Listing.fromJson(Map<String, dynamic>.from(e))),
        );
      _rebuildIndex();
      notifyListeners();
    } catch (_) {
      _items.clear();
      _keys.clear();
    }
  }

  Future<void> toggle(Listing listing) async {
    final key = listingKey(listing);
    final i = _items.indexWhere((item) => listingKey(item) == key);
    final removing = i >= 0;
    if (removing) {
      _items.removeAt(i);
      _keys.remove(key);
    } else {
      _items.insert(0, listing);
      _keys.add(key);
    }
    notifyListeners();
    await _saveLocalCache();
    if (removing) {
      await _repository.deleteFavorite(listing);
    } else {
      await _repository.putFavorite(listing);
    }
  }

  Future<void> remove(Listing listing) async {
    final key = listingKey(listing);
    _items.removeWhere((item) => listingKey(item) == key);
    _keys.remove(key);
    notifyListeners();
    await _saveLocalCache();
    await _repository.deleteFavorite(listing);
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

  Future<void> _saveLocalCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kFavorites,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }
}
