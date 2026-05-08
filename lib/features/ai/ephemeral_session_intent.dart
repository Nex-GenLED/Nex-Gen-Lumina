// lib/features/ai/ephemeral_session_intent.dart
//
// Typed model for the `ephemeralSession` field emitted by the cloud AI
// processor when the user combines a sports/team event with an "after"
// or "revert" state. The raw map (kept on `LuminaCommandResult.ephemeralSession`)
// passes through `fromJson` here for validation before any handler dispatches
// it into the EphemeralGameSessionService.

import 'package:flutter/foundation.dart';

/// Item #51 Prompt 3 — typed accessor for the cloud AI's ephemeralSession
/// JSON payload. Schema is defined in lumina_ai_service.dart's system prompt.
class EphemeralSessionIntent {
  /// Currently always 'post_game_revert'. Future ephemeral session types
  /// (e.g. event-bounded) may extend this set.
  final String type;

  /// Team slug from `kTeamColors` map (e.g. 'mlb_royals'). The AI is
  /// instructed to emit the slug in `<sport>_<team>` snake_case format.
  final String teamSlug;

  /// Anchor for resolving the target game: 'today' | 'tonight' |
  /// 'tomorrow' | 'next' | 'specific_date'.
  final String gameAnchorType;

  /// Calendar date in YYYY-MM-DD format. Populated only when
  /// [gameAnchorType] is 'specific_date'; null otherwise.
  final String? gameAnchorSpecificDate;

  /// Full WLED JSON payload to apply when the resolved game ends + the
  /// 30-minute post-game countdown completes.
  final Map<String, dynamic> revertWledPayload;

  /// 1-3 word display name reflecting the user's "after" phrasing
  /// (e.g. 'Normal Blue', 'Warm White').
  final String revertLabel;

  const EphemeralSessionIntent({
    required this.type,
    required this.teamSlug,
    required this.gameAnchorType,
    this.gameAnchorSpecificDate,
    required this.revertWledPayload,
    required this.revertLabel,
  });

  static const _validAnchors = {
    'today',
    'tonight',
    'tomorrow',
    'next',
    'specific_date',
  };

  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Parse and validate a raw `ephemeralSession` map from the AI response.
  /// Returns null when the input is null or fails any validation check.
  /// All validation failures log a debug message identifying the missing
  /// or malformed field.
  static EphemeralSessionIntent? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final type = json['type'] as String?;
    if (type == null || type != 'post_game_revert') {
      debugPrint(
          '[EphemeralSessionIntent] invalid or missing type: $type (expected post_game_revert)');
      return null;
    }

    final teamSlug = json['teamSlug'] as String?;
    if (teamSlug == null || teamSlug.isEmpty) {
      debugPrint('[EphemeralSessionIntent] missing or empty teamSlug');
      return null;
    }

    final gameAnchor = json['gameAnchor'];
    if (gameAnchor is! Map) {
      debugPrint(
          '[EphemeralSessionIntent] missing or invalid gameAnchor (expected Map)');
      return null;
    }

    final anchorType = gameAnchor['type'] as String?;
    if (anchorType == null || !_validAnchors.contains(anchorType)) {
      debugPrint(
          '[EphemeralSessionIntent] invalid gameAnchor.type: $anchorType (expected one of $_validAnchors)');
      return null;
    }

    final specificDate = gameAnchor['specificDate'] as String?;
    if (anchorType == 'specific_date') {
      if (specificDate == null || !_datePattern.hasMatch(specificDate)) {
        debugPrint(
            '[EphemeralSessionIntent] specific_date anchor requires YYYY-MM-DD specificDate, got: $specificDate');
        return null;
      }
    }

    final wledRaw = json['revertWledPayload'];
    if (wledRaw is! Map) {
      debugPrint(
          '[EphemeralSessionIntent] missing or invalid revertWledPayload (expected Map)');
      return null;
    }

    final revertLabel = json['revertLabel'] as String?;
    if (revertLabel == null || revertLabel.isEmpty) {
      debugPrint(
          '[EphemeralSessionIntent] missing or empty revertLabel');
      return null;
    }

    return EphemeralSessionIntent(
      type: type,
      teamSlug: teamSlug,
      gameAnchorType: anchorType,
      gameAnchorSpecificDate:
          anchorType == 'specific_date' ? specificDate : null,
      revertWledPayload: Map<String, dynamic>.from(wledRaw),
      revertLabel: revertLabel,
    );
  }

  /// Always true on a non-null instance. fromJson returns null on any
  /// validation failure, so a constructed intent is by definition valid.
  /// Provided so handler dispatch sites can read `intent != null && intent.isValid`
  /// without re-parsing — useful when the contract evolves to include
  /// soft-validation states.
  bool get isValid => true;

  @override
  String toString() {
    final dateSuffix = gameAnchorSpecificDate != null
        ? '@$gameAnchorSpecificDate'
        : '';
    return 'EphemeralSessionIntent(type=$type, slug=$teamSlug, '
        'anchor=$gameAnchorType$dateSuffix, label=$revertLabel)';
  }
}
