import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';

class SortedState extends ChangeNotifier {
  static const _key = 'sortedListings';
  final List<Listing> _items = [];

  List<Listing> get items => List.unmodifiable(_items);
  bool contains(String id) => _items.any((item) => item.id == id);

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      _items
        ..clear()
        ..addAll((jsonDecode(raw) as List).map(
          (item) => Listing.fromJson(Map<String, dynamic>.from(item)),
        ));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> add(Listing listing) async {
    if (contains(listing.id)) return;
    _items.insert(0, listing);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }
}
