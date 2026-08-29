import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';

/// Listings the user dismissed as "not interested", persisted locally and
/// excluded from the main results — mirrors the site's hide/restore
/// feature (`useSavedCollections`'s `hidden` list).
class HiddenState extends ChangeNotifier {
  static const _kHidden = 'hiddenListings';
  static const _limit = 200;

  final List<Listing> _items = [];

  List<Listing> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  bool isHidden(String id) => _items.any((l) => l.id == id);

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
      if (_items.length > _limit) _items.removeLast();
    }
    notifyListeners();
    await _save();
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
