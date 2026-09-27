import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper over google_sign_in so [AccountState] can be tested without
/// the platform plugin.
abstract class GoogleAuth {
  /// Whether this build can offer Google sign-in at all.
  bool get configured;

  /// Interactive sign-in; returns the Google ID token, or null when the user
  /// cancelled.
  Future<String?> signIn();

  /// Forgets the Google session on this device, so the next sign-in offers the
  /// account picker again.
  Future<void> signOut();
}

class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth._();

  static final PluginGoogleAuth instance = PluginGoogleAuth._();

  /// The OAuth "Web application" client id. The ID token is issued to it, and
  /// the backend accepts it (GOOGLE_OAUTH_CLIENT_IDS). Android additionally
  /// needs an "Android" client for this package name and signing SHA-1 in the
  /// same Google Cloud project; it is matched automatically, not passed here.
  static const _serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  Future<void>? _initialized;

  @override
  bool get configured => _serverClientId.isNotEmpty;

  Future<void> _ensureInitialized() =>
      _initialized ??= GoogleSignIn.instance.initialize(
        serverClientId: _serverClientId,
      );

  @override
  Future<String?> signIn() async {
    if (!configured) return null;
    await _ensureInitialized();
    try {
      // No scope hint: the backend only needs the subject id in the ID token.
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    if (!configured) return;
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }
}
