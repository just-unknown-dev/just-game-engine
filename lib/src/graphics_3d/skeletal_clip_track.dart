import '../subsystems/timeline/timeline.dart';
import 'graphics_components.dart';

/// A timeline track playing clips on the bound entity's 3-D model (its
/// [AnimationPlayerComponent]): each block names a clip, plays at the
/// block's speed, and loops as the block says. Entering a block crossfades
/// over the player's crossfade; between blocks the model goes back to the
/// clip it was playing before. Scrubbing puts the clip exactly where the
/// block says it should be.
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

  // What the model was playing before the first block took it over.
  String? _clipBefore;
  double _speedBefore = 1;
  bool _loopBefore = true;

  // Time came round into the current block over its start again — a
  // loop's wrap: its clip starts over.
  bool _reentered = false;

  @override
  void begin(TimelineContext context) {
    _current = null;
    _player = null;
    _clipBefore = null;
    _reentered = false;
  }

  @override
  void advance(TimelineContext context, double from, double to) {
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
  void apply(TimelineContext context, double time) {
    final block = track.blockAt(time, includeEnd: context.endsAt(time));
    final player = context
        .resolve(track.binding)
        ?.getComponent<AnimationPlayerComponent>();
    if (player == null) return;
    if (!identical(block, _current) || _reentered) {
      _reentered = false;
      _current = block;
      if (block == null) {
        _restore();
        return;
      }
      if (_clipBefore == null) {
        _player = player;
        _clipBefore = player.clip;
        _speedBefore = player.speed;
        _loopBefore = player.loop;
      }
      // Played first, so what fades out keeps its own speed and looping.
      player
        // A scrub cuts; playing through crossfades.
        ..play(block.value, fade: context.isPreview ? 0 : null, restart: true)
        ..speed = block.speed
        ..loop = block.loop;
    }
    if (block != null && context.isPreview) {
      // Scrubbing: the clip stands where the timeline says.
      player
        ..time = (time - block.start) * block.speed
        ..previousTime = player.time;
    }
  }

  void _restore() {
    final player = _player, clip = _clipBefore;
    if (player == null || clip == null) return;
    player
      ..play(clip, restart: true)
      ..speed = _speedBefore
      ..loop = _loopBefore;
    _clipBefore = null;
  }

  @override
  void end(TimelineContext context) {
    if (_current != null) _restore();
    _current = null;
  }
}
