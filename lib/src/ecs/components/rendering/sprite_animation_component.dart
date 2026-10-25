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
///
/// Its configuration is what was authored, and what a scene saves. What
/// plays at run time — the clip an animator or a timeline switched to, the
/// speed it set, the way it faces the sprite — is kept apart from it
/// ([playingClip], [playingSpeed], [playingFlipX]) and never saved, so an
/// editor that runs the game's systems while a scene is edited saves the
/// scene as it was authored.
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

  /// The clip it plays as authored: a tag in the atlas; empty plays every
  /// frame in order. [switchClip] plays another without changing this;
  /// what plays now is [playingClip].
  String clip;

  /// Start playing when the atlas has loaded.
  bool playOnStart;

  /// Playback rate as authored: 1 is the authored timing, 0 holds the
  /// frame. What it plays at now is [playingSpeed].
  double speed;

  /// Draw the frames mirrored left to right, as authored. How they are
  /// drawn now is [playingFlipX].
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

  /// Seconds into the current pass of [playingClip].
  double elapsed = 0.0;

  /// Index of the showing frame within the clip.
  int frameIndex = 0;

  /// True once a clip that does not loop has shown its last frame.
  bool isComplete = false;

  /// Whether [playOnStart] has been acted on.
  bool initialized = false;

  /// When set, overrides whether the clip loops; null takes the clip's own.
  bool? loopOverride;

  String? _clipNow;
  double? _speedNow;
  bool? _flipXNow;

  /// The clip playing: what [switchClip] last chose, else [clip] as
  /// authored.
  String get playingClip => _clipNow ?? clip;

  /// The rate playing: what was set here at run time, else [speed].
  double get playingSpeed => _speedNow ?? speed;
  set playingSpeed(double value) => _speedNow = value;

  /// Whether the frames are drawn mirrored left to right now: what was set
  /// here at run time (an animator turning the sprite the way it moves),
  /// else [flipX].
  bool get playingFlipX => _flipXNow ?? flipX;
  set playingFlipX(bool value) => _flipXNow = value;

  /// Whether something at run time has taken over from what was authored:
  /// a clip switched to, a speed, a facing or a looping set.
  bool get isDriven =>
      _clipNow != null ||
      _speedNow != null ||
      _flipXNow != null ||
      loopOverride != null;

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

  /// Plays [name] from its first frame, [loop] overriding whether it loops
  /// (null: the clip's own). Asking for the clip that is already playing
  /// does nothing unless [restartIfSame]. The authored [clip] stays as it
  /// is.
  void switchClip(String name, {bool restartIfSame = false, bool? loop}) {
    loopOverride = loop;
    if (name == playingClip && !restartIfSame) {
      isPlaying = true;
      return;
    }
    _clipNow = name;
    restart();
    isPlaying = true;
  }

  /// Lets go of everything set at run time — the clip switched to, the
  /// speed, the facing, the looping — and plays what was authored from its
  /// first frame, as when it first loaded. What an animator or a timeline
  /// does when it lets go of the sprite.
  void release() {
    _clipNow = null;
    _speedNow = null;
    _flipXNow = null;
    loopOverride = null;
    restart();
    isPlaying = playOnStart;
  }

  @override
  String toString() =>
      'SpriteAnimation($atlasPath, clip: $playingClip, frame: $frameIndex)';
}
