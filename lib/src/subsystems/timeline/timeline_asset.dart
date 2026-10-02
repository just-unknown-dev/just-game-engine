/// A timeline: tracks on one clock. Saved as `.timeline.json`, or inline in
/// the component that plays it.
library;

import '../../ecs/serialization/migration_hooks.dart';
import 'timeline_format.dart';
import 'dart:convert';

import 'timeline_track.dart';
import 'tracks/property_track.dart';

/// What happens when time reaches the end.
enum TimelineWrap {
  /// Stops on the last frame.
  once,

  /// Starts over.
  loop,

  /// Runs back to the start, then forwards again.
  pingPong,
}

/// A named time: somewhere to play from, something to snap to.
class TimelineMarker {
  /// A marker called [name], [time] seconds from the start.
  const TimelineMarker({required this.time, required this.name});

  /// Seconds from the timeline's start.
  final double time;

  /// What [TimelineAsset.markerNamed] — and so playing from a marker —
  /// finds it by.
  final String name;

  /// This marker as a JSON map with `time` and `name`.
  Map<String, dynamic> toJson() => {'time': time, 'name': name};

  /// Reads [toJson]'s shape; a missing `time` is 0 and a missing `name` is
  /// empty.
  factory TimelineMarker.fromJson(Map<String, dynamic> json) => TimelineMarker(
    time: (json['time'] as num?)?.toDouble() ?? 0,
    name: json['name'] as String? ?? '',
  );
}

/// Tracks on one clock: what a `.timeline.json` holds, or what a Timeline
/// Player keeps inline. Immutable — an editor makes a new one with
/// [copyWith] — so one asset can be shared by every player of it.
class TimelineAsset {
  /// A timeline of [tracks] lasting [duration] seconds (at or below zero,
  /// playback runs to [contentEnd]), played once by default. Both lists
  /// are copied into unmodifiable ones, [markers] sorted by time.
  TimelineAsset({
    this.name = '',
    this.duration = 1.0,
    this.fps = 30,
    this.wrap = TimelineWrap.once,
    List<TimelineTrack> tracks = const [],
    List<TimelineMarker> markers = const [],
  }) : tracks = List.unmodifiable(tracks),
       markers = List.unmodifiable(
         List.of(markers)..sort((a, b) => a.time.compareTo(b.time)),
       );

  /// The version of the file format this engine writes
  /// ([TimelineFormat.current]). Older files are brought up to it as they
  /// are read.
  static const int formatVersion = TimelineFormat.current;

  /// What a timeline file's name ends with.
  static const String fileExtension = 'timeline.json';

  /// A display name; empty for none, and then not saved.
  final String name;

  /// Seconds.
  final double duration;

  /// Frames per second — how an editor divides and snaps time. Playback is
  /// continuous and does not care.
  final int fps;

  /// What happens when time reaches the end; a player may impose its own.
  final TimelineWrap wrap;

  /// Its rows, in the order they run each step. Unmodifiable.
  final List<TimelineTrack> tracks;

  /// Its markers, sorted by time. Unmodifiable.
  final List<TimelineMarker> markers;

  /// When the last key, event or block on any track is.
  double get contentEnd =>
      tracks.fold(0.0, (end, t) => t.end > end ? t.end : end);

  /// The earliest marker called [name], or null.
  TimelineMarker? markerNamed(String name) {
    for (final m in markers) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// The property tracks, which is what most callers want to walk.
  Iterable<PropertyTrack> get propertyTracks =>
      tracks.whereType<PropertyTrack>();

  /// A copy with the given fields replaced; the tracks themselves are
  /// shared, being immutable.
  TimelineAsset copyWith({
    String? name,
    double? duration,
    int? fps,
    TimelineWrap? wrap,
    List<TimelineTrack>? tracks,
    List<TimelineMarker>? markers,
  }) => TimelineAsset(
    name: name ?? this.name,
    duration: duration ?? this.duration,
    fps: fps ?? this.fps,
    wrap: wrap ?? this.wrap,
    tracks: tracks ?? this.tracks,
    markers: markers ?? this.markers,
  );

  /// This timeline with the track at [index] replaced.
  TimelineAsset withTrackAt(int index, TimelineTrack track) => copyWith(
    tracks: [
      for (var i = 0; i < tracks.length; i++) i == index ? track : tracks[i],
    ],
  );

  /// What is wrong with this timeline by itself — not whether the entities
  /// and fields it names exist, which only a scene can answer.
  List<String> validate() {
    final problems = <String>[];
    if (duration <= 0) problems.add('The duration is not above zero.');
    if (fps <= 0) problems.add('The frame rate is not above zero.');
    final seen = <String>{};
    for (final track in tracks) {
      if (track is UnknownTrack) {
        problems.add(
          track.error == null
              ? 'A track is of the unknown kind "${track.kind}".'
              : 'A "${track.kind}" track could not be read: ${track.error}',
        );
      }
      if (track is PropertyTrack) {
        if (track.component.isEmpty || track.field.isEmpty) {
          problems.add('A property track does not say what it animates.');
        } else if (!seen.add('${track.binding.label}/${track.path}')) {
          problems.add(
            '${track.binding.label} has two tracks for ${track.path}.',
          );
        }
      }
      if (!track.binding.isSelf && track.binding.value.trim().isEmpty) {
        problems.add('The track "${track.summary}" is bound to nobody.');
      }
      if (track.end > duration + 1e-6) {
        problems.add(
          'The track "${track.name.isEmpty ? track.summary : track.name}" '
          'runs past the end.',
        );
      }
    }
    return problems;
  }

  /// The `.timeline.json` form: `formatVersion`, `name` when set,
  /// `duration`, `fps`, `wrap` (by name), `tracks`, and `markers` when
  /// there are any.
  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    if (name.isNotEmpty) 'name': name,
    'duration': duration,
    'fps': fps,
    'wrap': wrap.name,
    'tracks': [for (final t in tracks) t.toJson()],
    if (markers.isNotEmpty) 'markers': [for (final m in markers) m.toJson()],
  };

  /// [toJson] as text indented by two spaces: what a `.timeline.json` file
  /// holds.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Reads a timeline saved by this engine or an older one.
  ///
  /// Throws a [FormatException] for a file written by a newer engine
  /// ([TimelineFormat.versionOf] above [TimelineFormat.current]): reading
  /// it anyway would lose whatever the newer format added the next time it
  /// is saved.
  ///
  /// Tracks are read with [kinds] — the engine's own
  /// ([TimelineTrackKinds.builtIn]) when null. A track of a kind it does not
  /// know is kept as an [UnknownTrack] and saved back as it was. An older
  /// file is migrated with the packages' rules in [migrations] (none when
  /// null).
  factory TimelineAsset.fromJson(
    Map<String, dynamic> source, {
    TimelineTrackKinds? kinds,
    MigrationHooks? migrations,
  }) {
    final readers = kinds ?? TimelineTrackKinds.builtIn;
    final json = TimelineFormat.migrate(source, hooks: migrations);
    return TimelineAsset(
      name: json['name'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 1.0,
      fps: (json['fps'] as num?)?.toInt() ?? 30,
      wrap: TimelineWrap.values.asNameMap()[json['wrap']] ?? TimelineWrap.once,
      tracks: [
        for (final t in json['tracks'] as List? ?? const [])
          if (t is Map) readers.read(t.cast<String, dynamic>()),
      ],
      markers: [
        for (final m in json['markers'] as List? ?? const [])
          if (m is Map) TimelineMarker.fromJson(m.cast<String, dynamic>()),
      ],
    );
  }

  /// Parses and reads [source]; see [TimelineAsset.fromJson].
  static TimelineAsset parse(
    String source, {
    TimelineTrackKinds? kinds,
    MigrationHooks? migrations,
  }) => TimelineAsset.fromJson(
    (jsonDecode(source) as Map).cast(),
    kinds: kinds,
    migrations: migrations,
  );
}
