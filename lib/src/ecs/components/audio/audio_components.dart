/// Audio ECS Components
///
/// Components for integrating audio with the ECS architecture.
library;

import 'dart:math' as math;

import '../../../subsystems/audio/audio.dart';
import '../../ecs.dart';

/// Component describing an audio source attached to an entity.
///
/// This is data-only. The actual loading and playback is handled by
/// [AudioSystem]. The sound stops when the component or its entity goes.
class AudioSourceComponent extends Component {
  /// A source for [clipPath] that plays once, at full volume, centred, at
  /// its original pitch and speed, as soon as `AudioSystem` sees it.
  ///
  /// With [is3d] it is placed at the entity instead: full volume within
  /// [minDistance] of the listener, silent beyond [maxDistance], faded
  /// between by [rolloff].
  AudioSourceComponent({
    required this.clipPath,
    this.volume = 1.0,
    this.pan = 0.0,
    this.loop = false,
    this.playOnAdd = true,
    this.channel = AudioChannel.sfx,
    this.is3d = false,
    this.pitch = 1.0,
    this.speed = 1.0,
    this.effects = const [],
    this.minDistance = 1.0,
    this.maxDistance = 50.0,
    this.rolloff = AudioRolloff.inverse,
    this.dopplerLevel = 0.0,
    this.farCutoff = 0.0,
  });

  /// Asset path to the audio clip.
  String clipPath;

  /// Volume `[0.0 – 1.0]`.
  double volume;

  /// Stereo pan, -1.0 (left) to +1.0 (right); 0.0 is centred. Ignored
  /// while the source is placed in 3-D ([is3d] on an entity with a
  /// transform).
  double pan;

  /// Whether to loop the clip.
  bool loop;

  /// If true, playback starts as soon as the system processes this entity.
  bool playOnAdd;

  /// The channel the sound plays on: its volume scales the sound, and on
  /// the web it is the bus the sound goes through.
  AudioChannel channel;

  /// If true, the source is heard from where the entity is, relative to
  /// the listener ([AudioListenerComponent]); without a transform it plays
  /// flat.
  bool is3d;

  /// Pitch multiplier: 1.0 = original, 2.0 = one octave up.
  double pitch;

  /// Playback speed multiplier (1.0 = normal).
  double speed;

  /// DSP effects applied to this voice when playback starts.
  List<AudioEffect> effects;

  /// 3-D: within this distance of the listener, in world units, the sound
  /// plays at full volume.
  double minDistance;

  /// 3-D: at and beyond this distance the sound is silent (unless the
  /// [rolloff] is [AudioRolloff.none]), and muffled down to [farCutoff].
  double maxDistance;

  /// 3-D: how the sound fades between [minDistance] and [maxDistance].
  AudioRolloff rolloff;

  /// 3-D: how much moving changes the pitch — 0 none, 1 the real-world
  /// doppler effect (for a world in metres).
  double dopplerLevel;

  /// 3-D: the low-pass cutoff, in Hz, the sound is muffled to at
  /// [maxDistance]; 0 leaves it clear at any distance.
  double farCutoff;

  /// How the sound is heard in 3-D, from the fields above, made safe: a
  /// zero or negative [minDistance], or a [maxDistance] below it, cannot
  /// throw.
  AudioSpatial get spatial {
    final min = math.max(minDistance, 1e-3);
    return AudioSpatial(
      minDistance: min,
      maxDistance: math.max(maxDistance, min),
      rolloff: rolloff,
      dopplerLevel: math.max(dopplerLevel, 0),
      farCutoff: math.max(farCutoff, 0),
    );
  }

  /// Internal source handle managed by [AudioSystem].
  Object? loadedSource;

  /// Internal playback handle managed by [AudioSystem]: the sound's ID while
  /// it plays, null once it has stopped or played to its end.
  Object? handle;
}

/// Trigger component: add this to an entity to request one-shot playback.
///
/// The [AudioSystem] will play the sound and then remove this
/// component automatically.
class AudioPlayComponent extends Component {
  /// A request to play [clipPath] once, at full volume, centred, at its
  /// original pitch and speed, with no effects.
  AudioPlayComponent({
    required this.clipPath,
    this.volume = 1.0,
    this.pan = 0.0,
    this.pitch = 1.0,
    this.speed = 1.0,
    this.channel = AudioChannel.sfx,
    this.is3d = false,
    this.spatial = const AudioSpatial(),
    this.effects = const [],
  });

  /// Asset path to the audio clip.
  final String clipPath;

  /// Volume, 0.0 (silent) to 1.0 (full), scaled by its [channel]'s own
  /// volume.
  double volume;

  /// Stereo pan, -1.0 (left) to +1.0 (right); 0.0 is centred. Ignored
  /// while the sound is placed in 3-D ([is3d] on an entity with a
  /// transform).
  double pan;

  /// Pitch multiplier: 1.0 = original, 2.0 = one octave up.
  double pitch;

  /// Playback speed multiplier (1.0 = normal).
  double speed;

  /// The channel the sound plays on.
  AudioChannel channel;

  /// Whether the sound is placed in 3-D at the entity's
  /// `TransformComponent` position (where it is when it starts); without a
  /// transform it plays flat.
  bool is3d;

  /// How the sound is heard in 3-D.
  AudioSpatial spatial;

  /// DSP effects applied to the voice when playback starts.
  List<AudioEffect> effects;
}

/// Trigger component: add this to an entity to pause its active
/// [AudioSourceComponent] playback. Removed by [AudioSystem] after processing.
class AudioPauseComponent extends Component {}

/// Trigger component: add this to an entity to resume its paused
/// [AudioSourceComponent] playback. Removed by [AudioSystem] after processing.
class AudioResumeComponent extends Component {}

/// Trigger component: add this to an entity to stop its active
/// [AudioSourceComponent] playback. Removed by [AudioSystem] after processing.
class AudioStopComponent extends Component {}

/// Component that streams a large audio file without buffering it entirely.
///
/// Use for music tracks or long ambient loops. The [AudioSystem] opens an
/// [AudioStream] backed by the native streaming path and manages its lifecycle.
/// The stream stops when the component or its entity goes.
class AudioStreamComponent extends Component {
  /// A stream of [path] on the music channel that loops at full volume and
  /// starts as soon as `AudioSystem` sees it; no fade-in unless
  /// [fadeInDuration] is given.
  AudioStreamComponent({
    required this.path,
    this.volume = 1.0,
    this.loop = true,
    this.playOnAdd = true,
    this.channel = AudioChannel.music,
    this.fadeInDuration,
  });

  /// Asset path to the audio file.
  String path;

  /// Volume `[0.0 – 1.0]`.
  double volume;

  /// Whether to loop the stream indefinitely.
  bool loop;

  /// If true, streaming starts as soon as the system processes this entity.
  bool playOnAdd;

  /// The audio channel the stream is meant for, handed to its
  /// [AudioStream] (on the web, the bus it goes through). A stream bypasses
  /// the engine's channel volumes, so the channel's volume does not apply.
  AudioChannel channel;

  /// How long the stream takes to fade in from silence to [volume] when
  /// it starts; null or zero starts it at [volume] at once.
  Duration? fadeInDuration;

  /// Internal [AudioStream] instance managed by [AudioSystem].
  AudioStream? stream;

  /// Whether the stream is currently open and playing.
  bool get isPlaying => stream?.isPlaying ?? false;
}

/// Marks the entity that hears: 3-D sounds are panned and faded for where
/// it is and which way it faces.
///
/// By default it hears from the entity's own transform: its position, and
/// the way its rotation turns the world's forward (+Z) and up (−Y). Either
/// can come from the output camera instead — [atCamera], [faceCamera]. A
/// third-person game puts the listener on the player with [faceCamera]:
/// the hero's own sounds stay centred and full, the world's turn with the
/// view.
///
/// Only the first listener counts. With none, the `AudioSystem` hears from
/// the camera, when it has one.
class AudioListenerComponent extends Component {
  /// A listener at the entity, facing the way the entity does.
  AudioListenerComponent({this.atCamera = false, this.faceCamera = false});

  /// Hear from where the output camera is, not the entity. Needs the
  /// [AudioSystem] to be given the camera (the engine's default systems
  /// do).
  bool atCamera;

  /// Face the way the output camera faces, not the entity.
  bool faceCamera;
}
