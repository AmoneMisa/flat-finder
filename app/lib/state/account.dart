import 'package:flutter/foundation.dart';

import '../services/account_api.dart';
import '../services/api_service.dart';
import '../services/google_auth.dart';
import '../services/installation_identity.dart';

/// The account calls [AccountState] needs, so tests can stand in for the API.
abstract class AccountBackend {
  Future<bool> signedIn();
  Future<void> link(String idToken);
  Future<void> signOut();
  Future<void> delete();
}

class ApiAccountBackend implements AccountBackend {
  ApiAccountBackend(this._api, {InstallationIdentity? identity})
      : _identity = identity ?? InstallationIdentity();

  final ApiService _api;
  final InstallationIdentity _identity;

  @override
  Future<bool> signedIn() async =>
      _api.fetchAccountSignedIn(await _identity.credentials());

  @override
  Future<void> link(String idToken) async =>
      _api.linkGoogleAccount(await _identity.credentials(), idToken);

  @override
  Future<void> signOut() async =>
      _api.signOutAccount(await _identity.credentials());

  @override
  Future<void> delete() async =>
      _api.deleteAccount(await _identity.credentials());
}

enum AccountOutcome { linked, cancelled, signedOut, deleted, failed }

/// "Sign in with Google": joins this phone to the account the website and
/// other phones use, so saved flats, sorted collections and presets (with
/// their notification flags) are shared.
///
/// The backend does the merging -- linking adds this installation's saved
/// state to the account's, signing out leaves this installation empty -- so
/// after every change the app simply reloads saved state from the server and
/// re-registers push subscriptions for this device's token.
class AccountState extends ChangeNotifier {
  AccountState(
    this._backend,
    this._google, {
    required Future<void> Function() flushPending,
    required Future<void> Function() reloadSavedState,
  })  : _flushPending = flushPending,
        _reloadSavedState = reloadSavedState;

  final AccountBackend _backend;
  final GoogleAuth _google;
  final Future<void> Function() _flushPending;
  final Future<void> Function() _reloadSavedState;

  bool signedIn = false;
  bool busy = false;

  bool get available => _google.configured;

  Future<void> load() async {
    if (!available) return;
    try {
      signedIn = await _backend.signedIn();
      notifyListeners();
    } catch (_) {
      // Offline: keep showing the last known state (signed out by default).
    }
  }

  Future<AccountOutcome> signIn() => _run(() async {
        final idToken = await _google.signIn();
        if (idToken == null || idToken.isEmpty) return AccountOutcome.cancelled;
        // Changes still queued offline must reach this installation's saved
        // state first, or the merge into the account would miss them.
        await _flushPending();
        await _backend.link(idToken);
        signedIn = true;
        await _reloadSavedState();
        return AccountOutcome.linked;
      });

  Future<AccountOutcome> signOut() => _run(() async {
        await _backend.signOut();
        await _forgetGoogleSession();
        signedIn = false;
        await _reloadSavedState();
        return AccountOutcome.signedOut;
      });

  Future<AccountOutcome> deleteAccount() => _run(() async {
        await _backend.delete();
        await _forgetGoogleSession();
        signedIn = false;
        await _reloadSavedState();
        return AccountOutcome.deleted;
      });

  Future<void> _forgetGoogleSession() async {
    try {
      await _google.signOut();
    } catch (_) {
      // The backend link is what matters; the picker simply shows next time.
    }
  }

  Future<AccountOutcome> _run(Future<AccountOutcome> Function() action) async {
    if (busy) return AccountOutcome.failed;
    busy = true;
    notifyListeners();
    try {
      return await action();
    } catch (_) {
      return AccountOutcome.failed;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
