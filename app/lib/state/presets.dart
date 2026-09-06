import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/filters.dart';
import '../services/api_service.dart';
import '../services/installation_identity.dart';
import '../services/push_service.dart';
import '../services/user_saved_state_repository.dart';

class FilterPreset {
  final String id;
  final String name;
  final Filters filters;
  final bool enabled;
  final bool notificationsEnabled;

  const FilterPreset({
    required this.id,
    required this.name,
    required this.filters,
    this.enabled = true,
    this.notificationsEnabled = false,
  });

  FilterPreset copyWith({
    String? name,
    Filters? filters,
    bool? enabled,
    bool? notificationsEnabled,
  }) => FilterPreset(
        id: id,
        name: name ?? this.name,
        filters: filters ?? this.filters,
        enabled: enabled ?? this.enabled,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filters': filters.toJson(),
        'enabled': enabled,
        'notificationsEnabled': notificationsEnabled,
      };
}

/// Saved searches are mirrored to PostgreSQL so a future account can claim the
/// installation and sync them across devices. SharedPreferences remains the
/// immediate/offline cache; push delivery is still synchronized independently.
class PresetsState extends ChangeNotifier {
  PresetsState(
    this._api, {
    UserSavedStateRepository? saved,
    PushService? push,
  })  : _saved = saved,
        _push = push ?? PushService.instance;

  static const _kPresets = 'filterPresets';
  static const _kPushMaster = 'filterPresetPushMaster';
  static const _kUiLanguage = 'lang';

  final ApiService _api;
  final UserSavedStateRepository? _saved;
  final PushService _push;
  final List<FilterPreset> _presets = [];
  final InstallationIdentity _identity = InstallationIdentity();
  StreamSubscription<String>? _tokenSub;

  Future<bool>? _syncFuture;
  bool _syncAgain = false;
  bool _requestPermissionNext = false;

  bool pushMasterEnabled = false;
  bool syncingPush = false;
  String? pushError;

  List<FilterPreset> get presets => List.unmodifiable(_presets);
  bool get pushClientConfigured => _push.configured;

  Future<void> load() async {
    var migrated = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      pushMasterEnabled = prefs.getBool(_kPushMaster) ?? false;
      final raw = prefs.getString(_kPresets);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _presets
          ..clear()
          ..addAll(
            list.whereType<Map>().map((entry) {
              final m = Map<String, dynamic>.from(entry);
              final id = m['id']?.toString().trim();
              if (id == null || id.isEmpty) migrated = true;
              return _fromMap(m, fallbackId: id == null || id.isEmpty ? _newId() : id);
            }),
          );
      }
      if (migrated) await _persistLocal();
      notifyListeners();

      final saved = _saved;
      if (saved != null) {
        final snapshot = await saved.snapshot();
        final remote = <FilterPreset>[];
        for (final entry in (snapshot['presets'] as List? ?? const [])) {
          if (entry is! Map) continue;
          try {
            final value = Map<String, dynamic>.from(entry);
            final id = value['id']?.toString().trim() ?? '';
            if (id.isEmpty) continue;
            remote.add(_fromMap(value, fallbackId: id));
          } catch (_) {}
        }
        _presets
          ..clear()
          ..addAll(remote);
        await _persistLocal();
        notifyListeners();
      }

      if (pushMasterEnabled && _activePushPresets.isNotEmpty) {
        unawaited(syncPushSubscriptions());
      }
    } catch (_) {
      // Local state must never prevent the apartment feed from opening.
    }
  }

  static FilterPreset _fromMap(
    Map<String, dynamic> map, {
    required String fallbackId,
  }) {
    final filtersRaw = map['filters'];
    return FilterPreset(
      id: (map['id']?.toString().trim().isNotEmpty == true)
          ? map['id'].toString().trim()
          : fallbackId,
      name: map['name']?.toString() ?? '',
      filters: filtersRaw is Map
          ? Filters.fromJson(Map<String, dynamic>.from(filtersRaw))
          : Filters(),
      enabled: map['enabled'] is bool ? map['enabled'] as bool : true,
      notificationsEnabled: map['notificationsEnabled'] is bool
          ? map['notificationsEnabled'] as bool
          : false,
    );
  }

  static String _newId() => InstallationIdentity.newId();

  Future<FilterPreset?> save(String name, Filters filters) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final i = _presets.indexWhere(
      (p) => p.name.toLowerCase() == trimmed.toLowerCase(),
    );
    final preset = i >= 0
        ? _presets[i].copyWith(name: trimmed, filters: filters)
        : FilterPreset(id: _newId(), name: trimmed, filters: filters);
    if (i >= 0) {
      _presets[i] = preset;
    } else {
      _presets.add(preset);
    }
    notifyListeners();
    await _persistPreset(preset);
    unawaited(syncPushSubscriptions());
    return preset;
  }

  Future<void> rename(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final i = _presets.indexWhere((p) => p.name == oldName);
    if (i < 0) return;
    final clash = _presets.any(
      (p) => p.name != oldName && p.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (clash) return;
    _presets[i] = _presets[i].copyWith(name: trimmed);
    notifyListeners();
    await _persistPreset(_presets[i]);
    await syncPushSubscriptions();
  }

  Future<void> remove(String name) async {
    final removed = _presets.where((p) => p.name == name).toList(growable: false);
    _presets.removeWhere((p) => p.name == name);
    notifyListeners();
    await _persistLocal();
    final saved = _saved;
    if (saved != null) {
      for (final preset in removed) {
        await saved.deletePreset(preset.id);
      }
    }
    await syncPushSubscriptions();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final i = _presets.indexWhere((p) => p.id == id);
    if (i < 0 || _presets[i].enabled == enabled) return;
    _presets[i] = _presets[i].copyWith(enabled: enabled);
    notifyListeners();
    await _persistPreset(_presets[i]);
    await syncPushSubscriptions();
  }

  Future<bool> setNotificationsEnabled(String id, bool enabled) async {
    final i = _presets.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    final old = _presets[i];
    _presets[i] = old.copyWith(
      enabled: enabled ? true : old.enabled,
      notificationsEnabled: enabled,
    );
    if (enabled) pushMasterEnabled = true;
    notifyListeners();
    await _persistPreset(_presets[i]);

    final ok = await syncPushSubscriptions(requestPermission: enabled);
    if (enabled && !ok) {
      _presets[i] = _presets[i].copyWith(notificationsEnabled: false);
      if (_presets.every((p) => !p.notificationsEnabled)) {
        pushMasterEnabled = false;
      }
      notifyListeners();
      await _persistPreset(_presets[i]);
      await syncPushSubscriptions();
    }
    return ok;
  }

  Future<bool> setPushMasterEnabled(bool enabled) async {
    final old = pushMasterEnabled;
    pushMasterEnabled = enabled;
    notifyListeners();
    await _persistLocal();
    final ok = await syncPushSubscriptions(
      requestPermission: enabled && _activePushPresets.isNotEmpty,
    );
    if (enabled && !ok && _activePushPresets.isNotEmpty) {
      pushMasterEnabled = old;
      notifyListeners();
      await _persistLocal();
      return false;
    }
    return true;
  }

  List<FilterPreset> get _activePushPresets => _presets
      .where((p) => p.enabled && p.notificationsEnabled)
      .toList(growable: false);

  Future<bool> syncPushSubscriptions({bool requestPermission = false}) {
    _syncAgain = true;
    _requestPermissionNext = _requestPermissionNext || requestPermission;

    final running = _syncFuture;
    if (running != null) return running;

    final future = _drainPushSync();
    _syncFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_syncFuture, future)) _syncFuture = null;
      }),
    );
    return future;
  }

  Future<bool> _drainPushSync() async {
    syncingPush = true;
    notifyListeners();
    var ok = true;
    try {
      while (_syncAgain) {
        _syncAgain = false;
        final requestPermission = _requestPermissionNext;
        _requestPermissionNext = false;
        pushError = null;
        ok = await _syncPushOnce(requestPermission: requestPermission);
      }
      return ok;
    } finally {
      syncingPush = false;
      notifyListeners();
    }
  }

  Future<bool> _syncPushOnce({required bool requestPermission}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await _identity.getOrCreate();
      final active = pushMasterEnabled
          ? _activePushPresets
          : const <FilterPreset>[];
      String token = '';
      if (active.isNotEmpty) {
        if (!_push.configured) {
          pushError = 'firebase_not_configured';
          return false;
        }
        token = await _push.token(requestPermission: requestPermission) ?? '';
        if (token.isEmpty) {
          pushError = 'notification_permission_denied';
          return false;
        }
        _ensureTokenRefresh();
      }

      final savedLanguage = prefs.getString(_kUiLanguage)?.trim();
      await _api.syncMobileSubscriptions(
        deviceId: deviceId,
        pushToken: token,
        enabled: pushMasterEnabled,
        platform: defaultTargetPlatform.name,
        language: savedLanguage?.isNotEmpty == true
            ? savedLanguage!
            : ui.PlatformDispatcher.instance.locale.languageCode,
        presets: active.map((p) => p.toJson()).toList(),
      );
      return true;
    } catch (e) {
      pushError = e.toString();
      return false;
    }
  }

  void _ensureTokenRefresh() {
    if (_tokenSub != null) return;
    _tokenSub = _push.tokenRefresh.listen((_) {
      unawaited(syncPushSubscriptions());
    });
  }

  Future<void> _persistPreset(FilterPreset preset) async {
    await _persistLocal();
    await _saved?.putPreset(preset.toJson());
  }

  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPushMaster, pushMasterEnabled);
      await prefs.setString(
        _kPresets,
        jsonEncode(_presets.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }
}
