/// Tracks made of blocks — a stretch of time during which something holds:
/// a sprite clip plays, a camera has the shot, an entity is active, another
/// timeline runs. And sounds, which start at a time.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../ecs/components/components.dart';
import '../../../ecs/ecs.dart';
import '../timeline_asset.dart';
import '../timeline_player.dart';
import '../timeline_track.dart';

/// A stretch of a block track. Every kind reads the same few fields its own
/// way, which is what lets one editor draw, move and trim them all.
class TimelineBlock {
  /// A block from [start] lasting [length] seconds — one by default — with
  /// an empty [value], a [speed] and [amount] of 1, not looping.
  const TimelineBlock({
    required this.start,
    this.length = 1.0,
    this.value = '',
    this.speed = 1.0,
    this.amount = 1.0,
    this.loop = false,
  });

  /// When the block begins, in seconds from the timeline's start.
  final double start;

  /// How long it lasts, in seconds. On an instant track (see
  /// [BlockTrack.isInstant]) only how wide an editor draws it.
  final double length;

  /// What the block is of: a clip's name, a camera entity's name, a sound's
  /// or a timeline's path. See [BlockTrack.valueLabel].
  final String value;

  /// How fast the clip or the nested timeline runs.
  final double speed;

  /// How much: a sound's volume, a camera shot's priority boost. See
  /// [BlockTrack.amountLabel].
  final double amount;

  /// Whether the clip or the nested timeline starts over within the block.
  final bool loop;

  /// When the block ends, in seconds: [start] + [length].
  double get end => start + length;

  /// Whether [time] falls in the block: at its start or after, and before
  /// its end.
  bool contains(double time) => time >= start && time < end;

  /// A copy with the given fields replaced.
  TimelineBlock copyWith({
    double? start,
    double? length,
    String? value,
    double? speed,
    double? amount,
    bool? loop,
  }) => TimelineBlock(
    start: start ?? this.start,
    length: length ?? this.length,
    value: value ?? this.value,
    speed: speed ?? this.speed,
    amount: amount ?? this.amount,
    loop: loop ?? this.loop,
  );

  /// This block as a JSON map: `start` and `length` always; `value`,
  /// `speed`, `amount` and `loop` only when not the default.
  Map<String, dynamic> toJson() => {
    'start': start,
    'length': length,
    if (value.isNotEmpty) 'value': value,
    if (speed != 1.0) 'speed': speed,
    if (amount != 1.0) 'amount': amount,
    if (loop) 'loop': true,
  };

  /// Reads [toJson]'s shape; a missing key takes the constructor's default
  /// (a missing `start` is 0).
  factory TimelineBlock.fromJson(Map<String, dynamic> json) => TimelineBlock(
    start: (json['start'] as num?)?.toDouble() ?? 0,
    length: (json['length'] as num?)?.toDouble() ?? 1,
    value: json['value'] as String? ?? '',
    speed: (json['speed'] as num?)?.toDouble() ?? 1,
    amount: (json['amount'] as num?)?.toDouble() ?? 1,
    loop: json['loop'] == true,
  );
}

/// A track of [TimelineBlock]s.
abstract class BlockTrack extends TimelineTrack {
  /// A track of [blocks], copied, sorted by start and made unmodifiable.
  BlockTrack({
    List<TimelineBlock> blocks = const [],
    super.name,
    super.binding,
    super.muted,
    super.locked,
  }) : blocks = List.unmodifiable(
         List.of(blocks)..sort((a, b) => a.start.compareTo(b.start)),
       );

  /// The blocks, by start time. Unmodifiable. They may overlap; see
  /// [blockAt].
  final List<TimelineBlock> blocks;

  /// What [TimelineBlock.value] is here, for an editor's field; null when
  /// this kind has no use for it.
  String? get valueLabel;

  /// What [TimelineBlock.amount] is here; null when unused.
  String? get amountLabel => null;

  /// The file extensions [TimelineBlock.value] picks from, when it is a path.
  List<String> get valueExtensions => const [];

  /// Whether [TimelineBlock.speed] and [TimelineBlock.loop] mean anything.
  bool get hasSpeed => false;

  /// What happens at the block's start is all there is: its length is only
  /// how wide an editor draws it.
  bool get isInstant => false;

  /// What a new block of this kind starts as.
  TimelineBlock get defaultBlock => const TimelineBlock(start: 0);

  /// This track with other [blocks], or other base properties.
  BlockTrack rebuild({
    List<TimelineBlock>? blocks,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  });

  @override
  double get end => blocks.fold(0.0, (e, b) => b.end > e ? b.end : e);

  /// The block [time] falls in — the later one where two overlap.
  TimelineBlock? blockAt(double time) {
    for (final b in blocks.reversed) {
      if (b.contains(time)) return b;
    }
    return null;
  }

  @override
  TimelineTrack withBase({
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => rebuild(name: name, binding: binding, muted: muted, locked: locked);

  @override
  Map<String, dynamic> bodyToJson() => {
    'blocks': [for (final b in blocks) b.toJson()],
  };

  /// The blocks in a saved track's `blocks` list, for a kind's `fromJson`.
  /// No list is no blocks; entries that are not maps are skipped.
  static List<TimelineBlock> blocksFrom(Map<String, dynamic> json) => [
    for (final b in json['blocks'] as List? ?? const [])
      if (b is Map) TimelineBlock.fromJson(b.cast<String, dynamic>()),
  ];
}

// ── Sprite clips ────────────────────────────────────────────────────────────

/// Plays clips on the bound entity's [SpriteAnimationComponent]. Between
/// blocks the sprite goes back to the clip it was playing before.
class SpriteClipTrack extends BlockTrack {
  /// A track of clip [blocks]: each block's value names the clip, its speed
  /// and loop are the sprite's while it lasts.
  SpriteClipTrack({
    super.blocks,
    super.name,
    super.binding,
    super.muted,
    super.locked,
  });

  /// `spriteClip`: the `kind` this track is saved as in a `.timeline.json`,
  /// and the id [TimelineTrackKinds] reads it by.
  static const String kindId = 'spriteClip';

  @override
  String get kind => kindId;

  @override
  String get summary => 'Sprite clips';

  @override
  String? get valueLabel => 'Clip';

  @override
  bool get hasSpeed => true;

  @override
  TrackRunner createRunner() => _SpriteClipRunner(this);

  @override
  SpriteClipTrack rebuild({
    List<TimelineBlock>? blocks,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => SpriteClipTrack(
    blocks: blocks ?? this.blocks,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  /// Reads a saved track of this kind ([toJson]'s shape); a missing key
  /// takes its default. Throws on a mistyped one, which
  /// [TimelineTrackKinds.read] keeps as an [UnknownTrack].
  factory SpriteClipTrack.fromJson(Map<String, dynamic> json) =>
      SpriteClipTrack(
        blocks: BlockTrack.blocksFrom(json),
        name: json['name'] as String? ?? '',
        binding: TrackBinding.fromJson(json['binding']),
        muted: json['muted'] == true,
        locked: json['locked'] == true,
      );
}

class _SpriteClipRunner extends TrackRunner {
  _SpriteClipRunner(this.track);

  final SpriteClipTrack track;
  TimelineBlock? _current;
  SpriteAnimationComponent? _sprite;

  // What the sprite was doing before the first block took it over.
  String? _clipBefore;
  double _speedBefore = 1;
  bool? _loopBefore;

  @override
  void begin(TimelineContext context) {
    _current = null;
    _sprite = null;
    _clipBefore = null;
  }

  @override
  void apply(TimelineContext context, double time) {
    final block = track.blockAt(time);
    if (identical(block, _current)) return;
    final sprite = context
        .resolve(track.binding)
        ?.getComponent<SpriteAnimationComponent>();
    if (sprite == null) return;
    _current = block;
    if (block == null) {
      _restore();
      return;
    }
    if (_clipBefore == null) {
      _sprite = sprite;
      _clipBefore = sprite.clip;
      _speedBefore = sprite.speed;
      _loopBefore = sprite.loopOverride;
    }
    sprite
      ..speed = block.speed
      ..switchClip(block.value, restartIfSame: true, loop: block.loop);
  }

  void _restore() {
    final sprite = _sprite, clip = _clipBefore;
    if (sprite == null || clip == null) return;
    sprite
      ..speed = _speedBefore
      ..switchClip(clip, loop: _loopBefore);
    _clipBefore = null;
  }

  @override
  void end(TimelineContext context) {
    if (_current != null) _restore();
    _current = null;
  }
}

// ── Camera shots ────────────────────────────────────────────────────────────

/// Gives the shot to a virtual camera for a while: [TimelineBlock.value] is
/// the camera entity's name, and its priority is raised by
/// [TimelineBlock.amount] for the block's length. The camera brain blends
/// to it and back as it does for any change of priority.
class CameraShotTrack extends BlockTrack {
  /// A track of shot [blocks]. Each block names its own camera, so the
  /// track's binding is not used; a block's amount is rounded to a whole
  /// priority.
  CameraShotTrack({
    super.blocks,
    super.name,
    super.binding,
    super.muted,
    super.locked,
  });

  /// `cameraShot`: the `kind` this track is saved as in a `.timeline.json`,
  /// and the id [TimelineTrackKinds] reads it by.
  static const String kindId = 'cameraShot';

  /// What a new shot raises its camera's priority by.
  static const double defaultBoost = 100;

  @override
  String get kind => kindId;

  @override
  String get summary => 'Camera shots';

  @override
  String? get valueLabel => 'Camera';

  @override
  String? get amountLabel => 'Priority boost';

  @override
  TimelineBlock get defaultBlock =>
      const TimelineBlock(start: 0, length: 2, amount: defaultBoost);

  @override
  TrackRunner createRunner() => _CameraShotRunner(this);

  @override
  CameraShotTrack rebuild({
    List<TimelineBlock>? blocks,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => CameraShotTrack(
    blocks: blocks ?? this.blocks,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  /// Reads a saved track of this kind ([toJson]'s shape); a missing key
  /// takes its default. Throws on a mistyped one, which
  /// [TimelineTrackKinds.read] keeps as an [UnknownTrack].
  factory CameraShotTrack.fromJson(Map<String, dynamic> json) =>
      CameraShotTrack(
        blocks: BlockTrack.blocksFrom(json),
        name: json['name'] as String? ?? '',
        binding: TrackBinding.fromJson(json['binding']),
        muted: json['muted'] == true,
        locked: json['locked'] == true,
      );
}

class _CameraShotRunner extends TrackRunner {
  _CameraShotRunner(this.track);

  final CameraShotTrack track;
  TimelineBlock? _current;
  VirtualCameraComponent? _boosted;
  int _boost = 0;

  @override
  void apply(TimelineContext context, double time) {
    final block = track.blockAt(time);
    if (identical(block, _current)) return;
    _release();
    _current = block;
    if (block == null) return;
    final camera = context
        .resolve(TrackBinding.name(block.value))
        ?.getComponent<VirtualCameraComponent>();
    if (camera == null) {
      // Not there yet, perhaps: look again next frame.
      _current = null;
      return;
    }
    _boost = block.amount.round();
    camera.priority += _boost;
    _boosted = camera;
  }

  void _release() {
    _boosted?.priority -= _boost;
    _boosted = null;
  }

  @override
  void end(TimelineContext context) {
    _release();
    _current = null;
  }
}

// ── Sounds ──────────────────────────────────────────────────────────────────

/// Makes the sound an audio track's [cue] asks for, at entity [at].
typedef TimelineAudioPlayer =
    void Function(TimelineContext context, Entity at, TimelineBlock cue);

/// How an audio track makes a sound: through its world's context
/// (`context.timelineAudio`), which a game with its own audio replaces. The
/// default, [viaComponent], asks the engine's audio system through an
/// [AudioPlayComponent] on the bound entity.
abstract final class TimelineAudio {
  /// The default [TimelineAudioPlayer]: adds an [AudioPlayComponent] to
  /// [at] for the cue's file (its value), at its amount as the volume and
  /// its speed. While [at] already has one — a second sound the same frame
  /// — the cue is dropped.
  static void viaComponent(
    TimelineContext context,
    Entity at,
    TimelineBlock cue,
  ) {
    // One request at a time per entity; a second sound the same frame is
    // dropped rather than replacing the first.
    if (at.hasComponent<AudioPlayComponent>()) return;
    at.addComponent(
      AudioPlayComponent(
        clipPath: cue.value,
        volume: cue.amount,
        speed: cue.speed,
      ),
    );
  }
}

/// Starts sounds: [TimelineBlock.value] is the file, [TimelineBlock.amount]
/// the volume. A sound starts when time passes the block's start going
/// forwards; scrubbing in an editor stays quiet.
class AudioTrack extends BlockTrack {
  /// A track of sound cues. A block with no file is skipped; a sound plays
  /// at the bound entity, or the owner when the binding finds nobody.
  AudioTrack({
    super.blocks,
    super.name,
    super.binding,
    super.muted,
    super.locked,
  });

  /// `audio`: the `kind` this track is saved as in a `.timeline.json`, and
  /// the id [TimelineTrackKinds] reads it by.
  static const String kindId = 'audio';

  @override
  String get kind => kindId;

  @override
  String get summary => 'Audio';

  @override
  String? get valueLabel => 'Sound';

  @override
  String? get amountLabel => 'Volume';

  @override
  List<String> get valueExtensions => const ['wav', 'mp3', 'ogg', 'flac'];

  @override
  bool get isInstant => true;

  @override
  TrackRunner createRunner() => _AudioRunner(this);

  @override
  AudioTrack rebuild({
    List<TimelineBlock>? blocks,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => AudioTrack(
    blocks: blocks ?? this.blocks,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  /// Reads a saved track of this kind ([toJson]'s shape); a missing key
  /// takes its default. Throws on a mistyped one, which
  /// [TimelineTrackKinds.read] keeps as an [UnknownTrack].
  factory AudioTrack.fromJson(Map<String, dynamic> json) => AudioTrack(
    blocks: BlockTrack.blocksFrom(json),
    name: json['name'] as String? ?? '',
    binding: TrackBinding.fromJson(json['binding']),
    muted: json['muted'] == true,
    locked: json['locked'] == true,
  );
}

class _AudioRunner extends TrackRunner {
  _AudioRunner(this.track);

  final AudioTrack track;

  @override
  void advance(TimelineContext context, double from, double to) {
    if (context.isPreview || to < from) return;
    for (final cue in track.blocks) {
      if (cue.value.isEmpty || cue.start <= from || cue.start > to) continue;
      final at = context.resolve(track.binding) ?? context.owner;
      context.world.context.timelineAudio(context, at, cue);
    }
  }
}

// ── Activation ──────────────────────────────────────────────────────────────

/// The bound entity is active inside the blocks and inactive outside them.
class ActivationTrack extends BlockTrack {
  /// A track whose [blocks] are when the entity is on; their value, speed,
  /// amount and loop are not used. After a play the entity stays as the
  /// timeline left it; after an editor's preview it goes back to how it
  /// was.
  ActivationTrack({
    super.blocks,
    super.name,
    super.binding,
    super.muted,
    super.locked,
  });

  /// `activation`: the `kind` this track is saved as in a `.timeline.json`,
  /// and the id [TimelineTrackKinds] reads it by.
  static const String kindId = 'activation';

  @override
  String get kind => kindId;

  @override
  String get summary => 'Active';

  @override
  String? get valueLabel => null;

  @override
  TrackRunner createRunner() => _ActivationRunner(this);

  @override
  ActivationTrack rebuild({
    List<TimelineBlock>? blocks,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => ActivationTrack(
    blocks: blocks ?? this.blocks,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  /// Reads a saved track of this kind ([toJson]'s shape); a missing key
  /// takes its default. Throws on a mistyped one, which
  /// [TimelineTrackKinds.read] keeps as an [UnknownTrack].
  factory ActivationTrack.fromJson(Map<String, dynamic> json) =>
      ActivationTrack(
        blocks: BlockTrack.blocksFrom(json),
        name: json['name'] as String? ?? '',
        binding: TrackBinding.fromJson(json['binding']),
        muted: json['muted'] == true,
        locked: json['locked'] == true,
      );
}

class _ActivationRunner extends TrackRunner {
  _ActivationRunner(this.track);

  final ActivationTrack track;
  Entity? _entity;
  bool _wasActive = true;

  @override
  void begin(TimelineContext context) => _entity = null;

  @override
  void apply(TimelineContext context, double time) {
    // The entity this switches off must still be found the next frame.
    final entity = context.resolve(track.binding, includeInactive: true);
    if (entity == null) return;
    if (!identical(entity, _entity)) {
      _entity = entity;
      _wasActive = entity.isActive;
    }
    entity.isActive = track.blockAt(time) != null;
  }

  @override
  void end(TimelineContext context) {
    // A look in an editor leaves nothing behind; a play leaves the entity
    // as the timeline put it.
    if (context.isPreview) _entity?.isActive = _wasActive;
    _entity = null;
  }
}

// ── Nested timelines ────────────────────────────────────────────────────────

/// Runs other timelines inside this one: [TimelineBlock.value] is the
/// timeline's path, played for the bound entity as its "self".
class NestedTimelineTrack extends BlockTrack {
  /// A track of timeline [blocks]: inside a block its timeline runs at the
  /// block's speed from its own start, starting over when the block loops
  /// and holding its end when it does not.
  NestedTimelineTrack({
    super.blocks,
    super.name,
    super.binding,
    super.muted,
    super.locked,
  });

  /// `nested`: the `kind` this track is saved as in a `.timeline.json`, and
  /// the id [TimelineTrackKinds] reads it by.
  static const String kindId = 'nested';

  /// A timeline nested deeper than this is not run: it is nesting itself.
  static const int maxDepth = 8;

  @override
  String get kind => kindId;

  @override
  String get summary => 'Timelines';

  @override
  String? get valueLabel => 'Timeline';

  @override
  List<String> get valueExtensions => const [TimelineAsset.fileExtension];

  @override
  bool get hasSpeed => true;

  @override
  TrackRunner createRunner() => _NestedRunner(this);

  @override
  NestedTimelineTrack rebuild({
    List<TimelineBlock>? blocks,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => NestedTimelineTrack(
    blocks: blocks ?? this.blocks,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  /// Reads a saved track of this kind ([toJson]'s shape); a missing key
  /// takes its default. Throws on a mistyped one, which
  /// [TimelineTrackKinds.read] keeps as an [UnknownTrack].
  factory NestedTimelineTrack.fromJson(Map<String, dynamic> json) =>
      NestedTimelineTrack(
        blocks: BlockTrack.blocksFrom(json),
        name: json['name'] as String? ?? '',
        binding: TrackBinding.fromJson(json['binding']),
        muted: json['muted'] == true,
        locked: json['locked'] == true,
      );
}

class _NestedRunner extends TrackRunner {
  _NestedRunner(this.track);

  final NestedTimelineTrack track;
  final Map<String, TimelinePlayback?> _children = {};
  TimelineBlock? _current;
  int _generation = 0;

  // What has been read, kept from one play to the next: a restart has its
  // children at once instead of missing frames while they load again.
  final Map<String, TimelineAsset> _loaded = {};

  // What could not be read: said once, and not asked for again.
  final Set<String> _failed = {};

  // A step may cross the child's own loop this many times at most before
  // the laps in between stop firing: the same events, again and again.
  static const int _maxLaps = 2;

  @override
  void begin(TimelineContext context) {
    _drop(context);
    if (context.depth >= NestedTimelineTrack.maxDepth) return;
    final generation = ++_generation;
    for (final path in {for (final b in track.blocks) b.value}) {
      if (path.isEmpty || _failed.contains(path)) continue;
      _children[path] = null;
      if (_loaded.containsKey(path)) {
        _childFor(context, path);
        continue;
      }
      context
          .loadTimeline(path)
          .then(
            (asset) {
              _loaded[path] = asset;
              if (generation != _generation) return;
              _childFor(context, path);
            },
            onError: (Object error) {
              if (!_failed.add(path)) return;
              debugPrint(
                'Timeline: the nested timeline "$path" could not be loaded; '
                'its blocks will not play. $error',
              );
            },
          );
    }
  }

  /// The child playing [path] — made now if its timeline is loaded and the
  /// bound entity exists, which may be later than the play began.
  TimelinePlayback? _childFor(TimelineContext context, String path) {
    final existing = _children[path];
    if (existing != null) return existing;
    if (!_children.containsKey(path)) return null;
    final asset = _loaded[path];
    if (asset == null) return null;
    final owner = context.resolve(track.binding);
    if (owner == null) return null;
    return _children[path] = context.child(asset, owner);
  }

  /// Where the child's clock is when ours is at [time] inside [block].
  double _local(TimelineBlock block, TimelinePlayback child, double time) {
    final local = (time - block.start) * block.speed;
    final length = child.duration;
    if (length <= 0) return 0;
    return block.loop ? local % length : local.clamp(0.0, length);
  }

  @override
  void advance(TimelineContext context, double from, double to) {
    if (from == to) return;
    final forwards = to > from;
    // Every block the step touches, in the order time meets them — a step
    // may leave one block and enter the next, or jump a short one whole.
    final blocks = forwards ? track.blocks : track.blocks.reversed;
    for (final block in blocks) {
      final touches = forwards
          ? from < block.end && to >= block.start
          : from > block.start && to <= block.end;
      if (!touches) continue;
      final child = _childFor(context, block.value);
      if (child == null) continue;
      _fireIn(block, child, from, to);
      if (context.isInterrupted) return;
    }
  }

  /// Fires what the child passes while our clock goes from [from] to [to]
  /// inside [block].
  void _fireIn(
    TimelineBlock block,
    TimelinePlayback child,
    double from,
    double to,
  ) {
    final length = child.duration;
    if (length <= 0) return;
    // The step on the child's clock, not yet folded by its loop.
    final a = (from.clamp(block.start, block.end) - block.start) * block.speed;
    final b = (to.clamp(block.start, block.end) - block.start) * block.speed;
    // Which way the child's clock runs: ours, turned round by a negative
    // speed.
    final up = (to > from) == (block.speed >= 0);
    // Coming in over the block's edge, what sits on the edge happens too.
    final entering = to > from ? from < block.start : from > block.end;
    final nudge = entering ? (up ? -1e-9 : 1e-9) : 0.0;

    if (!block.loop) {
      child.fireBetween(
        a.clamp(0.0, length) + nudge,
        b.clamp(0.0, length).toDouble(),
      );
      return;
    }

    // A looping child: split the step at every lap. The end and the start
    // are the same moment, so what sits on either happens at the wrap.
    if (up) {
      final firstLap = (a / length).floor();
      final lastLap = (b / length).floor();
      final start = a - firstLap * length;
      final end = b - lastLap * length;
      if (firstLap == lastLap) {
        child.fireBetween(start + nudge, end);
        return;
      }
      child.fireBetween(start + nudge, length);
      if (child.isInterrupted) return;
      final laps = lastLap - firstLap - 1;
      for (var i = 0; i < laps && i < _maxLaps; i++) {
        child.fireBetween(-1e-9, length);
        if (child.isInterrupted) return;
      }
      child.fireBetween(-1e-9, end);
    } else {
      // Backwards a lap runs from its end down to its start: a time on a
      // lap's edge is the end of the one below.
      final firstLap = (a / length).ceil() - 1;
      final lastLap = (b / length).ceil() - 1;
      final start = a - firstLap * length;
      final end = b - lastLap * length;
      if (firstLap == lastLap) {
        child.fireBetween(start + nudge, end);
        return;
      }
      child.fireBetween(start + nudge, 0);
      if (child.isInterrupted) return;
      final laps = firstLap - lastLap - 1;
      for (var i = 0; i < laps && i < _maxLaps; i++) {
        child.fireBetween(length + 1e-9, 0);
        if (child.isInterrupted) return;
      }
      child.fireBetween(length + 1e-9, end);
    }
  }

  @override
  void apply(TimelineContext context, double time) {
    final block = track.blockAt(time);
    if (!identical(block, _current)) {
      final left = _current == null ? null : _children[_current!.value];
      if (left != null && (block == null || block.value != _current!.value)) {
        // Time may step clean over a block's edge: leave the child on the
        // edge it went out by, not wherever the last frame found it.
        final was = _current!;
        left
          ..seek(_local(was, left, time >= was.end ? was.end : was.start))
          ..stop();
      }
      _current = block;
    }
    final child = block == null ? null : _childFor(context, block.value);
    if (block == null || child == null) return;
    child.seek(_local(block, child, time));
  }

  void _drop(TimelineContext context) {
    _generation++;
    for (final child in _children.values) {
      child?.dispose();
    }
    _children.clear();
    _current = null;
  }

  @override
  void end(TimelineContext context) => _drop(context);
}
