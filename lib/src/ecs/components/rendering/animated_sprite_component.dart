library;

import '../../ecs.dart';
import '../animation/animation_event.dart';

// ── Easing ────────────────────────────────────────────────────────────────────

enum KeyframeEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut;

  double apply(double t) => switch (this) {
    linear => t,
    easeIn => t * t,
    easeOut => t * (2 - t),
    easeInOut => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t,
  };
}

// ── TransformKeyframe ─────────────────────────────────────────────────────────

/// A single time-stamped snapshot of transform properties on a clip.
///
/// Only properties that are non-null participate in interpolation for their
/// respective timeline tracks. Time is in seconds from the start of the clip.
class TransformKeyframe {
  const TransformKeyframe({
    required this.time,
    this.posX,
    this.posY,
    this.rotation,
    this.scaleX,
    this.scaleY,
    this.easing = KeyframeEasing.linear,
  });

  final double time;
  final double? posX;
  final double? posY;
  final double? rotation;
  final double? scaleX;
  final double? scaleY;
  final KeyframeEasing easing;

  factory TransformKeyframe.fromJson(Map<String, dynamic> json) =>
      TransformKeyframe(
        time: (json['time'] as num).toDouble(),
        posX: (json['posX'] as num?)?.toDouble(),
        posY: (json['posY'] as num?)?.toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble(),
        scaleX: (json['scaleX'] as num?)?.toDouble(),
        scaleY: (json['scaleY'] as num?)?.toDouble(),
        easing: KeyframeEasing.values.firstWhere(
          (e) => e.name == (json['easing'] as String? ?? 'linear'),
          orElse: () => KeyframeEasing.linear,
        ),
      );

  Map<String, dynamic> toJson() => {
    'time': time,
    if (posX != null) 'posX': posX,
    if (posY != null) 'posY': posY,
    if (rotation != null) 'rotation': rotation,
    if (scaleX != null) 'scaleX': scaleX,
    if (scaleY != null) 'scaleY': scaleY,
    if (easing != KeyframeEasing.linear) 'easing': easing.name,
  };

  TransformKeyframe copyWith({
    double? time,
    Object? posX = _sentinel,
    Object? posY = _sentinel,
    Object? rotation = _sentinel,
    Object? scaleX = _sentinel,
    Object? scaleY = _sentinel,
    KeyframeEasing? easing,
  }) =>
      TransformKeyframe(
        time: time ?? this.time,
        posX: posX == _sentinel ? this.posX : posX as double?,
        posY: posY == _sentinel ? this.posY : posY as double?,
        rotation: rotation == _sentinel ? this.rotation : rotation as double?,
        scaleX: scaleX == _sentinel ? this.scaleX : scaleX as double?,
        scaleY: scaleY == _sentinel ? this.scaleY : scaleY as double?,
        easing: easing ?? this.easing,
      );
}

const _sentinel = Object();

// ── AnimationClip ─────────────────────────────────────────────────────────────

/// Named clip referencing absolute frame indices in the sprite sheet grid.
class AnimationClip {
  AnimationClip({
    required this.name,
    required List<int> frames,
    this.fps,
    this.loop,
    this.blendDuration = 0.2,
    List<TransformKeyframe>? keyframes,
    List<AnimationEvent>? events,
  }) : frames = List<int>.from(frames),
       keyframes =
           keyframes == null
               ? <TransformKeyframe>[]
               : List<TransformKeyframe>.from(keyframes),
       events =
           events == null
               ? <AnimationEvent>[]
               : List<AnimationEvent>.from(events);

  final String name;

  /// Absolute sprite-sheet frame indices (row * columns + col).
  final List<int> frames;

  /// Per-clip FPS override; falls back to [AnimatedSpriteComponent.defaultFps].
  final double? fps;

  /// Per-clip loop override; falls back to [AnimatedSpriteComponent.loop].
  final bool? loop;

  /// Seconds to cross-blend from the previous clip when switching to this one.
  final double blendDuration;

  /// Time-based (seconds) transform keyframes for this clip.
  final List<TransformKeyframe> keyframes;

  /// Named time markers that fire when the playhead crosses their [AnimationEvent.time].
  final List<AnimationEvent> events;

  // ── Keyframe mutation helpers ────────────────────────────────────────────

  void addOrUpdateKeyframe(TransformKeyframe kf) {
    const eps = 0.05;
    final idx = keyframes.indexWhere((k) => (k.time - kf.time).abs() < eps);
    if (idx >= 0) {
      keyframes[idx] = keyframes[idx].copyWith(
        posX: kf.posX ?? keyframes[idx].posX,
        posY: kf.posY ?? keyframes[idx].posY,
        rotation: kf.rotation ?? keyframes[idx].rotation,
        scaleX: kf.scaleX ?? keyframes[idx].scaleX,
        scaleY: kf.scaleY ?? keyframes[idx].scaleY,
        easing: kf.easing,
      );
    } else {
      keyframes
        ..add(kf)
        ..sort((a, b) => a.time.compareTo(b.time));
    }
  }

  void removeKeyframe(int index) => keyframes.removeAt(index);

  void moveKeyframe(int index, double newTime) {
    final kf = keyframes.removeAt(index).copyWith(time: newTime);
    keyframes
      ..add(kf)
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  // ── Event mutation helpers ────────────────────────────────────────────────

  void addEvent(AnimationEvent event) {
    events
      ..add(event)
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  void removeEvent(int index) => events.removeAt(index);

  void moveEvent(int index, double newTime) {
    final ev = events.removeAt(index);
    events
      ..add(AnimationEvent(time: newTime, name: ev.name))
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  factory AnimationClip.fromJson(
    String name,
    Map<String, dynamic> json, {
    required int columns,
    required int rows,
  }) {
    final List<int> frames;
    if (json.containsKey('frames')) {
      frames = (json['frames'] as List).map((e) => (e as num).toInt()).toList();
    } else {
      final row = (json['row'] as num?)?.toInt() ?? 0;
      final startCol = (json['start'] as num?)?.toInt() ?? 0;
      final endCol =
          (json['end'] as num?)?.toInt() ?? (columns - 1).clamp(0, columns - 1);
      frames = List.generate(
        (endCol - startCol + 1).clamp(1, columns),
        (i) => row * columns + startCol + i,
      );
    }

    final kfsJson = json['keyframes'] as List?;
    final keyframes =
        kfsJson
            ?.map((k) => TransformKeyframe.fromJson(k as Map<String, dynamic>))
            .toList() ??
        <TransformKeyframe>[];

    final evJson = json['events'] as List?;
    final events =
        evJson
            ?.map((e) => AnimationEvent.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <AnimationEvent>[];

    return AnimationClip(
      name: name,
      frames: frames,
      fps: (json['fps'] as num?)?.toDouble(),
      loop: json['loop'] as bool?,
      blendDuration: (json['blendDuration'] as num?)?.toDouble() ?? 0.2,
      keyframes: keyframes,
      events: events,
    );
  }

  Map<String, dynamic> toJson() => {
    'frames': frames,
    if (fps != null) 'fps': fps,
    if (loop != null) 'loop': loop,
    'blendDuration': blendDuration,
    if (keyframes.isNotEmpty)
      'keyframes': keyframes.map((k) => k.toJson()).toList(),
    if (events.isNotEmpty) 'events': events.map((e) => e.toJson()).toList(),
  };
}

// ── AnimatedSpriteComponent ───────────────────────────────────────────────────

/// Sprite-sheet animation component.
///
/// Stores all configuration needed to:
///  - render a sprite sheet (path, frame grid)
///  - play named animation clips (frame sequences)
///  - drive per-clip time-based transform keyframes
///
/// The [EditorAnimatedSpriteSystem] reads this component every frame, advances
/// [elapsed], updates the [RenderableComponent]'s source-rect, and interpolates
/// transform keyframes onto the entity's [TransformComponent].
class AnimatedSpriteComponent extends Component {
  AnimatedSpriteComponent({
    this.spritePath = '',
    this.jsonPath = '',
    this.frameWidth = 64,
    this.frameHeight = 64,
    this.columns = 1,
    this.rows = 1,
    this.activeClip = '',
    this.defaultFps = 12.0,
    this.loop = true,
    this.playOnStart = true,
    Map<String, AnimationClip>? clips,
  }) : clips = clips ?? {};

  // ── Configuration ────────────────────────────────────────────────────────

  /// Asset path to the sprite sheet image (e.g. 'assets/sprites/hero.png').
  String spritePath;

  /// Optional path to a JSON animation config file. When set the system
  /// populates [frameWidth], [frameHeight], [columns], [rows], and [clips].
  String jsonPath;

  int frameWidth;
  int frameHeight;
  int columns;
  int rows;

  /// Name of the clip that should play. Set via [switchClip].
  String activeClip;

  /// Default FPS used when a clip doesn't override.
  double defaultFps;

  /// Default loop behaviour used when a clip doesn't override.
  bool loop;

  /// Start playing automatically when the entity is first processed.
  bool playOnStart;

  /// All named animation clips keyed by name.
  Map<String, AnimationClip> clips;

  // ── Runtime state (driven by EditorAnimatedSpriteSystem) ────────────────

  bool isPlaying = false;

  /// Playback position in seconds within [activeClip].
  double elapsed = 0.0;

  /// Current index into [AnimationClip.frames].
  int frameIndex = 0;

  /// Clip being cross-faded to, or null when not blending.
  String? blendingToClip;
  double blendElapsed = 0.0;
  double blendDuration = 0.2;

  bool initialized = false;

  // ── Computed ─────────────────────────────────────────────────────────────

  AnimationClip? get activeClipData => clips[activeClip];

  /// Absolute index of the current frame in the sprite sheet grid.
  int get currentAbsoluteFrame {
    final clip = activeClipData;
    if (clip == null || clip.frames.isEmpty) return 0;
    return clip.frames[frameIndex.clamp(0, clip.frames.length - 1)];
  }

  int get currentColumn =>
      columns > 0 ? currentAbsoluteFrame % columns : 0;

  int get currentRow =>
      columns > 0 ? currentAbsoluteFrame ~/ columns : 0;

  /// Duration of [activeClip] in seconds, or 0 if unknown.
  double get clipDuration {
    final clip = activeClipData;
    if (clip == null || clip.frames.isEmpty) return 0.0;
    final fps = clip.fps ?? defaultFps;
    return clip.frames.length / fps;
  }

  // ── Playback control ─────────────────────────────────────────────────────

  void play() => isPlaying = true;
  void pause() => isPlaying = false;

  void stop() {
    isPlaying = false;
    elapsed = 0.0;
    frameIndex = 0;
    blendingToClip = null;
    blendElapsed = 0.0;
  }

  void switchClip(String name, {bool blend = true}) {
    if (!clips.containsKey(name)) return;
    if (name == activeClip && blendingToClip == null) return;
    if (blend) {
      final target = clips[name]!;
      blendingToClip = name;
      blendElapsed = 0.0;
      blendDuration = target.blendDuration;
    } else {
      activeClip = name;
      elapsed = 0.0;
      frameIndex = 0;
    }
    isPlaying = true;
  }

  // ── JSON loading ─────────────────────────────────────────────────────────

  /// Populates this component from an animation JSON file.
  void loadFromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? {};
    frameWidth = (meta['frameWidth'] as num?)?.toInt() ?? frameWidth;
    frameHeight = (meta['frameHeight'] as num?)?.toInt() ?? frameHeight;
    columns = (meta['columns'] as num?)?.toInt() ?? columns;
    rows = (meta['rows'] as num?)?.toInt() ?? rows;

    final clipsJson =
        (json['clips'] as Map?)?.cast<String, dynamic>() ?? {};
    clips = {
      for (final e in clipsJson.entries)
        e.key: AnimationClip.fromJson(
          e.key,
          (e.value as Map).cast<String, dynamic>(),
          columns: columns,
          rows: rows,
        ),
    };

    if (activeClip.isEmpty && clips.isNotEmpty) {
      activeClip = clips.keys.first;
    }
  }

  /// Returns the clips map encoded for scene serialisation.
  Map<String, dynamic> clipsToJson() => {
    for (final e in clips.entries) e.key: e.value.toJson(),
  };

  /// Restores the clips map from serialised scene data.
  void clipsFromJson(Object? value) {
    if (value is! Map) return;
    final map = value.cast<String, dynamic>();
    clips = {
      for (final e in map.entries)
        if (e.value is Map)
          e.key: AnimationClip.fromJson(
            e.key,
            (e.value as Map).cast<String, dynamic>(),
            columns: columns,
            rows: rows,
          ),
    };
  }

  @override
  String toString() =>
      'AnimatedSprite($spritePath, clip: $activeClip, frame: $frameIndex)';
}
