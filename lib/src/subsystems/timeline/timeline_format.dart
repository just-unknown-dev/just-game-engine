/// Versions of the timeline file format, and the steps between them.
library;

/// One step of the timeline-format migration chain: from version [from] to
/// [from] + 1.
abstract class TimelineMigration {
  const TimelineMigration();

  int get from;

  /// Rewrites [json] (a private copy) in place and returns it.
  Map<String, dynamic> apply(Map<String, dynamic> json);
}

/// Rewrites one track of a version-1 timeline for version 2. Returns the
/// track, changed or not, or null to drop it.
typedef TrackMigration =
    Map<String, dynamic>? Function(Map<String, dynamic> track);

/// The timeline file format: its current version, and bringing an older
/// file up to it.
///
/// Used for timeline files (`.timeline.json`) and for the inline timelines
/// a `TimelinePlayerComponent` keeps inside a scene.
abstract final class TimelineFormat {
  /// The version this engine writes.
  static const int current = 2;

  /// Every step, in order.
  static const List<TimelineMigration> chain = [TimelineV1ToV2()];

  /// The version [json] says it is — 1 when it says nothing, as the first
  /// files did not.
  static int versionOf(Map<String, dynamic> json) =>
      (json['formatVersion'] as num?)?.toInt() ?? 1;

  /// [json] brought up to [current] — a new map; [json] is never changed.
  /// A file newer than this engine is returned as it is.
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    final version = versionOf(json);
    if (version >= current) return json;
    var out = _deepCopy(json);
    for (final step in chain) {
      if (step.from < version) continue;
      out = step.apply(out);
      out['formatVersion'] = step.from + 1;
    }
    return out;
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> json) =>
      _copy(json) as Map<String, dynamic>;

  static Object? _copy(Object? value) => switch (value) {
    Map() => <String, dynamic>{
      for (final e in value.entries) '${e.key}': _copy(e.value),
    },
    List() => [for (final v in value) _copy(v)],
    _ => value,
  };
}

/// v1 → v2: rotation became three angles.
///
/// A transform's rotation used to be one angle (`rotation`, about Z) plus
/// two hidden tilts (`rotationX`, `rotationY`); it is now one field,
/// `rotation: {x, y, z}`. So a track keying `rotation` keys its `z`
/// channel, and the tilts' tracks key `x` and `y`. Values were radians and
/// still are; nothing else about a track changes.
///
/// A parent link's offset is no longer saved — it follows from where
/// things are — so a track keying `ParentComponent.localOffset` or
/// `.localRotation` has nothing to key and is dropped.
///
/// A package with its own renamed fields adds rules to [perTrack].
class TimelineV1ToV2 extends TimelineMigration {
  const TimelineV1ToV2();

  @override
  int get from => 1;

  /// Track-level rules a package adds, run after the built-in ones.
  static final List<TrackMigration> perTrack = [];

  @override
  Map<String, dynamic> apply(Map<String, dynamic> json) {
    final tracks = json['tracks'];
    if (tracks is! List) return json;
    final out = <Object?>[];
    for (final t in tracks) {
      if (t is! Map<String, dynamic>) {
        out.add(t);
        continue;
      }
      Map<String, dynamic>? track = _builtIn(t);
      for (final rule in perTrack) {
        if (track == null) break;
        track = rule(track);
      }
      if (track != null) out.add(track);
    }
    json['tracks'] = out;
    return json;
  }

  static Map<String, dynamic>? _builtIn(Map<String, dynamic> track) {
    if (track['kind'] != 'property') return track;
    final component = track['component'];
    final field = track['field'];
    final channel = (track['channel'] as String?) ?? '';
    if (component == 'TransformComponent') {
      switch (field) {
        case 'rotation' when channel.isEmpty:
          track['channel'] = 'z';
        case 'rotationX':
          track['field'] = 'rotation';
          track['channel'] = 'x';
        case 'rotationY':
          track['field'] = 'rotation';
          track['channel'] = 'y';
      }
    }
    if (component == 'ParentComponent' &&
        (field == 'localOffset' || field == 'localRotation')) {
      return null;
    }
    return track;
  }
}
