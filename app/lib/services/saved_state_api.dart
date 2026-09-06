import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'installation_identity.dart';

extension SavedStateApi on ApiService {
  static const _savedStateTimeout = Duration(seconds: 15);
  static const _maxRateLimitAttempts = 4;

  Map<String, String> _savedStateHeaders(
    InstallationCredentials credentials, {
    bool json = false,
  }) => {
        'X-Flat-Finder-Device-Id': credentials.deviceId,
        'X-Flat-Finder-Device-Secret': credentials.secret,
        if (json) 'Content-Type': 'application/json',
      };

  Future<http.Response> _sendWithRateLimitRetry(
    Future<http.Response> Function() send,
  ) async {
    http.Response? response;
    for (var attempt = 0; attempt < _maxRateLimitAttempts; attempt++) {
      response = await send().timeout(_savedStateTimeout);
      if (response.statusCode != 429 ||
          attempt == _maxRateLimitAttempts - 1) {
        return response;
      }
      await Future<void>.delayed(_rateLimitDelay(response));
    }
    return response!;
  }

  Duration _rateLimitDelay(http.Response response) {
    var delayMs = 300;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['retryAfterMs'] is num) {
        delayMs = (decoded['retryAfterMs'] as num).round();
      } else {
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        if (retryAfter != null) delayMs = retryAfter * 1000;
      }
    } catch (_) {}
    // A small margin avoids immediately landing on the same limiter boundary.
    return Duration(milliseconds: delayMs.clamp(50, 5000) + 40);
  }

  Future<Map<String, dynamic>> fetchRemoteSavedState(
    InstallationCredentials credentials,
  ) async {
    final response = await _sendWithRateLimitRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/mobile/saved-state'),
        headers: _savedStateHeaders(credentials),
      ),
    );
    return _decodeSavedStateResponse(response);
  }

  Future<void> importRemoteSavedState(
    InstallationCredentials credentials, {
    required List<Map<String, dynamic>> favorites,
    required List<Map<String, dynamic>> sorted,
    required List<Map<String, dynamic>> presets,
  }) async {
    final uri = Uri.parse('$baseUrl/api/mobile/saved-state/import');
    final body = jsonEncode({
      'favorites': favorites,
      'sorted': sorted,
      'presets': presets,
    });
    final headers = _savedStateHeaders(credentials, json: true);
    final response = await _sendWithRateLimitRetry(
      () => http.post(uri, headers: headers, body: body),
    );
    _decodeSavedStateResponse(response);
  }

  Future<void> mutateRemoteSavedState(
    InstallationCredentials credentials,
    Map<String, dynamic> mutation,
  ) async {
    final uri = Uri.parse('$baseUrl/api/mobile/saved-state/mutate');
    final body = jsonEncode(mutation);
    final headers = _savedStateHeaders(credentials, json: true);
    final response = await _sendWithRateLimitRetry(
      () => http.post(uri, headers: headers, body: body),
    );
    _decodeSavedStateResponse(response);
  }
}

Map<String, dynamic> _decodeSavedStateResponse(http.Response response) {
  dynamic decoded;
  try {
    decoded = jsonDecode(response.body);
  } catch (_) {
    throw FormatException(
      'saved-state response is not JSON (HTTP ${response.statusCode})',
    );
  }
  if (decoded is! Map) {
    throw const FormatException('saved-state response must be an object');
  }
  final json = Map<String, dynamic>.from(decoded);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      json['error']?.toString() ?? 'saved-state HTTP ${response.statusCode}',
    );
  }
  return json;
}
