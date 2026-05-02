import 'dart:ui' show Locale;

import '../localization/localization_manager.dart';
import 'subtitle_cue.dart';

/// An ordered list of [SubtitleCue] entries that make up a subtitle sequence.
class SubtitleTrack {
  const SubtitleTrack(this.cues);

  /// Build a track by resolving localization keys via [l10n].
  ///
  /// [entries] is a list of records containing timing and the localization key
  /// for each cue.  Strings are resolved once at construction time using the
  /// manager's current locale, so the track is immutable after creation.
  ///
  /// ```dart
  /// SubtitleTrack.localized(
  ///   entries: [
  ///     (start: 0.5, end: 2.5, key: 'cue1'),
  ///     (start: 2.5, end: 6.5, key: 'cue2'),
  ///   ],
  ///   l10n: LocalizationManager.instance!,
  ///   namespace: 'intro',
  /// )
  /// ```
  factory SubtitleTrack.localized({
    required List<({double start, double end, String key})> entries,
    required LocalizationManager l10n,
    String? namespace,
    Locale? locale,
  }) {
    final cues = entries
        .map(
          (e) => SubtitleCue(
            start: e.start,
            end: e.end,
            text: l10n.t(e.key, ns: namespace, locale: locale),
          ),
        )
        .toList(growable: false);
    return SubtitleTrack(cues);
  }

  final List<SubtitleCue> cues;

  /// Returns the active [SubtitleCue] at [elapsed] seconds, or `null` if none
  /// is active at that time.
  SubtitleCue? getActiveCue(double elapsed) {
    for (final cue in cues) {
      if (elapsed >= cue.start && elapsed < cue.end) return cue;
    }
    return null;
  }

  /// End time of the last cue, or `0` for an empty track.
  double get totalDuration => cues.isEmpty ? 0 : cues.last.end;
}
