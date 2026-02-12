import 'package:flutter/material.dart';

/// Types of commands the Lumina voice assistant can process.
enum LuminaCommandType {
  power,
  brightness,
  solidColor,
  effect,
  scene,
  navigate,
  unknown,
}

/// Intent classifications returned by the cloud AI processor.
enum LuminaIntent {
  lightingCommand,
  navigation,
  question,
  guidedCreation,
}

/// Processing tier that produced the result.
enum ProcessingTier { local, cloud }

/// Structured command parsed from user speech or text input.
///
/// Produced by either the local keyword parser (Tier 1) or the cloud AI
/// processor (Tier 2). The [confidence] score determines whether the local
/// result is used immediately or the command is escalated to cloud processing.
class LuminaCommand {
  /// What kind of command this is.
  final LuminaCommandType type;

  /// Arbitrary parameters for execution. Contents depend on [type]:
  ///
  /// - `power`: `{ "on": bool }`
  /// - `brightness`: `{ "brightness": int (0-255), "relative": bool, "delta": int }`
  /// - `solidColor`: `{ "color": Color, "colorName": String }`
  /// - `effect`: `{ "effectId": int, "effectName": String, "speed": int?, "intensity": int? }`
  /// - `scene`: `{ "sceneId": String, "sceneName": String }`
  /// - `navigate`: `{ "route": String, "tabIndex": int? }`
  /// - `unknown`: empty or partial parse data
  final Map<String, dynamic> parameters;

  /// Confidence that this parse is correct (0.0 – 1.0).
  final double confidence;

  /// The original user input that produced this command.
  final String rawText;

  /// Which tier generated this command.
  final ProcessingTier tier;

  const LuminaCommand({
    required this.type,
    required this.parameters,
    required this.confidence,
    required this.rawText,
    this.tier = ProcessingTier.local,
  });

  /// Whether the local parser is confident enough to execute without AI.
  bool get isHighConfidence => confidence > 0.85;

  @override
  String toString() =>
      'LuminaCommand($type, confidence=$confidence, tier=$tier, params=$parameters)';
}

/// Full result from the command processing pipeline including a user-facing
/// response text, optional preview colors, and clarification suggestions.
class LuminaCommandResult {
  /// The parsed command (may be null if the AI returns only a text response).
  final LuminaCommand? command;

  /// What Lumina should say to the user.
  final String responseText;

  /// Optional WLED JSON payload ready to be sent to the device.
  final Map<String, dynamic>? wledPayload;

  /// Preview colors for the LightPreviewStrip widget.
  final List<Color> previewColors;

  /// Suggestion chips for clarification when confidence is low.
  final List<String> clarificationOptions;

  /// Which tier produced this result.
  final ProcessingTier tier;

  const LuminaCommandResult({
    this.command,
    required this.responseText,
    this.wledPayload,
    this.previewColors = const [],
    this.clarificationOptions = const [],
    this.tier = ProcessingTier.local,
  });
}
