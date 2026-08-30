import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/filters.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';

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

/// Saved filters remain local. Only enabled notification presets are mirrored
/// to the Flat Finder backend using an anonymous, locally generated device ID.
class PresetsState extends ChangeNotifier {
  PresetsState(this._api, {PushService? push})
    : _push = push ?? PushService.instance;

  static const _kPresets = 'filterPresets';
  static const _kPushMaster = 'filterPresetPushMaster';
  static const _kDeviceId = 'flatFinderDeviceId';

  final ApiService _api;
  final PushService _push;
  final List<FilterPreset> _presets = [];
  StreamSubscription<String>? _tokenSub;

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
            list.map((entry) {
              final m = Map<String, dynamic>.from(entry as Map);
              final id = m['id']?.toString().trim();
              if (id == null || id.isEmpty) migrated = true;
              return FilterPreset(
                id: id == null || id.isEmpty ? _newId() : id,
                name: m['name']?.toString() ?? '',
                filters: Filters.fromJson(
                  Map<String, dynamic>.from(m['filters'] as Map),
                ),
                enabled: m['enabled'] is bool ? m['enabled'] as bool : true,
                notificationsEnabled: m['notificationsEnabled'] is bool
                    ? m['notificationsEnabled'] as bool
                    : false,
              );
            }),
          );
      }
      if (migrated) await _persist();
      notifyListeners();
      if (pushMasterEnabled && _activePushPresets.isNotEmpty) {
        unawaited(syncPushSubscriptions());
      }
    } catch (_) {
      // Local state must never prevent the apartment feed from opening.
    }
  }

  static String _newId() {
    final random = Random.secure();
    return List<int>.generate(
      24,
      (_) => random.nextInt(256),
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Overwriting a preset by name preserves its ID and notification toggles.
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
    await _persist();
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
    await _persist();
    await syncPushSubscriptions();
  }

  Future<void> remove(String name) async {
    _presets.removeWhere((p) => p.name == name);
    notifyListeners();
    await _persist();
    await syncPushSubscriptions();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final i = _presets.indexWhere((p) => p.id == id);
    if (i < 0 || _presets[i].enabled == enabled) return;
    _presets[i] = _presets[i].copyWith(enabled: enabled);
    notifyListeners();
    await _persist();
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
    await _persist();

    final ok = await syncPushSubscriptions(requestPermission: enabled);
    if (enabled && !ok) {
      _presets[i] = _presets[i].copyWith(notificationsEnabled: false);
      if (_presets.every((p) => !p.notificationsEnabled)) {
        pushMasterEnabled = false;
      }
      notifyListeners();
      await _persist();
      await syncPushSubscriptions();
    }
    return ok;
  }

  Future<bool> setPushMasterEnabled(bool enabled) async {
    final old = pushMasterEnabled;
    pushMasterEnabled = enabled;
    notifyListeners();
    await _persist();
    final ok = await syncPushSubscriptions(
      requestPermission: enabled && _activePushPresets.isNotEmpty,
    );
    if (enabled && !ok && _activePushPresets.isNotEmpty) {
      pushMasterEnabled = old;
      notifyListeners();
      await _persist();
      return false;
    }
    return true;
  }

  List<FilterPreset> get _activePushPresets => _presets
      .where((p) => p.enabled && p.notificationsEnabled)
      .toList(growable: false);

  Future<bool> syncPushSubscriptions({bool requestPermission = false}) async {
    if (syncingPush) return pushError == null;
    syncingPush = true;
    pushError = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString(_kDeviceId);
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = _newId();
        await prefs.setString(_kDeviceId, deviceId);
      }

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

      await _api.syncMobileSubscriptions(
        deviceId: deviceId,
        pushToken: token,
        enabled: pushMasterEnabled,
        platform: defaultTargetPlatform.name,
        language: ui.PlatformDispatcher.instance.locale.languageCode,
        presets: active.map((p) => p.toJson()).toList(),
      );
      return true;
    } catch (e) {
      pushError = e.toString();
      return false;
    } finally {
      syncingPush = false;
      notifyListeners();
    }
  }

  void _ensureTokenRefresh() {
    if (_tokenSub != null) return;
    _tokenSub = _push.tokenRefresh.listen((_) {
      unawaited(syncPushSubscriptions());
    });
  }

  Future<void> _persist() async {
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
