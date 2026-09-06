import 'dart:collection';

class StoredListingItem {
  const StoredListingItem({required this.key, required this.payload});

  final String key;
  final Map<String, dynamic> payload;

  StoredListingItem copy() => StoredListingItem(
        key: key,
        payload: Map<String, dynamic>.from(payload),
      );
}

class StoredListingCollection {
  const StoredListingCollection({
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
  final List<StoredListingItem> items;

  StoredListingCollection copyWith({
    String? title,
    bool? isPreset,
    String? presetName,
    List<StoredListingItem>? items,
  }) =>
      StoredListingCollection(
        id: id,
        title: title ?? this.title,
        isPreset: isPreset ?? this.isPreset,
        presetName: presetName ?? this.presetName,
        items: items ?? this.items,
      );

  StoredListingCollection copy() => StoredListingCollection(
        id: id,
        title: title,
        isPreset: isPreset,
        presetName: presetName,
        items: items.map((item) => item.copy()).toList(growable: false),
      );
}

abstract interface class SavedListingStore {
  Future<List<StoredListingCollection>> readCollections(String bucket);

  Future<void> replaceCollections(
    String bucket,
    List<StoredListingCollection> collections,
  );

  Future<void> upsertListing(
    String bucket, {
    required StoredListingItem item,
    required String collectionId,
    required String collectionTitle,
    bool isPreset = false,
    String? presetName,
    int? maxItems,
  });

  Future<void> removeListing(
    String bucket,
    String listingKey, {
    String? collectionId,
  });

  Future<void> removeCollection(String bucket, String collectionId);

  Future<void> clearCollections(String bucket);

  /// Stable identity keys are intentionally stored separately from rich
  /// listing snapshots. History can therefore remember thousands of viewed
  /// ads without keeping thousands of full listing JSON payloads in memory.
  Future<List<String>> readKeys(String bucket);

  Future<void> replaceKeys(
    String bucket,
    List<String> keys, {
    int? maxItems,
  });

  Future<void> rememberKey(
    String bucket,
    String key, {
    int? maxItems,
  });

  Future<void> clearKeys(String bucket);

  Future<bool> isMigrated(String bucket);

  Future<void> markMigrated(String bucket);
}

/// Deterministic in-memory implementation used by state tests. Its semantics
/// mirror the persistent store: collection/item order is newest-first, adding a
/// listing moves it out of any previous collection, and remembering an existing
/// identity does not make it "new" again in the FIFO viewed-key history.
class MemorySavedListingStore implements SavedListingStore {
  final Map<String, List<StoredListingCollection>> _collections = {};
  final Map<String, LinkedHashSet<String>> _keys = {};
  final Set<String> _migrated = {};

  @override
  Future<List<StoredListingCollection>> readCollections(String bucket) async =>
      (_collections[bucket] ?? const [])
          .map((collection) => collection.copy())
          .toList(growable: false);

  @override
  Future<void> replaceCollections(
    String bucket,
    List<StoredListingCollection> collections,
  ) async {
    _collections[bucket] = collections
        .where((collection) => collection.id.isNotEmpty && collection.items.isNotEmpty)
        .map((collection) => collection.copy())
        .toList();
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
    final collections = _collections.putIfAbsent(bucket, () => []);

    for (var i = collections.length - 1; i >= 0; i--) {
      final remaining = collections[i].items
          .where((candidate) => candidate.key != item.key)
          .map((candidate) => candidate.copy())
          .toList();
      if (remaining.isEmpty) {
        collections.removeAt(i);
      } else if (remaining.length != collections[i].items.length) {
        collections[i] = collections[i].copyWith(items: remaining);
      }
    }

    var index = collections.indexWhere((collection) => collection.id == collectionId);
    final previous = index < 0 ? null : collections.removeAt(index);
    final items = [
      item.copy(),
      if (previous != null)
        ...previous.items.map((candidate) => candidate.copy()),
    ];
    if (maxItems != null && maxItems >= 0 && items.length > maxItems) {
      items.removeRange(maxItems, items.length);
    }
    if (items.isNotEmpty) {
      collections.insert(
        0,
        StoredListingCollection(
          id: collectionId,
          title: collectionTitle,
          isPreset: isPreset,
          presetName: presetName,
          items: items,
        ),
      );
    }
  }

  @override
  Future<void> removeListing(
    String bucket,
    String listingKey, {
    String? collectionId,
  }) async {
    final collections = _collections[bucket];
    if (collections == null) return;
    for (var i = collections.length - 1; i >= 0; i--) {
      if (collectionId != null && collections[i].id != collectionId) continue;
      final remaining = collections[i].items
          .where((item) => item.key != listingKey)
          .map((item) => item.copy())
          .toList();
      if (remaining.isEmpty) {
        collections.removeAt(i);
      } else if (remaining.length != collections[i].items.length) {
        collections[i] = collections[i].copyWith(items: remaining);
      }
    }
  }

  @override
  Future<void> removeCollection(String bucket, String collectionId) async {
    _collections[bucket]?.removeWhere((collection) => collection.id == collectionId);
  }

  @override
  Future<void> clearCollections(String bucket) async {
    _collections.remove(bucket);
  }

  @override
  Future<List<String>> readKeys(String bucket) async =>
      List<String>.unmodifiable(_keys[bucket] ?? const <String>{});

  @override
  Future<void> replaceKeys(
    String bucket,
    List<String> keys, {
    int? maxItems,
  }) async {
    final normalized = LinkedHashSet<String>.from(
      keys.map((key) => key.trim()).where((key) => key.isNotEmpty),
    );
    _trimKeys(normalized, maxItems);
    _keys[bucket] = normalized;
  }

  @override
  Future<void> rememberKey(
    String bucket,
    String key, {
    int? maxItems,
  }) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    final keys = _keys.putIfAbsent(bucket, LinkedHashSet<String>.new);
    keys.add(normalized);
    _trimKeys(keys, maxItems);
  }

  @override
  Future<void> clearKeys(String bucket) async {
    _keys.remove(bucket);
  }

  @override
  Future<bool> isMigrated(String bucket) async => _migrated.contains(bucket);

  @override
  Future<void> markMigrated(String bucket) async {
    _migrated.add(bucket);
  }

  void _trimKeys(LinkedHashSet<String> keys, int? maxItems) {
    if (maxItems == null || maxItems < 0) return;
    while (keys.length > maxItems) {
      keys.remove(keys.first);
    }
  }
}
