import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';
import '../models/listing_identity.dart';
import '../services/user_saved_state_repository.dart';

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
  }) => SortedCollection(
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

  factory SortedCollection.fromRemote(Map<String, dynamic> json) =>
      SortedCollection(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        isPreset: json['isPreset'] == true,
        presetName: json['presetName']?.toString(),
        items: (json['items'] as List? ?? const [])
            .whereType<Map>()
            .map((entry) => entry['listing'])
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

/// User-created listing collections. PostgreSQL is authoritative in the app;
/// SharedPreferences is an offline cache. The optional repository keeps this
/// state independently testable without network infrastructure.
class SortedState extends ChangeNotifier {
  SortedState([this._repository]);

  static const _key = 'sortedListings';
  static const _version = 3;

  final UserSavedStateRepository? _repository;
  final List<SortedCollection> _collections = [];
  final Set<String> _keys = {};

  List<SortedCollection> get collections => List.unmodifiable(_collections);
  List<Listing> get items => List.unmodifiable([
        for (final collection in _collections) ...collection.items,
      ]);

  bool containsKey(String key) => _keys.contains(key);
  bool contains(Listing listing) => containsKey(listingKey(listing));
  bool containsListing(Listing listing) => contains(listing);

  Future<void> load() async {
    await _loadLocalCache();
    final repository = _repository;
    if (repository == null) return;
    try {
      final snapshot = await repository.snapshot();
      final remote = <SortedCollection>[];
      for (final entry in (snapshot['sorted'] as List? ?? const [])) {
        if (entry is! Map) continue;
        try {
          final collection = SortedCollection.fromRemote(
            Map<String, dynamic>.from(entry),
          );
          if (collection.id.isNotEmpty && collection.items.isNotEmpty) {
            remote.add(collection);
          }
        } catch (_) {}
      }
      _collections
        ..clear()
        ..addAll(remote);
      _rebuildIndex();
      await _saveLocalCache();
      notifyListeners();
    } catch (_) {
      // Keep local cache when server is unavailable.
    }
  }

  Future<void> _loadLocalCache() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      _collections.clear();

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
              .where(
                (collection) =>
                    collection.id.isNotEmpty && collection.items.isNotEmpty,
              ),
        );
      }
      _rebuildIndex();
      notifyListeners();
    } catch (_) {
      _collections.clear();
      _keys.clear();
    }
  }

  Future<void> add(
    Listing listing, {
    required String collectionId,
    required String collectionTitle,
    bool isPreset = false,
    String? presetName,
  }) async {
    final key = listingKey(listing);

    for (var i = _collections.length - 1; i >= 0; i--) {
      final remaining = _collections[i].items
          .where((item) => listingKey(item) != key)
          .toList();
      if (remaining.isEmpty) {
        _collections.removeAt(i);
      } else if (remaining.length != _collections[i].items.length) {
        _collections[i] = _collections[i].copyWith(items: remaining);
      }
    }

    var index = _collections.indexWhere(
      (collection) => collection.id == collectionId,
    );
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

    _keys.add(key);
    notifyListeners();
    await _saveLocalCache();
    await _repository?.putSorted(
      listing,
      collectionId: collectionId,
      collectionTitle: collectionTitle,
      isPreset: isPreset,
      presetName: presetName,
    );
  }

  Future<void> remove(Listing listing, {String? collectionId}) async {
    final key = listingKey(listing);
    final affected = <String>[];
    for (var i = _collections.length - 1; i >= 0; i--) {
      if (collectionId != null && _collections[i].id != collectionId) continue;
      final before = _collections[i].items.length;
      final remaining = _collections[i].items
          .where((item) => listingKey(item) != key)
          .toList();
      if (remaining.length != before) affected.add(_collections[i].id);
      if (remaining.isEmpty) {
        _collections.removeAt(i);
      } else if (remaining.length != before) {
        _collections[i] = _collections[i].copyWith(items: remaining);
      }
    }
    _rebuildIndex();
    notifyListeners();
    await _saveLocalCache();
    final repository = _repository;
    if (repository == null) return;
    for (final id in affected) {
      await repository.deleteSorted(listing, collectionId: id);
    }
  }

  Future<void> removeCollection(String collectionId) async {
    _collections.removeWhere((collection) => collection.id == collectionId);
    _rebuildIndex();
    notifyListeners();
    await _saveLocalCache();
    await _repository?.deleteSortedCollection(collectionId);
  }

  void _rebuildIndex() {
    _keys
      ..clear()
      ..addAll(
        _collections.expand((collection) => collection.items).map(listingKey),
      );
  }

  Future<void> _saveLocalCache() async {
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        'version': _version,
        'collections':
            _collections.map((collection) => collection.toJson()).toList(),
      }),
    );
  }
}
