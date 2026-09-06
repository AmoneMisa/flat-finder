import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class InstallationCredentials {
  const InstallationCredentials({required this.deviceId, required this.secret});

  final String deviceId;
  final String secret;
}

/// Stable anonymous installation identity used by server-backed user state.
///
/// The public-ish device id is reused from push subscriptions. Saved-state API
/// access additionally uses a separate 256-bit secret; only its SHA-256 hash is
/// stored by PostgreSQL. A future signed-in account can claim installation IDs
/// without treating the identifier itself as authentication.
class InstallationIdentity {
  static const preferenceKey = 'flatFinderDeviceId';
  static const secretPreferenceKey = 'flatFinderInstallationSecretV1';

  Future<String> getOrCreate() async => (await credentials()).deviceId;

  Future<InstallationCredentials> credentials() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(preferenceKey)?.trim();
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = newId();
      await prefs.setString(preferenceKey, deviceId);
    }

    var secret = prefs.getString(secretPreferenceKey)?.trim().toLowerCase();
    if (secret == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(secret)) {
      secret = newSecret();
      await prefs.setString(secretPreferenceKey, secret);
    }

    return InstallationCredentials(deviceId: deviceId, secret: secret);
  }

  static String newId() => _randomHex(24);
  static String newSecret() => _randomHex(32);

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List<int>.generate(bytes, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
