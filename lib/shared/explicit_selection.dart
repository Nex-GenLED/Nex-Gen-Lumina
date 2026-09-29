// Pure Dart. The rule: the app never chooses a device, a controller or a
// pattern on the customer's behalf. `.first` is not a choice.

/// The answer to "which one did the customer pick?" — either the thing they
/// picked, or nothing plus the sentence that says why there is nothing.
class SelectionDecision<T> {
  /// The customer's choice, or null when they have not made one.
  final T? value;

  /// Customer-readable. Non-null exactly when [value] is null.
  final String? reason;

  const SelectionDecision.chosen(T this.value) : reason = null;

  const SelectionDecision.none(String this.reason) : value = null;

  bool get hasSelection => value != null;
}

/// Resolves a selection WITHOUT ever falling back to "the first one".
///
/// [tapped] is what the customer explicitly chose, or null when they have not
/// tapped anything. [noun] names the thing in the customer's words
/// ("controller", "device", "pattern") and is used in the reason.
///
/// Outcomes:
///  * [tapped] is one of [candidates] → that one.
///  * [tapped] is null, exactly one candidate, and [allowSoleCandidate] →
///    that one. One candidate is not a guess: there is nothing else it could
///    be. Off by default, because a save that names no controller is still
///    worth a confirming tap.
///  * anything else → no selection, with the reason. Never `candidates.first`.
///
/// A [tapped] value that is no longer among the candidates (the controller was
/// removed, the pattern left the catalog) is NOT honoured and is NOT replaced:
/// the caller is told it is gone.
SelectionDecision<T> requireExplicitSelection<T>({
  required Iterable<T> candidates,
  required T? tapped,
  required String noun,
  bool allowSoleCandidate = false,
  bool Function(T a, T b)? equals,
}) {
  final same = equals ?? (T a, T b) => a == b;
  final list = candidates.toList(growable: false);

  if (tapped != null) {
    for (final c in list) {
      if (same(c, tapped)) return SelectionDecision.chosen(c);
    }
    return SelectionDecision.none(
        'That $noun is no longer available. Choose another $noun.');
  }

  if (list.isEmpty) {
    return SelectionDecision.none('No $noun found yet.');
  }
  if (list.length == 1 && allowSoleCandidate) {
    return SelectionDecision.chosen(list.single);
  }
  return SelectionDecision.none(list.length == 1
      ? 'Tap the $noun to choose it.'
      : 'Choose a $noun to continue.');
}

/// Looks something up by what the customer asked for, and says so when it is
/// not there — instead of quietly substituting the first entry.
///
/// For the "suggested pattern is not in the catalog" case: the old code
/// applied the FIRST catalog pattern under the suggested pattern's name.
SelectionDecision<T> requireExactMatch<T>({
  required Iterable<T> candidates,
  required bool Function(T candidate) matches,
  required String noun,
  String? requested,
}) {
  for (final c in candidates) {
    if (matches(c)) return SelectionDecision.chosen(c);
  }
  return SelectionDecision.none(requested == null || requested.isEmpty
      ? "That $noun isn't available."
      : '"$requested" isn\'t available.');
}
