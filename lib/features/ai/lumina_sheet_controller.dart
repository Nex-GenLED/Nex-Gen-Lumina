import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// The three visual states the Lumina bottom sheet can be in.
enum LuminaSheetMode { compact, listening, expanded }

/// Role for a conversation message.
enum LuminaMessageRole { user, assistant, thinking }

/// A single message in the Lumina conversation thread.
class LuminaMessage {
  final LuminaMessageRole role;
  final String text;
  final LuminaPatternPreview? preview;
  final Map<String, dynamic>? wledPayload;
  bool? feedbackGiven;

  LuminaMessage({
    required this.role,
    required this.text,
    this.preview,
    this.wledPayload,
    this.feedbackGiven,
  });

  factory LuminaMessage.user(String text) =>
      LuminaMessage(role: LuminaMessageRole.user, text: text);

  factory LuminaMessage.assistant(
    String text, {
    LuminaPatternPreview? preview,
    Map<String, dynamic>? wledPayload,
  }) =>
      LuminaMessage(
        role: LuminaMessageRole.assistant,
        text: text,
        preview: preview,
        wledPayload: wledPayload,
      );

  factory LuminaMessage.thinking() =>
      LuminaMessage(role: LuminaMessageRole.thinking, text: '');
}

/// Pattern preview data attached to assistant messages.
class LuminaPatternPreview {
  final String? patternName;
  final List<Color> colors;
  final List<String> colorNames;
  final int? effectId;
  final String? effectName;
  final String? direction;
  final bool isStatic;
  final int? speed;
  final int? intensity;
  final int? paletteId;

  const LuminaPatternPreview({
    this.patternName,
    required this.colors,
    this.colorNames = const [],
    this.effectId,
    this.effectName,
    this.direction,
    this.isStatic = false,
    this.speed,
    this.intensity,
    this.paletteId,
  });
}

/// Immutable state snapshot for the Lumina sheet.
class LuminaSheetState {
  final bool isOpen;
  final LuminaSheetMode mode;
  final List<LuminaMessage> messages;
  final bool isThinking;
  final String transcription;
  final Map<String, dynamic>? activePatternContext;
  final LuminaPatternPreview? activePreview;

  const LuminaSheetState({
    this.isOpen = false,
    this.mode = LuminaSheetMode.compact,
    this.messages = const [],
    this.isThinking = false,
    this.transcription = '',
    this.activePatternContext,
    this.activePreview,
  });

  bool get hasActiveSession => messages.isNotEmpty;

  LuminaSheetState copyWith({
    bool? isOpen,
    LuminaSheetMode? mode,
    List<LuminaMessage>? messages,
    bool? isThinking,
    String? transcription,
    Map<String, dynamic>? activePatternContext,
    LuminaPatternPreview? activePreview,
    bool clearPatternContext = false,
  }) {
    return LuminaSheetState(
      isOpen: isOpen ?? this.isOpen,
      mode: mode ?? this.mode,
      messages: messages ?? this.messages,
      isThinking: isThinking ?? this.isThinking,
      transcription: transcription ?? this.transcription,
      activePatternContext:
          clearPatternContext ? null : (activePatternContext ?? this.activePatternContext),
      activePreview:
          clearPatternContext ? null : (activePreview ?? this.activePreview),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the Lumina bottom sheet state: open/close, mode transitions,
/// conversation messages, and pattern context.
class LuminaSheetController extends Notifier<LuminaSheetState> {
  @override
  LuminaSheetState build() => const LuminaSheetState();

  /// Open the sheet in compact mode (quick tap).
  void openCompact() {
    state = state.copyWith(isOpen: true, mode: LuminaSheetMode.compact);
  }

  /// Open the sheet in listening mode (long press).
  void openListening() {
    state = state.copyWith(
      isOpen: true,
      mode: LuminaSheetMode.listening,
      transcription: '',
    );
  }

  /// Close the sheet (does NOT clear conversation).
  void close() {
    state = state.copyWith(isOpen: false);
  }

  /// Transition to a specific mode.
  void setMode(LuminaSheetMode mode) {
    state = state.copyWith(mode: mode);
  }

  /// Update live speech-to-text transcription.
  void updateTranscription(String text) {
    state = state.copyWith(transcription: text);
  }

  /// Add a user message and mark as thinking.
  void addUserMessage(String text) {
    final updated = [...state.messages, LuminaMessage.user(text)];
    state = state.copyWith(
      messages: updated,
      isThinking: true,
      mode: LuminaSheetMode.expanded,
    );
  }

  /// Add an assistant response.
  void addAssistantMessage(
    String text, {
    LuminaPatternPreview? preview,
    Map<String, dynamic>? wledPayload,
  }) {
    final updated = [
      ...state.messages,
      LuminaMessage.assistant(text, preview: preview, wledPayload: wledPayload),
    ];
    state = state.copyWith(
      messages: updated,
      isThinking: false,
      activePatternContext:
          wledPayload != null ? {'wled': wledPayload} : state.activePatternContext,
      activePreview: preview ?? state.activePreview,
    );
  }

  /// Mark thinking state without adding a message.
  void setThinking(bool thinking) {
    state = state.copyWith(isThinking: thinking);
  }

  /// Store pattern context for refinement operations.
  void setPatternContext(
      Map<String, dynamic>? context, LuminaPatternPreview? preview) {
    state = state.copyWith(
      activePatternContext: context,
      activePreview: preview,
    );
  }

  /// Clear conversation and pattern context.
  void clearSession() {
    state = state.copyWith(
      messages: [],
      isThinking: false,
      transcription: '',
      clearPatternContext: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global provider for the Lumina bottom sheet state.
final luminaSheetProvider =
    NotifierProvider<LuminaSheetController, LuminaSheetState>(
  LuminaSheetController.new,
);
