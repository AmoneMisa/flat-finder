import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A newer release found on whiteslove.me, ready to hand to the update dialog.
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.apkUrl});

  final String version;
  final String apkUrl;
}

/// Checks whiteslove.me (the same site the APK itself is downloaded from) for
/// a newer release than the one currently installed.
///
/// The site publishes a small `version.json` next to the APK files, updated
/// by hand on each release — see `public/files/version.json` in the website
/// repo. There is no backend endpoint for this: the APK isn't served by the
/// flats API, so checking against the static file the download link already
/// points at avoids a needless cross-service dependency.
class UpdateService {
  UpdateService._();

  static const String _versionUrl = 'https://whiteslove.me/files/version.json';
  static const String _lastCheckKey = 'update.lastCheckedAt';
  static const Duration _minCheckInterval = Duration(hours: 12);

  /// Returns an update only if one is available and this device hasn't been
  /// asked about it too recently. Never throws — a flaky network shouldn't
  /// block app startup, so any failure just means "no update reported".
  static Future<AvailableUpdate?> checkForUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckedMs = prefs.getInt(_lastCheckKey) ?? 0;
      final lastChecked = DateTime.fromMillisecondsSinceEpoch(lastCheckedMs);
      if (DateTime.now().difference(lastChecked) < _minCheckInterval) {
        return null;
      }

      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 5));
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final versionCode = int.tryParse(json['versionCode']?.toString() ?? '');
      final version = json['version']?.toString();
      final apkUrl = json['apkUrl']?.toString();
      if (versionCode == null || version == null || apkUrl == null) {
        return null;
      }

      final info = await PackageInfo.fromPlatform();
      final installedCode = int.tryParse(info.buildNumber) ?? 0;
      if (versionCode <= installedCode) return null;

      return AvailableUpdate(version: version, apkUrl: apkUrl);
    } catch (_) {
      return null;
    }
  }
}
