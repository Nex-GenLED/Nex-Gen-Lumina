// Pure Dart — no Flutter, no Riverpod — so services, notifiers, widgets and
// the bench CLI can all return and read the same type.

/// Why a write did not land. Lets a snackbar say the right thing instead of
/// collapsing every failure into "check your connection".
enum WriteFailureKind {
  /// Stopped before anything was sent: no controller, no channels selected,
  /// away from home with no remote access. Nothing reached the lights.
  blocked,

  /// Sent (or attempted) and nothing answered: timeout, socket error, the
  /// bridge never acknowledged.
  unreachable,

  /// The write was refused on purpose — wrong device at that address, a
  /// security rule, a guard that declined it. Retrying will not help.
  refused,

  /// The transport cannot carry this kind of write at all (for example a
  /// hardware-settings change while away from home).
  unsupported,

  /// The write threw something unexpected.
  error,
}

/// The outcome of one write — to a controller, to the account, to anything
/// the customer is waiting on.
///
/// THE RULE THIS TYPE EXISTS FOR: a write returns what happened, and the
/// message the customer sees is chosen from that. Not from the step before
/// the write, and not from nothing. `Future<void>` and `catch → debugPrint`
/// both make that impossible, which is how "Saved", "Applied" and "Synced"
/// came to be shown for writes that had failed.
///
/// [message] is always customer-readable: no exception text, no status codes,
/// no ids. [error] carries the underlying cause for logs only.
class WriteResult {
  final bool ok;

  /// Null when [ok].
  final WriteFailureKind? failure;

  /// What to tell the customer. On success this is the success copy, when the
  /// caller supplied one; on failure it is the reason.
  final String? message;

  /// The underlying exception, for logging. Never shown.
  final Object? error;

  /// True once the failure has been put on the shared failure state the
  /// dashboard renders. A caller that sees `reported` must NOT show a second
  /// failure snackbar for the same write.
  final bool reported;

  const WriteResult.success({this.message})
      : ok = true,
        failure = null,
        error = null,
        reported = false;

  const WriteResult.failed(
    WriteFailureKind kind, {
    this.message,
    this.error,
    this.reported = false,
  })  : ok = false,
        failure = kind;

  /// Nothing was sent, and [reason] says why in the customer's words.
  const WriteResult.blocked(String reason)
      : ok = false,
        failure = WriteFailureKind.blocked,
        message = reason,
        error = null,
        reported = false;

  /// Adapts the `Future<bool>` contract most repositories still speak.
  /// `false` carries no cause, so the failure is [WriteFailureKind.unreachable]
  /// unless the caller knows better and passes [failureKind].
  factory WriteResult.fromBool(
    bool ok, {
    String? onSuccess,
    String? onFailure,
    WriteFailureKind failureKind = WriteFailureKind.unreachable,
  }) =>
      ok
          ? WriteResult.success(message: onSuccess)
          : WriteResult.failed(failureKind, message: onFailure);

  bool get failed => !ok;

  /// Nothing reached the lights or the account — as opposed to a write that
  /// was attempted and lost.
  bool get wasBlocked => failure == WriteFailureKind.blocked;

  WriteResult copyWith({String? message, bool? reported}) => ok
      ? WriteResult.success(message: message ?? this.message)
      : WriteResult.failed(
          failure!,
          message: message ?? this.message,
          error: error,
          reported: reported ?? this.reported,
        );

  @override
  String toString() => ok
      ? 'WriteResult.success(${message ?? ''})'
      : 'WriteResult.${failure!.name}(${message ?? ''})';
}

/// Runs [write] and converts anything it throws into a [WriteResult], so a
/// caller never needs its own try/catch to find out whether a write landed.
///
/// [onError] maps a thrown object to a failure kind; by default every throw is
/// [WriteFailureKind.error].
Future<WriteResult> guardWrite(
  Future<WriteResult> Function() write, {
  String? onFailure,
  WriteFailureKind Function(Object error)? onError,
}) async {
  try {
    final result = await write();
    if (result.ok || result.message != null || onFailure == null) return result;
    return result.copyWith(message: onFailure);
  } catch (e) {
    return WriteResult.failed(
      onError?.call(e) ?? WriteFailureKind.error,
      message: onFailure,
      error: e,
    );
  }
}
