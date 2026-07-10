import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/filters.dart';

/// A named, saved set of filters the user can re-apply with one tap.
class FilterPreset {
  final String name;
  final Filters filters;
  const FilterPreset(this.name, this.filters);
}

/// Persists the user's named filter presets locally.
class PresetsState extends ChangeNotifier {
  static const _kPresets = 'filterPresets';

  final List<FilterPreset> _presets = [];

  List<FilterPreset> get presets => List.unmodifiable(_presets);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kPresets);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _presets
          ..clear()
          ..addAll(list.map((e) {
            final m = Map<String, dynamic>.from(e);
            return FilterPreset(
              m['name']?.toString() ?? '',
              Filters.fromJson(Map<String, dynamic>.from(m['filters'])),
            );
          }));
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Save (or overwrite by name) a preset.
  Future<void> save(String name, Filters filters) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _presets.removeWhere((p) => p.name.toLowerCase() == trimmed.toLowerCase());
    _presets.add(FilterPreset(trimmed, filters));
    notifyListeners();
    await _persist();
  }

  /// Rename a preset, keeping its filters. No-op if the new name collides with
  /// a different existing preset (case-insensitive).
  Future<void> rename(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final i = _presets.indexWhere((p) => p.name == oldName);
    if (i < 0) return;
    final clash = _presets.any((p) =>
        p.name != oldName && p.name.toLowerCase() == trimmed.toLowerCase());
    if (clash) return;
    _presets[i] = FilterPreset(trimmed, _presets[i].filters);
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String name) async {
    _presets.removeWhere((p) => p.name == name);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kPresets,
        jsonEncode(_presets.map((e) => {'name': e.name, 'filters': e.filters.toJson()}).toList()),
      );
    } catch (_) {}
  }
}
