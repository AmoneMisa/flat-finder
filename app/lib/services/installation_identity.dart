import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Stable anonymous installation identity used by all server-backed user state.
///
/// It deliberately reuses the key that push presets already used, so existing
/// installs keep one identity when favorites/sorted/presets move to Postgre.
/// A future authenticated account can claim one or more installation IDs on the
/// backend without changing the local data model.
class InstallationIdentity {
  static const preferenceKey = 'flatFinderDeviceId';

  Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(preferenceKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    final id = newId();
    await prefs.setString(preferenceKey, id);
    return id;
  }

  static String newId() {
    final random = Random.secure();
    return List<int>.generate(24, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
