import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'installation_identity.dart';

extension SavedStateApi on ApiService {
  static const _savedStateTimeout = Duration(seconds: 15);

  Map<String, String> _savedStateHeaders(
    InstallationCredentials credentials, {
    bool json = false,
  }) => {
        'X-Flat-Finder-Device-Id': credentials.deviceId,
        'X-Flat-Finder-Device-Secret': credentials.secret,
        if (json) 'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> fetchRemoteSavedState(
    InstallationCredentials credentials,
  ) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/mobile/saved-state'),
          headers: _savedStateHeaders(credentials),
        )
        .timeout(_savedStateTimeout);
    return _decodeSavedStateResponse(response);
  }

  Future<void> importRemoteSavedState(
    InstallationCredentials credentials, {
    required List<Map<String, dynamic>> favorites,
    required List<Map<String, dynamic>> sorted,
    required List<Map<String, dynamic>> presets,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/mobile/saved-state/import'),
          headers: _savedStateHeaders(credentials, json: true),
          body: jsonEncode({
            'favorites': favorites,
            'sorted': sorted,
            'presets': presets,
          }),
        )
        .timeout(_savedStateTimeout);
    _decodeSavedStateResponse(response);
  }

  Future<void> mutateRemoteSavedState(
    InstallationCredentials credentials,
    Map<String, dynamic> mutation,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/mobile/saved-state/mutate'),
          headers: _savedStateHeaders(credentials, json: true),
          body: jsonEncode(mutation),
        )
        .timeout(_savedStateTimeout);
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
