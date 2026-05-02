/// A single timed subtitle entry.
class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  /// Start time in seconds (inclusive).
  final double start;

  /// End time in seconds (exclusive).
  final double end;

  /// Display text for this cue.
  final String text;
}
