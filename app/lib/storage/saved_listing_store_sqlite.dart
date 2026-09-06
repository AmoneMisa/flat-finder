import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'saved_listing_store_prefs.dart';
import 'saved_listing_store_types.dart';

/// Native normalized storage for user-owned listing collections. Full Listing
/// payloads no longer have to be decoded/re-encoded as one giant preference on
/// every favorite/sort/history mutation.
class SqliteSavedListingStore implements SavedListingStore {
  SqliteSavedListingStore({PreferencesSavedListingStore? fallback})
      : _fallback = fallback ?? PreferencesSavedListingStore();

  static const _databaseName = 'flat_finder_saved_listings.db';
  static const _databaseVersion = 1;

  final PreferencesSavedListingStore _fallback;
  Database? _db;

  bool get _supportsSqlite =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, _databaseName),
      version: _databaseVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE saved_collections (
            bucket TEXT NOT NULL,
            collection_id TEXT NOT NULL,
            title TEXT NOT NULL,
            is_preset INTEGER NOT NULL DEFAULT 0,
            preset_name TEXT,
            order_value INTEGER NOT NULL,
            PRIMARY KEY (bucket, collection_id)
          )
        ''');
        await database.execute('''
          CREATE TABLE saved_listings (
            bucket TEXT NOT NULL,
            listing_key TEXT NOT NULL,
            collection_id TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            order_value INTEGER NOT NULL,
            PRIMARY KEY (bucket, listing_key),
            FOREIGN KEY (bucket, collection_id)
              REFERENCES saved_collections(bucket, collection_id)
              ON DELETE CASCADE
          )
        ''');
        await database.execute('''
          CREATE INDEX saved_listings_collection_order
          ON saved_listings(bucket, collection_id, order_value DESC)
        ''');
        await database.execute('''
          CREATE TABLE saved_keys (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            bucket TEXT NOT NULL,
            listing_key TEXT NOT NULL,
            UNIQUE (bucket, listing_key)
          )
        ''');
        await database.execute('''
          CREATE INDEX saved_keys_bucket_seq
          ON saved_keys(bucket, seq)
        ''');
        await database.execute('''
          CREATE TABLE saved_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  @override
  Future<List<StoredListingCollection>> readCollections(String bucket) async {
    if (!_supportsSqlite) return _fallback.readCollections(bucket);
    final rows = await (await _database()).rawQuery('''
      SELECT
        c.collection_id,
        c.title,
        c.is_preset,
        c.preset_name,
        l.listing_key,
        l.payload_json
      FROM saved_collections c
      JOIN saved_listings l
        ON l.bucket = c.bucket AND l.collection_id = c.collection_id
      WHERE c.bucket = ?
      ORDER BY c.order_value DESC, l.order_value DESC
    ''', [bucket]);

    final collections = <String, _MutableCollection>{};
    for (final row in rows) {
      final id = row['collection_id']?.toString() ?? '';
      final key = row['listing_key']?.toString() ?? '';
      final raw = row['payload_json']?.toString() ?? '';
      if (id.isEmpty || key.isEmpty || raw.isEmpty) continue;
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        payload = Map<String, dynamic>.from(decoded);
      } catch (_) {
        continue;
      }
      final collection = collections.putIfAbsent(
        id,
        () => _MutableCollection(
          id: id,
          title: row['title']?.toString() ?? '',
          isPreset: (row['is_preset'] as num?)?.toInt() == 1,
          presetName: row['preset_name']?.toString(),
        ),
      );
      collection.items.add(StoredListingItem(key: key, payload: payload));
    }
    return collections.values
        .map((collection) => collection.freeze())
        .toList(growable: false);
  }

  @override
  Future<void> replaceCollections(
    String bucket,
    List<StoredListingCollection> collections,
  ) async {
    if (!_supportsSqlite) {
      await _fallback.replaceCollections(bucket, collections);
      return;
    }
    final normalized = _dedupeCollections(collections);
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete('saved_listings', where: 'bucket = ?', whereArgs: [bucket]);
      await txn.delete('saved_collections', where: 'bucket = ?', whereArgs: [bucket]);
      for (var ci = 0; ci < normalized.length; ci++) {
        final collection = normalized[ci];
        await txn.insert('saved_collections', {
          'bucket': bucket,
          'collection_id': collection.id,
          'title': collection.title,
          'is_preset': collection.isPreset ? 1 : 0,
          'preset_name': collection.presetName,
          'order_value': normalized.length - ci,
        });
        for (var ii = 0; ii < collection.items.length; ii++) {
          final item = collection.items[ii];
          await txn.insert('saved_listings', {
            'bucket': bucket,
            'listing_key': item.key,
            'collection_id': collection.id,
            'payload_json': jsonEncode(item.payload),
            'order_value': collection.items.length - ii,
          });
        }
      }
    });
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
    if (!_supportsSqlite) {
      await _fallback.upsertListing(
        bucket,
        item: item,
        collectionId: collectionId,
        collectionTitle: collectionTitle,
        isPreset: isPreset,
        presetName: presetName,
        maxItems: maxItems,
      );
      return;
    }
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(
        'saved_listings',
        where: 'bucket = ? AND listing_key = ?',
        whereArgs: [bucket, item.key],
      );
      await _deleteEmptyCollections(txn, bucket);

      final collectionOrder = await _nextOrder(
        txn,
        'saved_collections',
        bucket,
      );
      final updated = await txn.update(
        'saved_collections',
        {
          'title': collectionTitle,
          'is_preset': isPreset ? 1 : 0,
          'preset_name': presetName,
          'order_value': collectionOrder,
        },
        where: 'bucket = ? AND collection_id = ?',
        whereArgs: [bucket, collectionId],
      );
      if (updated == 0) {
        await txn.insert('saved_collections', {
          'bucket': bucket,
          'collection_id': collectionId,
          'title': collectionTitle,
          'is_preset': isPreset ? 1 : 0,
          'preset_name': presetName,
          'order_value': collectionOrder,
        });
      }

      final itemOrder = await _nextOrder(txn, 'saved_listings', bucket);
      await txn.insert('saved_listings', {
        'bucket': bucket,
        'listing_key': item.key,
        'collection_id': collectionId,
        'payload_json': jsonEncode(item.payload),
        'order_value': itemOrder,
      });

      if (maxItems != null && maxItems >= 0) {
        final overflow = await txn.rawQuery('''
          SELECT listing_key
          FROM saved_listings
          WHERE bucket = ? AND collection_id = ?
          ORDER BY order_value DESC
          LIMIT -1 OFFSET ?
        ''', [bucket, collectionId, maxItems]);
        for (final row in overflow) {
          await txn.delete(
            'saved_listings',
            where: 'bucket = ? AND listing_key = ?',
            whereArgs: [bucket, row['listing_key']],
          );
        }
      }
      await _deleteEmptyCollections(txn, bucket);
    });
  }

  @override
  Future<void> removeListing(
    String bucket,
    String listingKey, {
    String? collectionId,
  }) async {
    if (!_supportsSqlite) {
      await _fallback.removeListing(
        bucket,
        listingKey,
        collectionId: collectionId,
      );
      return;
    }
    final db = await _database();
    await db.transaction((txn) async {
      final where = collectionId == null
          ? 'bucket = ? AND listing_key = ?'
          : 'bucket = ? AND listing_key = ? AND collection_id = ?';
      final args = collectionId == null
          ? <Object?>[bucket, listingKey]
          : <Object?>[bucket, listingKey, collectionId];
      await txn.delete('saved_listings', where: where, whereArgs: args);
      await _deleteEmptyCollections(txn, bucket);
    });
  }

  @override
  Future<void> removeCollection(String bucket, String collectionId) async {
    if (!_supportsSqlite) {
      await _fallback.removeCollection(bucket, collectionId);
      return;
    }
    await (await _database()).delete(
      'saved_collections',
      where: 'bucket = ? AND collection_id = ?',
      whereArgs: [bucket, collectionId],
    );
  }

  @override
  Future<void> clearCollections(String bucket) async {
    if (!_supportsSqlite) {
      await _fallback.clearCollections(bucket);
      return;
    }
    await (await _database()).delete(
      'saved_collections',
      where: 'bucket = ?',
      whereArgs: [bucket],
    );
  }

  @override
  Future<List<String>> readKeys(String bucket) async {
    if (!_supportsSqlite) return _fallback.readKeys(bucket);
    final rows = await (await _database()).query(
      'saved_keys',
      columns: ['listing_key'],
      where: 'bucket = ?',
      whereArgs: [bucket],
      orderBy: 'seq ASC',
    );
    return rows
        .map((row) => row['listing_key']?.toString() ?? '')
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> replaceKeys(
    String bucket,
    List<String> keys, {
    int? maxItems,
  }) async {
    if (!_supportsSqlite) {
      await _fallback.replaceKeys(bucket, keys, maxItems: maxItems);
      return;
    }
    final normalized = _normalizeKeys(keys, maxItems);
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete('saved_keys', where: 'bucket = ?', whereArgs: [bucket]);
      for (final key in normalized) {
        await txn.insert(
          'saved_keys',
          {'bucket': bucket, 'listing_key': key},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  @override
  Future<void> rememberKey(
    String bucket,
    String key, {
    int? maxItems,
  }) async {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    if (!_supportsSqlite) {
      await _fallback.rememberKey(bucket, normalized, maxItems: maxItems);
      return;
    }
    final db = await _database();
    await db.transaction((txn) async {
      await txn.insert(
        'saved_keys',
        {'bucket': bucket, 'listing_key': normalized},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (maxItems != null && maxItems >= 0) {
        final count = Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM saved_keys WHERE bucket = ?',
                [bucket],
              ),
            ) ??
            0;
        final overflow = count - maxItems;
        if (overflow > 0) {
          await txn.rawDelete('''
            DELETE FROM saved_keys
            WHERE seq IN (
              SELECT seq FROM saved_keys
              WHERE bucket = ?
              ORDER BY seq ASC
              LIMIT ?
            )
          ''', [bucket, overflow]);
        }
      }
    });
  }

  @override
  Future<void> clearKeys(String bucket) async {
    if (!_supportsSqlite) {
      await _fallback.clearKeys(bucket);
      return;
    }
    await (await _database()).delete(
      'saved_keys',
      where: 'bucket = ?',
      whereArgs: [bucket],
    );
  }

  @override
  Future<bool> isMigrated(String bucket) async {
    if (!_supportsSqlite) return _fallback.isMigrated(bucket);
    final rows = await (await _database()).query(
      'saved_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['migrated:$bucket'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == '1';
  }

  @override
  Future<void> markMigrated(String bucket) async {
    if (!_supportsSqlite) {
      await _fallback.markMigrated(bucket);
      return;
    }
    await (await _database()).insert(
      'saved_meta',
      {'key': 'migrated:$bucket', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _nextOrder(
    DatabaseExecutor executor,
    String table,
    String bucket,
  ) async {
    final rows = await executor.rawQuery(
      'SELECT COALESCE(MAX(order_value), 0) + 1 AS value FROM $table WHERE bucket = ?',
      [bucket],
    );
    return (rows.first['value'] as num?)?.toInt() ?? 1;
  }

  Future<void> _deleteEmptyCollections(
    DatabaseExecutor executor,
    String bucket,
  ) async {
    await executor.rawDelete('''
      DELETE FROM saved_collections
      WHERE bucket = ?
        AND NOT EXISTS (
          SELECT 1 FROM saved_listings l
          WHERE l.bucket = saved_collections.bucket
            AND l.collection_id = saved_collections.collection_id
        )
    ''', [bucket]);
  }

  List<StoredListingCollection> _dedupeCollections(
    List<StoredListingCollection> collections,
  ) {
    final seen = <String>{};
    final out = <StoredListingCollection>[];
    for (final collection in collections) {
      if (collection.id.isEmpty) continue;
      final items = <StoredListingItem>[];
      for (final item in collection.items) {
        if (item.key.isEmpty || !seen.add(item.key)) continue;
        items.add(item.copy());
      }
      if (items.isEmpty) continue;
      out.add(collection.copyWith(items: items));
    }
    return out;
  }

  List<String> _normalizeKeys(List<String> keys, int? maxItems) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in keys) {
      final key = raw.trim();
      if (key.isNotEmpty && seen.add(key)) out.add(key);
    }
    if (maxItems != null && maxItems >= 0 && out.length > maxItems) {
      out.removeRange(0, out.length - maxItems);
    }
    return out;
  }
}

class _MutableCollection {
  _MutableCollection({
    required this.id,
    required this.title,
    required this.isPreset,
    required this.presetName,
  });

  final String id;
  final String title;
  final bool isPreset;
  final String? presetName;
  final List<StoredListingItem> items = [];

  StoredListingCollection freeze() => StoredListingCollection(
        id: id,
        title: title,
        isPreset: isPreset,
        presetName: presetName,
        items: List.unmodifiable(items),
      );
}

SavedListingStore createSavedListingStore() => SqliteSavedListingStore();
