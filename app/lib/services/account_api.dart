import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'installation_identity.dart';

/// Thrown when the backend refuses a sign-in: `reason` is its check code
/// (expired, bad_audience, ...) or `not_configured` / `http_<status>`.
class AccountException implements Exception {
  const AccountException(this.reason);

  final String reason;

  @override
  String toString() => 'AccountException($reason)';
}

/// The account endpoints (backend: apps/flats src/mobile/mobile-account.js).
///
/// They authenticate with the same installation id and secret as saved state:
/// signing in links THIS installation to the Google account, after which its
/// saved-state calls read and write the account's shared state.
extension AccountApi on ApiService {
  static const _timeout = Duration(seconds: 20);

  Map<String, String> _accountHeaders(InstallationCredentials credentials) => {
        'X-Flat-Finder-Device-Id': credentials.deviceId,
        'X-Flat-Finder-Device-Secret': credentials.secret,
        'Content-Type': 'application/json',
      };

  /// One retry on 429: the backend allows one account call per second per
  /// client, and a double tap should not read as a failure.
  Future<Map<String, dynamic>> _accountCall(
    Future<http.Response> Function() send,
  ) async {
    var response = await send().timeout(_timeout);
    if (response.statusCode == 429) {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      response = await send().timeout(_timeout);
    }
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (response.statusCode == 503) {
      throw const AccountException('not_configured');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AccountException(
        body['reason']?.toString() ?? 'http_${response.statusCode}',
      );
    }
    return body;
  }

  Future<bool> fetchAccountSignedIn(InstallationCredentials credentials) async {
    final body = await _accountCall(
      () => http.get(
        Uri.parse('$baseUrl/api/mobile/account'),
        headers: _accountHeaders(credentials),
      ),
    );
    return body['signedIn'] == true;
  }

  Future<void> linkGoogleAccount(
    InstallationCredentials credentials,
    String idToken,
  ) async {
    final payload = jsonEncode({'idToken': idToken});
    await _accountCall(
      () => http.post(
        Uri.parse('$baseUrl/api/mobile/account/google'),
        headers: _accountHeaders(credentials),
        body: payload,
      ),
    );
  }

  Future<void> signOutAccount(InstallationCredentials credentials) async {
    await _accountCall(
      () => http.post(
        Uri.parse('$baseUrl/api/mobile/account/sign-out'),
        headers: _accountHeaders(credentials),
      ),
    );
  }

  Future<void> deleteAccount(InstallationCredentials credentials) async {
    await _accountCall(
      () => http.post(
        Uri.parse('$baseUrl/api/mobile/account/delete'),
        headers: _accountHeaders(credentials),
      ),
    );
  }
}
