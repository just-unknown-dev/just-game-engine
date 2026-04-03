/// Fully-resolved player choice — ready for display.
library;

/// A single player choice after localization and condition evaluation have
/// been applied.
///
/// Produced by [DialogueRunner] and emitted via [NarrativeSignals.choices].
///
/// ```dart
/// runner.signals.choices.addListener(() {
///   final opts = runner.signals.choices.value;
///   for (final c in opts) {
///     print('  [${c.index}] ${c.text}${c.isAvailable ? '' : ' (locked)'}');
///   }
/// });
/// ```
class DialogueChoice {
  const DialogueChoice({
    required this.index,
    required this.text,
    this.audioKey,
    this.tags = const [],
    this.isAvailable = true,
  });

  /// Zero-based index of this choice in its [ChoiceSetStatement].
  /// Pass this to [DialogueRunner.selectChoice].
  final int index;

  /// Display text — already localized and variable-substituted.
  final String text;

  /// Optional audio key for a voice line associated with the choice.
  final String? audioKey;

  /// Metadata tags from the Yarn source.
  final List<String> tags;

  /// Whether the condition for this choice evaluated to `true`.
  ///
  /// Unavailable choices should be shown greyed-out or hidden, depending on
  /// your UX. The runner only executes choices whose [isAvailable] is `true`.
  final bool isAvailable;

  @override
  String toString() => '[$index] $text${isAvailable ? '' : ' (unavailable)'}';
}
