import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InstallationCredentials {
  const InstallationCredentials({required this.deviceId, required this.secret});

  final String deviceId;
  final String secret;
}

abstract class InstallationSecretStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureInstallationSecretStore implements InstallationSecretStore {
  SecureInstallationSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'flatFinderInstallationSecretV1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Stable anonymous installation identity used by server-backed user state.
///
/// The device id is an identifier and may live in ordinary preferences. API
/// authorization uses a separate 256-bit secret kept in KeyStore/Keychain; the
/// backend persists only its SHA-256 hash. A future account can claim one or
/// more installation ids without treating the public identifier as a password.
class InstallationIdentity {
  InstallationIdentity({InstallationSecretStore? secretStore})
      : _secretStore = secretStore ?? SecureInstallationSecretStore();

  static const preferenceKey = 'flatFinderDeviceId';

  final InstallationSecretStore _secretStore;

  Future<String> getOrCreate() async => (await credentials()).deviceId;

  Future<InstallationCredentials> credentials() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(preferenceKey)?.trim();
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = newId();
      await prefs.setString(preferenceKey, deviceId);
    }

    var secret = (await _secretStore.read())?.trim().toLowerCase();
    if (secret == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(secret)) {
      secret = newSecret();
      await _secretStore.write(secret);
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
