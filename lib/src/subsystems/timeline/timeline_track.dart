/// What a timeline is made of: tracks, who they are bound to, and the
/// registry a package adds its own kinds of track to.
library;

import '../../ecs/ecs.dart';
import '../../ecs/components/components.dart' show TagComponent;
import '../../ecs/serialization/component_definition.dart' show SchemaField;
import 'timeline_asset.dart';
import 'timeline_player.dart';

/// Who a track acts on.
enum TrackBindingKind {
  /// The entity holding the player — what makes a timeline reusable.
  self,

  /// The active entity with this name.
  name,

  /// The first active entity with this tag.
  tag,
}

/// Who a track acts on, looked up when the timeline plays — never an id, so
/// a timeline asset fits any scene that has the names it asks for.
class TrackBinding {
  const TrackBinding.self() : kind = TrackBindingKind.self, value = '';
  const TrackBinding.name(this.value) : kind = TrackBindingKind.name;
  const TrackBinding.tag(this.value) : kind = TrackBindingKind.tag;

  static const TrackBinding owner = TrackBinding.self();

  final TrackBindingKind kind;
  final String value;

  bool get isSelf => kind == TrackBindingKind.self;

  /// The entity this means for a timeline played by [owner], or null.
  /// Entities switched off are passed over unless [includeInactive].
  Entity? resolve(World world, Entity? owner, {bool includeInactive = false}) {
    switch (kind) {
      case TrackBindingKind.self:
        return owner;
      case TrackBindingKind.name:
        final found = world.findEntityByName(value);
        return found != null && (includeInactive || found.isActive)
            ? found
            : null;
      case TrackBindingKind.tag:
        for (final entity in world.query([TagComponent])) {
          if ((includeInactive || entity.isActive) &&
              entity.getComponent<TagComponent>()!.tag == value) {
            return entity;
          }
        }
        return null;
    }
  }

  /// What a person reads: `Self`, `Door`, `#enemy`.
  String get label => switch (kind) {
    TrackBindingKind.self => 'Self',
    TrackBindingKind.name => value,
    TrackBindingKind.tag => '#$value',
  };

  Object toJson() => switch (kind) {
    TrackBindingKind.self => 'self',
    TrackBindingKind.name => {'name': value},
    TrackBindingKind.tag => {'tag': value},
  };

  static TrackBinding fromJson(Object? json) {
    if (json is Map) {
      if (json['name'] is String) return TrackBinding.name(json['name']);
      if (json['tag'] is String) return TrackBinding.tag(json['tag']);
    }
    return owner;
  }

  @override
  bool operator ==(Object other) =>
      other is TrackBinding && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// What a running track can reach: the world, who is playing the timeline,
/// the entities bindings mean, and a way to say an event happened.
abstract class TimelineContext {
  World get world;

  /// The entity whose player is playing this timeline.
  Entity get owner;

  /// The entity [binding] means right now, or null. Looked up once and kept
  /// until that entity goes away. An entity that is switched off counts
  /// only with [includeInactive].
  Entity? resolve(TrackBinding binding, {bool includeInactive = false});

  /// How many timelines deep this one is nested; 0 for one a player plays.
  int get depth;

  /// Reads another timeline, the way this one was read.
  Future<TimelineAsset> loadTimeline(String path);

  /// A playback of [asset] inside this one, with [owner] as its "self".
  /// Its events come out of this timeline; its clock is the caller's to
  /// drive.
  TimelinePlayback child(TimelineAsset asset, Entity owner);

  /// Tells listeners [name] happened on the timeline.
  void emit(String name, [String payload = '']);

  /// A track is about to write [field] of [component] for the first time
  /// this play. An editor previewing a timeline notes the value here, to put
  /// it back afterwards.
  void willWrite(Component component, SchemaField field);

  /// Whether the timeline is only being looked at (an editor scrubbing),
  /// so a track must not do what cannot be undone — play a sound, fire a
  /// signal.
  bool get isPreview;
}

/// One row of a timeline. Immutable: an editor replaces a track to change
/// it, which is what makes undo a list of assets.
abstract class TimelineTrack {
  const TimelineTrack({
    this.name = '',
    this.binding = TrackBinding.owner,
    this.muted = false,
    this.locked = false,
  });

  /// The id this kind is registered under in [TimelineTrackKinds].
  String get kind;

  /// A label; empty shows what the track says about itself.
  final String name;
  final TrackBinding binding;

  /// A muted track is kept but not played.
  final bool muted;

  /// Editor only: a locked track cannot be edited.
  final bool locked;

  /// When the last thing on this track is; the timeline's content ends at
  /// the latest of these.
  double get end;

  /// What the track calls itself when [name] is empty.
  String get summary;

  /// The part of this track that runs: it holds whatever a play needs to
  /// remember, so the track itself can stay immutable and shared.
  TrackRunner createRunner();

  /// This track with the base properties changed.
  TimelineTrack withBase({
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  });

  /// The kind's own fields; [toJson] adds the shared ones.
  Map<String, dynamic> bodyToJson();

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (name.isNotEmpty) 'name': name,
    if (!binding.isSelf) 'binding': binding.toJson(),
    if (muted) 'muted': true,
    if (locked) 'locked': true,
    ...bodyToJson(),
  };
}

/// The running half of a track, made fresh for every playback.
abstract class TrackRunner {
  /// A play is starting (or starting over): forget what the last one kept.
  void begin(TimelineContext context) {}

  /// Time moved from [from] to [to] without a jump — backwards when
  /// `to < from`. For what happens *at* a time (an event, a sound's start)
  /// rather than *over* it. A seek does not call this.
  void advance(TimelineContext context, double from, double to) {}

  /// Make the world look as it should at [time].
  void apply(TimelineContext context, double time) {}

  /// The playback is over or thrown away: undo what only lasts while the
  /// timeline runs (a raised camera priority), never what it animated.
  void end(TimelineContext context) {}
}

/// A track of a kind nobody registered — a package that is not installed.
/// Kept as it was read so saving the timeline does not lose it.
class UnknownTrack extends TimelineTrack {
  UnknownTrack(this.raw)
    : super(
        name: raw['name'] as String? ?? '',
        binding: TrackBinding.fromJson(raw['binding']),
        muted: raw['muted'] == true,
        locked: raw['locked'] == true,
      );

  final Map<String, dynamic> raw;

  @override
  String get kind => raw['kind'] as String? ?? 'unknown';

  @override
  double get end => 0;

  @override
  String get summary => 'Unknown track ($kind)';

  @override
  TrackRunner createRunner() => _NoRunner();

  @override
  TimelineTrack withBase({
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => UnknownTrack({
    ...raw,
    if (name != null) 'name': name,
    if (binding != null) 'binding': binding.toJson(),
    if (muted != null) 'muted': muted,
    if (locked != null) 'locked': locked,
  });

  @override
  Map<String, dynamic> bodyToJson() => const {};

  @override
  Map<String, dynamic> toJson() => raw;
}

class _NoRunner extends TrackRunner {}

/// The kinds of track a timeline can hold. The engine registers its own;
/// a package registers more, and a timeline asset that uses them loads,
/// plays and saves like any other:
///
/// ```dart
/// TimelineTrackKinds.register('weather', WeatherTrack.fromJson);
/// ```
abstract final class TimelineTrackKinds {
  static final Map<String, TimelineTrack Function(Map<String, dynamic> json)>
  _kinds = {};

  static void register(
    String kind,
    TimelineTrack Function(Map<String, dynamic> json) fromJson,
  ) => _kinds[kind] = fromJson;

  static void unregister(String kind) => _kinds.remove(kind);

  static bool has(String kind) => _kinds.containsKey(kind);

  static List<String> get kinds => _kinds.keys.toList();

  /// The track [json] describes; an [UnknownTrack] for a kind not
  /// registered, or one whose reader throws.
  static TimelineTrack read(Map<String, dynamic> json) {
    final reader = _kinds[json['kind']];
    if (reader == null) return UnknownTrack(json);
    try {
      return reader(json);
    } catch (_) {
      return UnknownTrack(json);
    }
  }
}
