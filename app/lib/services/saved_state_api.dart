import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

extension SavedStateApi on ApiService {
  static const _savedStateTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> fetchRemoteSavedState(String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/mobile/saved-state').replace(
      queryParameters: {'deviceId': deviceId},
    );
    final response = await http.get(uri).timeout(_savedStateTimeout);
    final decoded = _decodeSavedStateResponse(response);
    return decoded;
  }

  Future<void> importRemoteSavedState(
    String deviceId, {
    required List<Map<String, dynamic>> favorites,
    required List<Map<String, dynamic>> sorted,
    required List<Map<String, dynamic>> presets,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/mobile/saved-state/import'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'deviceId': deviceId,
            'favorites': favorites,
            'sorted': sorted,
            'presets': presets,
          }),
        )
        .timeout(_savedStateTimeout);
    _decodeSavedStateResponse(response);
  }

  Future<void> mutateRemoteSavedState(
    String deviceId,
    Map<String, dynamic> mutation,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/mobile/saved-state/mutate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'deviceId': deviceId, ...mutation}),
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
