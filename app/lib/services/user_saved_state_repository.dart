import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/listing.dart';
import '../models/listing_identity.dart';
import 'api_service.dart';
import 'installation_identity.dart';
import 'saved_state_api.dart';

/// Repository for user-owned state that should survive reinstalls and later be
/// claimable by an authenticated account.
///
/// PostgreSQL is the source of truth. SharedPreferences remains only an offline
/// cache plus a tiny idempotent mutation outbox, so a tap made without network
/// is replayed on the next successful connection instead of being lost.
class UserSavedStateRepository {
  UserSavedStateRepository(
    this._api, {
    InstallationIdentity? identity,
  }) : _identity = identity ?? InstallationIdentity();

  static const _migrationKey = 'remoteSavedStateImportedV1';
  static const _outboxKey = 'remoteSavedStateOutboxV1';
  static const _favoritesKey = 'favorites';
  static const _sortedKey = 'sortedListings';
  static const _presetsKey = 'filterPresets';

  final ApiService _api;
  final InstallationIdentity _identity;

  Future<Map<String, dynamic>>? _snapshotFuture;
  Future<void> _enqueueTail = Future<void>.value();
  Future<void>? _flushFuture;

  Future<String> get deviceId => _identity.getOrCreate();

  Future<Map<String, dynamic>> snapshot({bool force = false}) {
    if (force || _snapshotFuture == null) {
      _snapshotFuture = _loadSnapshot();
    }
    return _snapshotFuture!;
  }

  Future<Map<String, dynamic>> _loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = _legacySnapshot(prefs);
    final id = await deviceId;

    try {
      if (prefs.getBool(_migrationKey) != true) {
        await _api.importRemoteSavedState(
          id,
          favorites: _mapList(fallback['favorites']),
          sorted: _mapList(fallback['sorted']),
          presets: _mapList(fallback['presets']),
        );
        await prefs.setBool(_migrationKey, true);
      }

      await flushOutbox();
      final remote = await _api.fetchRemoteSavedState(id);
      return {
        'favorites': _mapList(remote['favorites']),
        'sorted': _mapList(remote['sorted']),
        'presets': _mapList(remote['presets']),
      };
    } catch (_) {
      // Offline startup must still expose the last local cache. The import
      // marker is written only after Postgre accepts the legacy snapshot, so a
      // failed first migration is retried on the next connection.
      return fallback;
    }
  }

  Future<void> putFavorite(Listing listing) => enqueueMutation({
        'op': 'favorite.put',
        'itemKey': listingKey(listing),
        'listing': listing.toJson(),
      });

  Future<void> deleteFavorite(Listing listing) => enqueueMutation({
        'op': 'favorite.delete',
        'itemKey': listingKey(listing),
      });

  Future<void> putSorted(
    Listing listing, {
    required String collectionId,
    required String collectionTitle,
    bool isPreset = false,
    String? presetName,
  }) =>
      enqueueMutation({
        'op': 'sorted.put',
        'collectionId': collectionId,
        'collectionTitle': collectionTitle,
        'isPreset': isPreset,
        if (presetName != null) 'presetName': presetName,
        'itemKey': listingKey(listing),
        'listing': listing.toJson(),
      });

  Future<void> deleteSorted(
    Listing listing, {
    required String collectionId,
  }) =>
      enqueueMutation({
        'op': 'sorted.delete',
        'collectionId': collectionId,
        'itemKey': listingKey(listing),
      });

  Future<void> deleteSortedCollection(String collectionId) => enqueueMutation({
        'op': 'sorted.deleteCollection',
        'collectionId': collectionId,
      });

  Future<void> putPreset(Map<String, dynamic> preset) => enqueueMutation({
        'op': 'preset.put',
        'preset': preset,
      });

  Future<void> deletePreset(String presetId) => enqueueMutation({
        'op': 'preset.delete',
        'presetId': presetId,
      });

  /// Durably enqueue before attempting the network request. Server mutations
  /// are idempotent (upserts/deletes), so replay after a crash is safe.
  Future<void> enqueueMutation(Map<String, dynamic> mutation) async {
    final queued = <String, dynamic>{
      '_queueId': InstallationIdentity.newId(),
      ...mutation,
    };

    final task = _enqueueTail.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final queue = _readOutbox(prefs)..add(queued);
      await prefs.setString(_outboxKey, jsonEncode(queue));
    });
    _enqueueTail = task.catchError((_) {});
    await task;
    _snapshotFuture = null;
    unawaited(flushOutbox());
  }

  Future<void> flushOutbox() {
    final running = _flushFuture;
    if (running != null) return running;
    final future = _drainOutbox();
    _flushFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_flushFuture, future)) _flushFuture = null;
      }),
    );
    return future;
  }

  Future<void> _drainOutbox() async {
    // Ensure an enqueue currently writing SharedPreferences cannot be lost by a
    // simultaneous drain.
    await _enqueueTail;
    final id = await deviceId;

    while (true) {
      final prefs = await SharedPreferences.getInstance();
      final queue = _readOutbox(prefs);
      if (queue.isEmpty) return;
      final mutation = queue.first;
      final queueId = mutation['_queueId']?.toString();

      try {
        await _api.mutateRemoteSavedState(id, mutation);
      } catch (_) {
        // Keep the failed operation at the head. Ordering matters for put/delete
        // sequences touching the same listing.
        return;
      }

      final latest = _readOutbox(prefs);
      final index = latest.indexWhere(
        (entry) => entry['_queueId']?.toString() == queueId,
      );
      if (index >= 0) latest.removeAt(index);
      if (latest.isEmpty) {
        await prefs.remove(_outboxKey);
      } else {
        await prefs.setString(_outboxKey, jsonEncode(latest));
      }
    }
  }

  List<Map<String, dynamic>> _readOutbox(SharedPreferences prefs) {
    final raw = prefs.getString(_outboxKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _legacySnapshot(SharedPreferences prefs) => {
        'favorites': _legacyFavorites(prefs),
        'sorted': _legacySorted(prefs),
        'presets': _legacyPresets(prefs),
      };

  List<Map<String, dynamic>> _legacyFavorites(SharedPreferences prefs) {
    final raw = prefs.getString(_favoritesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <Map<String, dynamic>>[];
      for (final entry in decoded.whereType<Map>()) {
        final payload = Map<String, dynamic>.from(entry);
        final listing = Listing.fromJson(payload);
        out.add({'key': listingKey(listing), 'listing': payload});
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _legacySorted(SharedPreferences prefs) {
    final raw = prefs.getString(_sortedKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      final collections = <Map<String, dynamic>>[];
      if (decoded is List) {
        final items = _legacyItems(decoded);
        if (items.isNotEmpty) {
          collections.add({
            'id': 'legacy',
            'title': 'Ранее отсортированные',
            'items': items,
          });
        }
        return collections;
      }
      if (decoded is! Map) return const [];
      for (final entry in (decoded['collections'] as List? ?? const [])) {
        if (entry is! Map) continue;
        final value = Map<String, dynamic>.from(entry);
        final id = value['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final items = _legacyItems(value['items'] as List? ?? const []);
        if (items.isEmpty) continue;
        collections.add({
          'id': id,
          'title': value['title']?.toString() ?? '',
          'isPreset': value['isPreset'] == true,
          if (value['presetName'] != null)
            'presetName': value['presetName'].toString(),
          'items': items,
        });
      }
      return collections;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _legacyItems(List<dynamic> values) {
    final out = <Map<String, dynamic>>[];
    for (final entry in values.whereType<Map>()) {
      final payload = Map<String, dynamic>.from(entry);
      try {
        final listing = Listing.fromJson(payload);
        out.add({'key': listingKey(listing), 'listing': payload});
      } catch (_) {}
    }
    return out;
  }

  List<Map<String, dynamic>> _legacyPresets(SharedPreferences prefs) {
    final raw = prefs.getString(_presetsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) {
            final id = entry['id']?.toString().trim() ?? '';
            return id.isNotEmpty && entry['filters'] is Map;
          })
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _mapList(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
}
