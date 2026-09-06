import 'dart:async';

/// Cooperative cancellation for long-lived request workflows such as
/// translation submit + polling. It cannot retroactively abort a top-level
/// `http.get`, but it interrupts waits immediately and prevents any subsequent
/// poll after the owning UI has gone away.
class RequestCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const RequestCancelledException();
  }
}

class RequestCancelledException implements Exception {
  const RequestCancelledException();

  @override
  String toString() => 'Request cancelled';
}

Future<void> waitForDelayOrCancellation(
  Duration duration,
  RequestCancellation? cancellation,
) async {
  if (cancellation == null) {
    await Future<void>.delayed(duration);
    return;
  }
  cancellation.throwIfCancelled();
  await Future.any<void>([
    Future<void>.delayed(duration),
    cancellation.whenCancelled,
  ]);
  cancellation.throwIfCancelled();
}
