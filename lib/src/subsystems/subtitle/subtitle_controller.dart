import 'package:just_signals/just_signals.dart';

import 'subtitle_track.dart';

/// Drives subtitle playback from a [SubtitleTrack].
///
/// Call [update] every frame (or from a Ticker) with the current elapsed
/// time in seconds.  [currentText] fires only when the visible cue changes,
/// so widgets rebuild at most once per cue boundary.
class SubtitleController {
  SubtitleController({required SubtitleTrack track}) : _track = track;

  final SubtitleTrack _track;
  String? _activeCueText;

  /// Reactive current subtitle text.  `null` means no subtitle is showing.
  final Signal<String?> currentText = Signal<String?>(null);

  /// Total duration of the track in seconds (end time of the last cue).
  double get totalDuration => _track.totalDuration;

  /// Advance the controller to [elapsedSeconds] and update [currentText] if
  /// the active cue has changed.
  void update(double elapsedSeconds) {
    final cue = _track.getActiveCue(elapsedSeconds);
    final next = cue?.text;
    if (next != _activeCueText) {
      _activeCueText = next;
      currentText.value = next;
    }
  }

  void reset() {
    _activeCueText = null;
    currentText.value = null;
  }
}
