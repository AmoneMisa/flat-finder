import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class ForegroundPush {
  const ForegroundPush({
    required this.title,
    required this.body,
    required this.publicId,
  });

  final String? title;
  final String? body;
  final int? publicId;
}

/// Thin FCM client for anonymous apartment-preset notifications.
///
/// No account or device MAC is used. Firebase options are supplied at build
/// time so no project-specific google-services.json needs to live in Git:
///
/// --dart-define=FIREBASE_API_KEY=...
/// --dart-define=FIREBASE_APP_ID=...
/// --dart-define=FIREBASE_MESSAGING_SENDER_ID=...
/// --dart-define=FIREBASE_PROJECT_ID=...
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  final _listingOpens = StreamController<int>.broadcast();
  Stream<int> get listingOpens => _listingOpens.stream;
  final _foregroundPushes = StreamController<ForegroundPush>.broadcast();
  Stream<ForegroundPush> get foregroundPushes => _foregroundPushes.stream;

  bool _initialized = false;
  bool _listenersAttached = false;

  bool get configured =>
      !kIsWeb &&
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty;

  Future<bool> _ensureInitialized() async {
    if (!configured) return false;
    if (!_initialized) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: _apiKey,
            appId: _appId,
            messagingSenderId: _senderId,
            projectId: _projectId,
          ),
        );
      }
      _initialized = true;
    }
    if (!_listenersAttached) {
      _listenersAttached = true;
      FirebaseMessaging.onMessage.listen(_emitForegroundPush);
      FirebaseMessaging.onMessageOpenedApp.listen(_emitListing);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        // Let the widget tree finish mounting before a cold-start navigation.
        scheduleMicrotask(() => _emitListing(initial));
      }
    }
    return true;
  }

  void _emitListing(RemoteMessage message) {
    final id = _publicId(message);
    if (id != null && id > 0) _listingOpens.add(id);
  }

  void _emitForegroundPush(RemoteMessage message) {
    _foregroundPushes.add(ForegroundPush(
      title: message.notification?.title,
      body: message.notification?.body,
      publicId: _publicId(message),
    ));
  }

  int? _publicId(RemoteMessage message) {
    final raw = message.data['publicId'];
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<String?> token({bool requestPermission = false}) async {
    if (!await _ensureInitialized()) return null;
    if (requestPermission) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }
    }
    return FirebaseMessaging.instance.getToken();
  }

  Stream<String> get tokenRefresh async* {
    if (!await _ensureInitialized()) return;
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }
}
