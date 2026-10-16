/// A single timed subtitle entry.
class SubtitleCue {
  /// The cue showing [text] from [start] up to, not including, [end]; both
  /// in seconds.
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
