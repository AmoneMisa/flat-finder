import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flat_finder/services/installation_identity.dart';

class _MemorySecretStore implements InstallationSecretStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('credentials keep one public installation id and one private secret', () async {
    final secrets = _MemorySecretStore();
    final identity = InstallationIdentity(secretStore: secrets);

    final first = await identity.credentials();
    final second = await identity.credentials();

    expect(first.deviceId, second.deviceId);
    expect(first.deviceId, matches(RegExp(r'^[a-f0-9]{48}$')));
    expect(first.secret, second.secret);
    expect(first.secret, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(secrets.value, first.secret);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InstallationIdentity.preferenceKey), first.deviceId);
    expect(prefs.getString('flatFinderInstallationSecretV1'), isNull,
        reason: 'the API credential must never fall back to SharedPreferences');
  });

  test('existing push device id is reused when saved-state sync is enabled', () async {
    const existing = '0123456789abcdef0123456789abcdef0123456789abcdef';
    SharedPreferences.setMockInitialValues({
      InstallationIdentity.preferenceKey: existing,
    });
    final identity = InstallationIdentity(secretStore: _MemorySecretStore());

    final credentials = await identity.credentials();

    expect(credentials.deviceId, existing);
    expect(credentials.secret.length, 64);
  });
}
