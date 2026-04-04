part of '../sprite_atlas_subsystem.dart';

/// A single frame within an [AtlasAnimationClip], pairing a [SpriteRegion]
/// name with how long that frame is displayed.
class AtlasFrame {
  /// Name of the [SpriteRegion] to display for this frame.
  final String regionName;

  /// How long this frame is shown, in **seconds**.
  ///
  /// Aseprite exports durations in milliseconds; the [AsepriteAtlasParser]
  /// converts them to seconds automatically.
  final double duration;

  const AtlasFrame({required this.regionName, required this.duration});

  @override
  String toString() => 'AtlasFrame("$regionName", ${duration}s)';
}

/// A named, reusable sequence of [AtlasFrame]s that forms one animation
/// (e.g. `"run"`, `"idle"`, `"jump_rise"`).
///
/// ## Source
/// Clips are:
/// - **Embedded** in the atlas JSON when the format supports it (Aseprite
///   `frameTags`, or a custom `"clips"` object in a TexturePacker variant).
/// - **Registered at runtime** via [SpriteAtlas.registerClip] /
///   [SpriteAtlas.registerClips] — useful for overriding imported data or
///   defining clips that span regions from multiple sources.
///
/// ## Per-frame durations
/// Each [AtlasFrame] carries its own [AtlasFrame.duration]; the clip therefore
/// supports mixed-rate animations (e.g. a slow anticipation frame, fast action
/// frames, slow follow-through) with no extra configuration.
class AtlasAnimationClip {
  /// Logical name used to look up this clip in [SpriteAtlas] (e.g. `"run"`).
  final String name;

  /// Ordered playback frames.
  final List<AtlasFrame> frames;

  /// Whether the clip loops after the last frame.
  ///
  /// Defaults to `true`.  Aseprite does not encode a per-tag loop flag, so
  /// all Aseprite-derived clips default to looping; override as needed via
  /// [SpriteAtlas.registerClip].
  final bool loop;

  const AtlasAnimationClip({
    required this.name,
    required this.frames,
    this.loop = true,
  });

  /// Total wall-clock duration of one full pass through all frames (seconds).
  double get totalDuration =>
      frames.fold(0.0, (acc, frame) => acc + frame.duration);

  @override
  String toString() =>
      'AtlasAnimationClip("$name", ${frames.length} frames, '
      '${totalDuration.toStringAsFixed(3)}s, loop: $loop)';
}
