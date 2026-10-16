/// What a timeline is made of: tracks, who they are bound to, and the
/// registry a package adds its own kinds of track to.
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../ecs/ecs.dart';
import '../../ecs/serialization/component_definition.dart' show SchemaField;
import 'timeline_asset.dart';
import 'timeline_player.dart';
import 'tracks/block_tracks.dart';
import 'tracks/event_track.dart';
import 'tracks/property_track.dart';

/// Who a track acts on: [EntityTargetKind], by its timeline name.
typedef TrackBindingKind = EntityTargetKind;

/// Who a track acts on, looked up when the timeline plays — never an id, so
/// a timeline asset fits any scene that has the names it asks for.
///
/// An [EntityTarget] whose default is the timeline's own entity rather than
/// nobody: a track with no binding animates whoever plays it.
class TrackBinding extends EntityTarget {
  /// The entity playing the timeline.
  const TrackBinding.self() : super.self();

  /// The first (oldest) entity named [value].
  const TrackBinding.name(super.value) : super.name();

  /// The first (oldest) entity tagged [value] (without the `#`).
  const TrackBinding.tag(super.value) : super.tag();

  /// The binding a track has by default: the entity playing the timeline.
  static const TrackBinding owner = TrackBinding.self();

  /// [target] as a binding; nobody becomes the timeline's own entity.
  static TrackBinding of(EntityTarget target) => switch (target.kind) {
    _ when target.isNone => owner,
    EntityTargetKind.self => owner,
    EntityTargetKind.name => TrackBinding.name(target.value),
    EntityTargetKind.tag => TrackBinding.tag(target.value),
  };

  @override
  Object toJson() => switch (kind) {
    TrackBindingKind.self => 'self',
    TrackBindingKind.name => {'name': value},
    TrackBindingKind.tag => {'tag': value},
  };

  /// Reads [toJson]'s `'self'`, `{'name': ...}` or `{'tag': ...}`. A bare
  /// string reads as [EntityTarget.parse] reads one — `'#door'` a tag,
  /// `'Door'` a name — so a hand-written file means what it says; a blank
  /// one, `'self'`, null, or any other map or value is [owner].
  static TrackBinding fromJson(Object? json) {
    if (json is Map) {
      if (json['name'] is String) return TrackBinding.name(json['name']);
      if (json['tag'] is String) return TrackBinding.tag(json['tag']);
      return owner;
    }
    if (json is String) return of(EntityTarget.parse(json));
    return owner;
  }
}

/// What a running track can reach: the world, who is playing the timeline,
/// the entities bindings mean, and a way to say an event happened.
abstract class TimelineContext {
  /// The world the timeline plays in, where its bindings are looked up.
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

  /// Whether something an event set off — a handler that stopped, sought
  /// or restarted the playback, or the one it is nested in — has changed
  /// what is playing since this step began. A track that fires several
  /// things in one step stops at the first that finds it true: what comes
  /// after them is no longer happening.
  bool get isInterrupted => false;

  /// Whether the timeline comes to rest at [time] — the end of what it
  /// plays, where it stops or turns round rather than going on to its
  /// start. A block ending exactly at [time] still holds there (see
  /// [BlockTrack.blockAt]), so what it does lasts once the timeline has
  /// finished. False by default.
  bool endsAt(double time) => false;
}

/// One row of a timeline. Immutable: an editor replaces a track to change
/// it, which is what makes undo a list of assets.
abstract class TimelineTrack {
  /// The shared part of every track: unnamed, bound to the entity playing
  /// the timeline, neither muted nor locked unless said.
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

  /// Who the track acts on, looked up by the playback as it plays.
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

  /// The saved form in a `.timeline.json`'s `tracks`: `kind`; `name`,
  /// `binding`, `muted` and `locked` only when not the default; then the
  /// kind's own [bodyToJson] keys.
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

/// A track of a kind nobody registered — a package that is not installed —
/// or of a known kind whose reader could not read it ([error] says why).
/// Kept as it was read so saving the timeline does not lose it.
class UnknownTrack extends TimelineTrack {
  /// A track kept as [raw], its saved map; the name, binding, muted and
  /// locked flags are read from it so an editor can still show them.
  UnknownTrack(this.raw, {this.error})
    : super(
        name: raw['name'] as String? ?? '',
        binding: TrackBinding.fromJson(raw['binding']),
        muted: raw['muted'] == true,
        locked: raw['locked'] == true,
      );

  /// The track's saved map, as read; [toJson] returns it unchanged. It is
  /// not copied: a change to the map changes what is saved.
  final Map<String, dynamic> raw;

  /// Why a registered kind's reader could not read [raw]; null when the
  /// kind is simply not registered.
  final Object? error;

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
    'name': ?name,
    if (binding != null) 'binding': binding.toJson(),
    'muted': ?muted,
    'locked': ?locked,
  }, error: error);

  @override
  Map<String, dynamic> bodyToJson() => const {};

  @override
  Map<String, dynamic> toJson() => raw;
}

class _NoRunner extends TrackRunner {}

/// Reads a track of one kind from its saved form.
typedef TimelineTrackReader = TimelineTrack Function(Map<String, dynamic> json);

/// How an editor offers a kind of track for adding: what it is called, and
/// an empty one of it.
final class TimelineTrackOffer {
  /// An offer called [label] that adds what [create] makes.
  const TimelineTrackOffer(this.label, this.create);

  /// What the add menu calls it: `Events`, `Skeletal clips`.
  final String label;

  /// An empty track of the kind.
  final TimelineTrack Function() create;
}

/// The kinds of track a timeline can hold. The engine's own are always
/// there; a package registers more into an engine's
/// (`engine.context.trackKinds`), and a timeline asset that uses them loads,
/// plays and saves like any other:
///
/// ```dart
/// engine.context.trackKinds.register('weather', WeatherTrack.fromJson);
/// ```
///
/// A timeline read without a package's kinds keeps their tracks as
/// [UnknownTrack]s, which save back unchanged; [resolve] reads them again
/// once the kinds are known — a player does so with its world's.
/// [builtIn] holds only the engine's kinds and cannot be changed.
final class TimelineTrackKinds {
  /// The engine's kinds (unless [withBuiltIns] is false), to add to.
  TimelineTrackKinds({bool withBuiltIns = true}) : _frozen = false {
    if (withBuiltIns) {
      _kinds.addAll(_engine);
      _offers.addAll(_engineOffers);
    }
  }

  TimelineTrackKinds._frozen() : _frozen = true {
    _kinds.addAll(_engine);
    _offers.addAll(_engineOffers);
  }

  /// The engine's kinds and nothing else — what a timeline is read with when
  /// given none. Read-only: [register] throws.
  static final TimelineTrackKinds builtIn = TimelineTrackKinds._frozen();

  static final Map<String, TimelineTrackReader> _engine = {
    PropertyTrack.kindId: PropertyTrack.fromJson,
    EventTrack.kindId: EventTrack.fromJson,
    SpriteClipTrack.kindId: SpriteClipTrack.fromJson,
    CameraShotTrack.kindId: CameraShotTrack.fromJson,
    AudioTrack.kindId: AudioTrack.fromJson,
    ActivationTrack.kindId: ActivationTrack.fromJson,
    NestedTimelineTrack.kindId: NestedTimelineTrack.fromJson,
  };

  // A property track is added by choosing a field, so it is not offered.
  static const Map<String, TimelineTrackOffer> _engineOffers = {
    EventTrack.kindId: TimelineTrackOffer('Events', EventTrack.new),
    SpriteClipTrack.kindId: TimelineTrackOffer(
      'Sprite clips',
      SpriteClipTrack.new,
    ),
    CameraShotTrack.kindId: TimelineTrackOffer(
      'Camera shots',
      CameraShotTrack.new,
    ),
    AudioTrack.kindId: TimelineTrackOffer('Audio', AudioTrack.new),
    ActivationTrack.kindId: TimelineTrackOffer(
      'Activation',
      ActivationTrack.new,
    ),
    NestedTimelineTrack.kindId: TimelineTrackOffer(
      'Nested timelines',
      NestedTimelineTrack.new,
    ),
  };

  final bool _frozen;
  final Map<String, TimelineTrackReader> _kinds = {};
  final Map<String, TimelineTrackOffer> _offers = {};

  void _check() {
    if (_frozen) {
      throw UnsupportedError(
        "TimelineTrackKinds.builtIn cannot be changed: register into an "
        "engine's (engine.context.trackKinds).",
      );
    }
  }

  /// Reads tracks of [kind] with [fromJson], replacing any reader for it.
  /// With [offer], an editor's add menu offers the kind too.
  void register(
    String kind,
    TimelineTrackReader fromJson, {
    TimelineTrackOffer? offer,
  }) {
    _check();
    _kinds[kind] = fromJson;
    if (offer != null) {
      _offers[kind] = offer;
    } else {
      _offers.remove(kind);
    }
  }

  /// How an editor offers [kind] for adding, or null when it does not.
  TimelineTrackOffer? offerFor(String kind) => _offers[kind];

  /// The kinds an editor offers for adding, in registration order.
  List<String> get offered => [
    for (final kind in _kinds.keys)
      if (_offers.containsKey(kind)) kind,
  ];

  /// Forgets the reader for [kind], built-in or not; tracks of it are read
  /// as [UnknownTrack]s from then on. Throws [UnsupportedError] on
  /// [builtIn].
  void unregister(String kind) {
    _check();
    _kinds.remove(kind);
    _offers.remove(kind);
  }

  /// Whether a reader is registered for [kind].
  bool has(String kind) => _kinds.containsKey(kind);

  /// Every registered kind id, the engine's first — a new list each call.
  List<String> get kinds => _kinds.keys.toList();

  /// [asset] with every [UnknownTrack] whose kind is registered here read
  /// again — the same instance when there is none.
  TimelineAsset resolve(TimelineAsset asset) {
    List<TimelineTrack>? tracks;
    for (var i = 0; i < asset.tracks.length; i++) {
      final track = asset.tracks[i];
      if (track is! UnknownTrack || track.error != null) continue;
      if (!_kinds.containsKey(track.kind)) continue;
      (tracks ??= List.of(asset.tracks))[i] = read(track.raw);
    }
    return tracks == null ? asset : asset.copyWith(tracks: tracks);
  }

  /// The track [json] describes; an [UnknownTrack] for a kind not
  /// registered, or one whose reader throws — that one carries the error,
  /// which is also printed in debug builds.
  TimelineTrack read(Map<String, dynamic> json) {
    final reader = _kinds[json['kind']];
    if (reader == null) return UnknownTrack(json);
    try {
      return reader(json);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Timeline: a "${json['kind']}" track could not be read and is '
          'kept as it was: $error',
        );
      }
      return UnknownTrack(json, error: error);
    }
  }
}
