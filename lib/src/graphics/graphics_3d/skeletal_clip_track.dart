import '../../ecs/ecs.dart';
import '../../timeline/timeline.dart';
import 'model_components.dart';
import 'graphics_models.dart';

/// A timeline track playing clips on the bound entity's 3-D model (its
/// [AnimationPlayerComponent]): each block names a clip, plays at the
/// block's speed, and loops as the block says. Entering a block crossfades
/// over the player's crossfade; between blocks the model goes back to what
/// it was playing before — what was authored, unless something (an
/// animator) had taken it over, a blend tree's blend included. Scrubbing
/// puts the clip exactly where the block says it should be: wrapped into
/// it when the block loops, held at its end when not, from its end when
/// the block plays it backwards. It sets what the player plays at run
/// time, never what it saves.
///
/// Saved with kind `skeletalClip`; `Graphics3D` registers it.
class SkeletalClipTrack extends BlockTrack {
  /// A track of clip [blocks].
  SkeletalClipTrack({
    super.blocks,
    super.name,
    super.binding,
    super.muted,
    super.locked,
  });

  /// `skeletalClip`: the `kind` this track is saved as, and the id
  /// [TimelineTrackKinds] reads it by.
  static const String kindId = 'skeletalClip';

  @override
  String get kind => kindId;

  @override
  String get summary => 'Model clips';

  @override
  String? get valueLabel => 'Clip';

  @override
  bool get hasSpeed => true;

  @override
  TrackRunner createRunner() => _SkeletalClipRunner(this);

  @override
  SkeletalClipTrack rebuild({
    List<TimelineBlock>? blocks,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => SkeletalClipTrack(
    blocks: blocks ?? this.blocks,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  /// Reads a saved track of this kind; a missing key takes its default.
  factory SkeletalClipTrack.fromJson(Map<String, dynamic> json) =>
      SkeletalClipTrack(
        blocks: BlockTrack.blocksFrom(json),
        name: json['name'] as String? ?? '',
        binding: TrackBinding.fromJson(json['binding']),
        muted: json['muted'] == true,
        locked: json['locked'] == true,
      );
}

class _SkeletalClipRunner extends TrackRunner {
  _SkeletalClipRunner(this.track);

  final SkeletalClipTrack track;
  TimelineBlock? _current;
  AnimationPlayerComponent? _player;

  // What the model was playing before the first block took it over — a
  // blend's clips, weights and speeds when it was blending — and whether
  // that was something set at run time rather than authored.
  String? _clipBefore;
  double _speedBefore = 1;
  bool _loopBefore = true;
  bool _drivenBefore = false;
  List<String> _blendBefore = const [];
  List<double> _weightsBefore = const [];
  List<double> _speedsBefore = const [];

  // Time came round into the current block over its start again — a
  // loop's wrap: its clip starts over.
  bool _reentered = false;

  @override
  void begin(TrackContext context) {
    _current = null;
    _player = null;
    _clipBefore = null;
    _reentered = false;
  }

  @override
  void advance(TrackContext context, double from, double to) {
    final current = _current;
    if (current == null) return;
    // Forwards over its start, or backwards over its end (as a backwards
    // loop wraps to it); a ping-pong turning round inside it is neither.
    if (to > from
        ? from < current.start && to >= current.start
        : from > current.end && to <= current.end) {
      _reentered = true;
    }
  }

  @override
  void apply(TrackContext context, double time) {
    final block = track.blockAt(time, includeEnd: context.endsAt(time));
    final entity = context.resolve(track.binding);
    final player = entity?.getComponent<AnimationPlayerComponent>();
    if (entity == null || player == null) return;
    if (!identical(block, _current) || _reentered) {
      _reentered = false;
      _current = block;
      if (block == null) {
        _restore();
        return;
      }
      if (_clipBefore == null) {
        _player = player;
        _clipBefore = player.playingClip;
        _speedBefore = player.playingSpeed;
        _loopBefore = player.playingLoop;
        _drivenBefore = player.isDriven;
        _blendBefore = List.of(player.blendClips);
        _weightsBefore = List.of(player.blendWeights);
        _speedsBefore = List.of(player.blendSpeeds);
      }
      // Played first, so what fades out keeps its own speed and looping.
      player
        // A scrub cuts; playing through crossfades.
        ..play(block.value, fade: context.isPreview ? 0 : null, restart: true)
        ..playingSpeed = block.speed
        ..playingLoop = block.loop;
    }
    if (block != null && context.isPreview) {
      // Scrubbing: the clip stands where the timeline says.
      final at = _timeIn(block, time, _lengthOf(context, entity, block.value));
      player
        ..time = at
        ..previousTime = at;
    }
  }

  /// Seconds into [block]'s clip, [length] long (0 while not known), at
  /// the timeline's [time]: wrapped into it when the block loops, held at
  /// its ends when not; played backwards, from its end.
  static double _timeIn(TimelineBlock block, double time, double length) {
    final played = (time - block.start) * block.speed;
    if (length <= 0) return played;
    final t = block.speed < 0 ? length + played : played;
    if (!block.loop) return t.clamp(0.0, length);
    final r = t % length;
    return r < 0 ? r + length : r;
  }

  /// The length of [entity]'s model's clip [name], seconds; 0 while it is
  /// not known (no 3-D graphics, or the model is not loaded).
  static double _lengthOf(TrackContext context, Entity entity, String name) {
    final path = entity.getComponent<ModelComponent>()?.model ?? '';
    if (path.isEmpty) return 0;
    final models = context.world.context.graphicsModels;
    return models?.get(path)?.clips[name]?.duration ?? 0;
  }

  void _restore() {
    final player = _player, clip = _clipBefore;
    if (player == null || clip == null) return;
    if (_drivenBefore) {
      if (_blendBefore.isNotEmpty) {
        // A blend tree's: its blend again, which its animator goes on
        // weighing.
        player.playBlend(_blendBefore, _weightsBefore, speeds: _speedsBefore);
      } else {
        player.play(clip, restart: true);
      }
      player
        ..playingSpeed = _speedBefore
        ..playingLoop = _loopBefore;
    } else {
      // Nothing had taken it over: back to what was authored.
      player.release();
    }
    _clipBefore = null;
  }

  @override
  void end(TrackContext context) {
    if (_current != null) _restore();
    _current = null;
  }
}
