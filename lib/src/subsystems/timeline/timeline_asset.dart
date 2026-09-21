/// A timeline: tracks on one clock. Saved as `.timeline.json`, or inline in
/// the component that plays it.
library;

import 'dart:convert';

import 'timeline_track.dart';
import 'tracks/block_tracks.dart';
import 'tracks/event_track.dart';
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
  const TimelineMarker({required this.time, required this.name});

  final double time;
  final String name;

  Map<String, dynamic> toJson() => {'time': time, 'name': name};

  factory TimelineMarker.fromJson(Map<String, dynamic> json) => TimelineMarker(
    time: (json['time'] as num?)?.toDouble() ?? 0,
    name: json['name'] as String? ?? '',
  );
}

class TimelineAsset {
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
       ) {
    ensureBuiltInTracks();
  }

  /// The version of the file format this engine writes.
  static const int formatVersion = 1;

  /// What a timeline file's name ends with.
  static const String fileExtension = 'timeline.json';

  final String name;

  /// Seconds.
  final double duration;

  /// Frames per second — how an editor divides and snaps time. Playback is
  /// continuous and does not care.
  final int fps;
  final TimelineWrap wrap;
  final List<TimelineTrack> tracks;
  final List<TimelineMarker> markers;

  /// When the last key, event or block on any track is.
  double get contentEnd =>
      tracks.fold(0.0, (end, t) => t.end > end ? t.end : end);

  TimelineMarker? markerNamed(String name) {
    for (final m in markers) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// The property tracks, which is what most callers want to walk.
  Iterable<PropertyTrack> get propertyTracks =>
      tracks.whereType<PropertyTrack>();

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
        problems.add('A track is of the unknown kind "${track.kind}".');
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

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    if (name.isNotEmpty) 'name': name,
    'duration': duration,
    'fps': fps,
    'wrap': wrap.name,
    'tracks': [for (final t in tracks) t.toJson()],
    if (markers.isNotEmpty) 'markers': [for (final m in markers) m.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory TimelineAsset.fromJson(Map<String, dynamic> json) {
    ensureBuiltInTracks();
    return TimelineAsset(
      name: json['name'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 1.0,
      fps: (json['fps'] as num?)?.toInt() ?? 30,
      wrap: TimelineWrap.values.asNameMap()[json['wrap']] ?? TimelineWrap.once,
      tracks: [
        for (final t in json['tracks'] as List? ?? const [])
          if (t is Map) TimelineTrackKinds.read(t.cast<String, dynamic>()),
      ],
      markers: [
        for (final m in json['markers'] as List? ?? const [])
          if (m is Map) TimelineMarker.fromJson(m.cast<String, dynamic>()),
      ],
    );
  }

  static TimelineAsset parse(String source) =>
      TimelineAsset.fromJson((jsonDecode(source) as Map).cast());

  static bool _builtInsRegistered = false;

  /// Registers the engine's own track kinds; harmless to call again. A
  /// package's registration of the same id beforehand is left alone.
  static void ensureBuiltInTracks() {
    if (_builtInsRegistered) return;
    _builtInsRegistered = true;
    void add(String kind, TimelineTrack Function(Map<String, dynamic>) read) {
      if (!TimelineTrackKinds.has(kind))
        TimelineTrackKinds.register(kind, read);
    }

    add(PropertyTrack.kindId, PropertyTrack.fromJson);
    add(EventTrack.kindId, EventTrack.fromJson);
    add(SpriteClipTrack.kindId, SpriteClipTrack.fromJson);
    add(CameraShotTrack.kindId, CameraShotTrack.fromJson);
    add(AudioTrack.kindId, AudioTrack.fromJson);
    add(ActivationTrack.kindId, ActivationTrack.fromJson);
    add(NestedTimelineTrack.kindId, NestedTimelineTrack.fromJson);
  }
}
