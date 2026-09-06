import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';
import '../models/listing_identity.dart';

/// Listings the user dismissed as "not interested", persisted locally and
/// excluded from the main results — mirrors the site's hide/restore feature.
class HiddenState extends ChangeNotifier {
  static const _kHidden = 'hiddenListings';
  static const _limit = 200;

  final List<Listing> _items = [];
  final Set<String> _keys = {};

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  bool isHiddenKey(String key) => _keys.contains(key);
  bool isHidden(Listing listing) => isHiddenKey(listingKey(listing));

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kHidden);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items
          ..clear()
          ..addAll(
            list.map((e) => Listing.fromJson(Map<String, dynamic>.from(e))),
          );
        if (_items.length > _limit) {
          _items.removeRange(_limit, _items.length);
        }
        _rebuildIndex();
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/incompatible saved state: start empty and keep indexes aligned.
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
      if (_items.length > _limit) {
        final removed = _items.removeLast();
        _keys.remove(listingKey(removed));
      }
    }
    notifyListeners();
    await _save();
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
        _kHidden,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }
}
