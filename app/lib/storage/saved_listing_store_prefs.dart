import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'saved_listing_store_types.dart';

/// Portable fallback for Flutter web and desktop platforms where the mobile
/// sqflite plugin is not available. It keeps the normalized storage contract,
/// so state code and migrations are identical across platforms.
class PreferencesSavedListingStore implements SavedListingStore {
  String _collectionsKey(String bucket) => 'saved_store.v1.collections.$bucket';
  String _keysKey(String bucket) => 'saved_store.v1.keys.$bucket';
  String _migrationKey(String bucket) => 'saved_store.v1.migrated.$bucket';

  @override
  Future<List<StoredListingCollection>> readCollections(String bucket) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _collectionsKey(bucket),
    );
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) {
            final map = Map<String, dynamic>.from(entry);
            final items = (map['items'] as List? ?? const [])
                .whereType<Map>()
                .map((item) {
                  final value = Map<String, dynamic>.from(item);
                  final payload = value['payload'];
                  if (payload is! Map) return null;
                  final key = value['key']?.toString().trim() ?? '';
                  if (key.isEmpty) return null;
                  return StoredListingItem(
                    key: key,
                    payload: Map<String, dynamic>.from(payload),
                  );
                })
                .whereType<StoredListingItem>()
                .toList(growable: false);
            return StoredListingCollection(
              id: map['id']?.toString() ?? '',
              title: map['title']?.toString() ?? '',
              isPreset: map['isPreset'] == true,
              presetName: map['presetName']?.toString(),
              items: items,
            );
          })
          .where((collection) => collection.id.isNotEmpty && collection.items.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> replaceCollections(
    String bucket,
    List<StoredListingCollection> collections,
  ) async {
    final payload = [
      for (final collection in collections)
        if (collection.id.isNotEmpty && collection.items.isNotEmpty)
          {
            'id': collection.id,
            'title': collection.title,
            'isPreset': collection.isPreset,
            if (collection.presetName != null)
              'presetName': collection.presetName,
            'items': [
              for (final item in collection.items)
                {'key': item.key, 'payload': item.payload},
            ],
          },
    ];
    await (await SharedPreferences.getInstance()).setString(
      _collectionsKey(bucket),
      jsonEncode(payload),
    );
  }

  Future<MemorySavedListingStore> _memoryFor(String bucket) async {
    final memory = MemorySavedListingStore();
    await memory.replaceCollections(bucket, await readCollections(bucket));
    return memory;
  }

  @override
  Future<void> upsertListing(
    String bucket, {
    required StoredListingItem item,
    required String collectionId,
    required String collectionTitle,
    bool isPreset = false,
    String? presetName,
    int? maxItems,
  }) async {
    final memory = await _memoryFor(bucket);
    await memory.upsertListing(
      bucket,
      item: item,
      collectionId: collectionId,
      collectionTitle: collectionTitle,
      isPreset: isPreset,
      presetName: presetName,
      maxItems: maxItems,
    );
    await replaceCollections(bucket, await memory.readCollections(bucket));
  }

  @override
  Future<void> removeListing(
    String bucket,
    String listingKey, {
    String? collectionId,
  }) async {
    final memory = await _memoryFor(bucket);
    await memory.removeListing(bucket, listingKey, collectionId: collectionId);
    await replaceCollections(bucket, await memory.readCollections(bucket));
  }

  @override
  Future<void> removeCollection(String bucket, String collectionId) async {
    final memory = await _memoryFor(bucket);
    await memory.removeCollection(bucket, collectionId);
    await replaceCollections(bucket, await memory.readCollections(bucket));
  }

  @override
  Future<void> clearCollections(String bucket) async {
    await (await SharedPreferences.getInstance()).remove(_collectionsKey(bucket));
  }

  @override
  Future<List<String>> readKeys(String bucket) async {
    final raw = (await SharedPreferences.getInstance()).getString(_keysKey(bucket));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> replaceKeys(
    String bucket,
    List<String> keys, {
    int? maxItems,
  }) async {
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in keys) {
      final key = raw.trim();
      if (key.isNotEmpty && seen.add(key)) normalized.add(key);
    }
    if (maxItems != null && maxItems >= 0 && normalized.length > maxItems) {
      normalized.removeRange(0, normalized.length - maxItems);
    }
    await (await SharedPreferences.getInstance()).setString(
      _keysKey(bucket),
      jsonEncode(normalized),
    );
  }

  @override
  Future<void> rememberKey(
    String bucket,
    String key, {
    int? maxItems,
  }) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    final keys = await readKeys(bucket);
    if (!keys.contains(normalized)) keys.add(normalized);
    await replaceKeys(bucket, keys, maxItems: maxItems);
  }

  @override
  Future<void> clearKeys(String bucket) async {
    await (await SharedPreferences.getInstance()).remove(_keysKey(bucket));
  }

  @override
  Future<bool> isMigrated(String bucket) async =>
      (await SharedPreferences.getInstance()).getBool(_migrationKey(bucket)) ==
      true;

  @override
  Future<void> markMigrated(String bucket) async {
    await (await SharedPreferences.getInstance()).setBool(
      _migrationKey(bucket),
      true,
    );
  }
}

SavedListingStore createSavedListingStore() => PreferencesSavedListingStore();
