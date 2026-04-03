/// Fully-resolved dialogue line — ready for display.
library;

/// A single dialogue line after localization and variable substitution have
/// been applied.
///
/// Produced by [DialogueRunner] and emitted via [NarrativeSignals.currentLine].
///
/// ```dart
/// runner.signals.currentLine.addListener(() {
///   final line = runner.signals.currentLine.value;
///   if (line != null) {
///     print('${line.character ?? 'Narrator'}: ${line.text}');
///   }
/// });
/// ```
class DialogueLine {
  const DialogueLine({
    this.character,
    required this.text,
    this.audioKey,
    this.tags = const [],
    this.lineKey,
  });

  /// Speaker name, or `null` for narrator/ambient lines.
  final String? character;

  /// Displayed text — already localized and variable-substituted.
  final String text;

  /// Optional audio clip key for voice-over playback.
  final String? audioKey;

  /// Metadata tags carried from the Yarn source (e.g. `#emotion:happy`).
  final List<String> tags;

  /// Original localization key — useful for lip-sync triggers or subtitle IDs.
  final String? lineKey;

  /// `true` when no character name is attributed (pure narration).
  bool get isNarration => character == null;

  @override
  String toString() =>
      character != null ? '$character: $text' : '[Narration] $text';
}
