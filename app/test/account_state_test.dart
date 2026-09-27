import 'package:flat_finder/services/google_auth.dart';
import 'package:flat_finder/state/account.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGoogle implements GoogleAuth {
  _FakeGoogle({this.token = 'id-token', this.configured = true});

  String? token;
  @override
  final bool configured;
  int signOuts = 0;

  @override
  Future<String?> signIn() async => token;

  @override
  Future<void> signOut() async => signOuts++;
}

class _FakeBackend implements AccountBackend {
  final calls = <String>[];
  bool remoteSignedIn = false;
  bool fail = false;

  @override
  Future<bool> signedIn() async => remoteSignedIn;

  @override
  Future<void> link(String idToken) async {
    calls.add('link:$idToken');
    if (fail) throw Exception('401');
  }

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<void> delete() async => calls.add('delete');
}

void main() {
  late _FakeBackend backend;
  late _FakeGoogle google;
  late List<String> order;
  late AccountState account;

  setUp(() {
    backend = _FakeBackend();
    google = _FakeGoogle();
    order = [];
    account = AccountState(
      backend,
      google,
      flushPending: () async => order.add('flush'),
      reloadSavedState: () async => order.add('reload'),
    );
  });

  test('sign-in flushes queued changes, links, then reloads saved state',
      () async {
    expect(await account.signIn(), AccountOutcome.linked);
    expect(account.signedIn, isTrue);
    expect(backend.calls, ['link:id-token']);
    // Pending offline changes must be on the server before the merge.
    expect(order, ['flush', 'reload']);
    expect(account.busy, isFalse);
  });

  test('a cancelled Google picker changes nothing', () async {
    google.token = null;
    expect(await account.signIn(), AccountOutcome.cancelled);
    expect(account.signedIn, isFalse);
    expect(backend.calls, isEmpty);
    expect(order, isEmpty);
  });

  test('a refused token reports failure and stays signed out', () async {
    backend.fail = true;
    expect(await account.signIn(), AccountOutcome.failed);
    expect(account.signedIn, isFalse);
    expect(order, ['flush']);
  });

  test('sign-out and delete unlink, forget the Google session and reload',
      () async {
    await account.signIn();
    order.clear();
    expect(await account.signOut(), AccountOutcome.signedOut);
    expect(account.signedIn, isFalse);
    expect(google.signOuts, 1);
    expect(order, ['reload']);

    await account.signIn();
    expect(await account.deleteAccount(), AccountOutcome.deleted);
    expect(backend.calls.last, 'delete');
    expect(google.signOuts, 2);
  });

  test('load reflects the server, and builds without a client id hide it',
      () async {
    backend.remoteSignedIn = true;
    await account.load();
    expect(account.signedIn, isTrue);

    final unconfigured = AccountState(
      backend,
      _FakeGoogle(configured: false),
      flushPending: () async {},
      reloadSavedState: () async {},
    );
    expect(unconfigured.available, isFalse);
    await unconfigured.load();
    expect(unconfigured.signedIn, isFalse);
  });
}
