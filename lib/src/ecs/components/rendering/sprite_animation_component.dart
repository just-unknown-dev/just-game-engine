library;

import 'package:flutter/painting.dart' show Color;

import '../../ecs.dart';

/// Plays a clip from a sprite atlas on this entity.
///
/// The atlas is the JSON a sprite tool exports beside its sheet — Aseprite's
/// format, which carries a duration per frame and the named tags that become
/// clips. This component is only the choice of what to play;
/// [SpriteAnimationSystem] loads the atlas, advances the frames and keeps the
/// entity's renderable showing the right one.
class SpriteAnimationComponent extends Component {
  /// Plays [clip] of the atlas at [atlasPath] at its authored speed once
  /// loaded, unflipped, untinted and without smoothing. An empty
  /// [atlasPath] shows nothing.
  SpriteAnimationComponent({
    this.atlasPath = '',
    this.clip = '',
    this.playOnStart = true,
    this.speed = 1.0,
    this.flipX = false,
    this.flipY = false,
    this.tint,
    this.pixelArt = true,
  });

  // ── Configuration ────────────────────────────────────────────────────────

  /// Asset path of the atlas JSON (e.g. `assets/sprites/hero.json`).
  String atlasPath;

  /// The clip to play: a tag in the atlas. Empty plays every frame in order.
  /// Change it with [switchClip] so playback restarts cleanly.
  String clip;

  /// Start playing when the atlas has loaded.
  bool playOnStart;

  /// Playback rate: 1 is the authored timing, 0 holds the frame.
  double speed;

  /// Draw the frames mirrored left to right.
  bool flipX;

  /// Draw the frames mirrored top to bottom.
  bool flipY;

  /// Colour multiplied into every frame (a modulate filter); null draws
  /// the frames as they are.
  Color? tint;

  /// Sample the texture without smoothing, so scaled pixels stay square.
  bool pixelArt;

  // ── Runtime state (driven by SpriteAnimationSystem) ──────────────────────

  /// Whether the clip is advancing. Set by [play], [pause], [stop] and
  /// [switchClip]; set by the system when it acts on [playOnStart], and
  /// cleared when a clip that does not loop ends.
  bool isPlaying = false;

  /// Seconds into the current pass of [clip].
  double elapsed = 0.0;

  /// Index of the showing frame within the clip.
  int frameIndex = 0;

  /// True once a clip that does not loop has shown its last frame.
  bool isComplete = false;

  /// Whether [playOnStart] has been acted on.
  bool initialized = false;

  /// When set, overrides whether the clip loops; null takes the clip's own.
  bool? loopOverride;

  // ── Playback control ─────────────────────────────────────────────────────

  /// Plays on from the current frame; a clip that has finished starts again
  /// from its first frame.
  void play() {
    if (isComplete) restart();
    isPlaying = true;
  }

  /// Holds the current frame.
  void pause() => isPlaying = false;

  /// Stops and goes back to the clip's first frame.
  void stop() {
    isPlaying = false;
    restart();
  }

  /// Back to the clip's first frame, without changing whether it plays.
  void restart() {
    elapsed = 0.0;
    frameIndex = 0;
    isComplete = false;
  }

  /// Plays [name] from its first frame. Asking for the clip that is already
  /// playing does nothing unless [restartIfSame].
  void switchClip(String name, {bool restartIfSame = false, bool? loop}) {
    loopOverride = loop;
    if (name == clip && !restartIfSame) {
      isPlaying = true;
      return;
    }
    clip = name;
    restart();
    isPlaying = true;
  }

  @override
  String toString() =>
      'SpriteAnimation($atlasPath, clip: $clip, frame: $frameIndex)';
}
