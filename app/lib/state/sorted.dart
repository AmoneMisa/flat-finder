import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';

class SortedCollection {
  const SortedCollection({
    required this.id,
    required this.title,
    required this.items,
    this.isPreset = false,
    this.presetName,
  });

  final String id;
  final String title;
  final bool isPreset;
  final String? presetName;
  final List<Listing> items;

  SortedCollection copyWith({
    String? title,
    bool? isPreset,
    String? presetName,
    List<Listing>? items,
  }) =>
      SortedCollection(
        id: id,
        title: title ?? this.title,
        isPreset: isPreset ?? this.isPreset,
        presetName: presetName ?? this.presetName,
        items: items ?? this.items,
      );

  factory SortedCollection.fromJson(Map<String, dynamic> json) =>
      SortedCollection(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        isPreset: json['isPreset'] == true,
        presetName: json['presetName']?.toString(),
        items: (json['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Listing.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isPreset': isPreset,
        if (presetName != null) 'presetName': presetName,
        'items': items.map((item) => item.toJson()).toList(),
      };
}

class SortedState extends ChangeNotifier {
  static const _key = 'sortedListings';
  static const _version = 2;

  final List<SortedCollection> _collections = [];

  List<SortedCollection> get collections => List.unmodifiable(_collections);
  List<Listing> get items => List.unmodifiable([
        for (final collection in _collections) ...collection.items,
      ]);

  String _listingKey(Listing listing) =>
      '${listing.source}:${listing.country}:${listing.id}';

  bool contains(String id) =>
      _collections.any((collection) => collection.items.any((item) => item.id == id));

  bool containsListing(Listing listing) {
    final key = _listingKey(listing);
    return _collections.any(
      (collection) => collection.items.any((item) => _listingKey(item) == key),
    );
  }

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      _collections.clear();

      // Migration from the original flat List<Listing> storage.
      if (decoded is List) {
        final legacy = decoded
            .whereType<Map>()
            .map((item) => Listing.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        if (legacy.isNotEmpty) {
          _collections.add(
            SortedCollection(
              id: 'legacy',
              title: 'Ранее отсортированные',
              items: legacy,
            ),
          );
        }
        await _save();
      } else if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final values = map['collections'] as List? ?? const [];
        _collections.addAll(
          values
              .whereType<Map>()
              .map(
                (item) => SortedCollection.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((collection) =>
                  collection.id.isNotEmpty && collection.items.isNotEmpty),
        );
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> add(
    Listing listing, {
    required String collectionId,
    required String collectionTitle,
    bool isPreset = false,
    String? presetName,
  }) async {
    final listingKey = _listingKey(listing);

    // One apartment belongs to one sorted collection. Sorting it from another
    // search/preset moves it instead of creating duplicates in several lists.
    for (var i = _collections.length - 1; i >= 0; i--) {
      final remaining = _collections[i]
          .items
          .where((item) => _listingKey(item) != listingKey)
          .toList();
      if (remaining.isEmpty) {
        _collections.removeAt(i);
      } else if (remaining.length != _collections[i].items.length) {
        _collections[i] = _collections[i].copyWith(items: remaining);
      }
    }

    var index = _collections.indexWhere((collection) => collection.id == collectionId);
    if (index < 0) {
      _collections.insert(
        0,
        SortedCollection(
          id: collectionId,
          title: collectionTitle,
          isPreset: isPreset,
          presetName: presetName,
          items: [listing],
        ),
      );
    } else {
      final collection = _collections[index];
      _collections[index] = collection.copyWith(
        title: collectionTitle,
        isPreset: isPreset,
        presetName: presetName,
        items: [listing, ...collection.items],
      );
      if (index > 0) {
        final updated = _collections.removeAt(index);
        _collections.insert(0, updated);
      }
    }

    notifyListeners();
    await _save();
  }

  Future<void> remove(String id, {String? collectionId}) async {
    for (var i = _collections.length - 1; i >= 0; i--) {
      if (collectionId != null && _collections[i].id != collectionId) continue;
      final remaining = _collections[i].items.where((item) => item.id != id).toList();
      if (remaining.isEmpty) {
        _collections.removeAt(i);
      } else if (remaining.length != _collections[i].items.length) {
        _collections[i] = _collections[i].copyWith(items: remaining);
      }
    }
    notifyListeners();
    await _save();
  }

  Future<void> removeCollection(String collectionId) async {
    _collections.removeWhere((collection) => collection.id == collectionId);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        'version': _version,
        'collections': _collections.map((collection) => collection.toJson()).toList(),
      }),
    );
  }
}
