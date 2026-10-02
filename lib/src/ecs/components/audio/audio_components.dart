/// Audio ECS Components
///
/// Components for integrating audio with the ECS architecture.
library;

import '../../../subsystems/audio/audio.dart';
import '../../../foundation/world_axes.dart';
import '../../ecs.dart';

/// Component describing an audio source attached to an entity.
///
/// This is data-only. The actual loading and playback is handled by
/// [AudioSystem].
class AudioSourceComponent extends Component {
  /// A source for [clipPath] that plays once, at full volume, centred, at
  /// its original pitch and speed, as soon as `AudioSystem` sees it.
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

  /// The audio channel the source is meant for. `AudioSystem` cannot honour
  /// it yet — just_audio_engine plays every sound effect on
  /// [AudioChannel.sfx], its volume and bus included.
  AudioChannel channel;

  /// If true, the source uses 3D positional audio derived from the entity's
  /// [TransformComponent]; without a transform it plays flat.
  bool is3d;

  /// Pitch multiplier: 1.0 = original, 2.0 = one octave up.
  double pitch;

  /// Playback speed multiplier (1.0 = normal).
  double speed;

  /// DSP effects applied to this voice when playback starts.
  List<AudioEffect> effects;

  /// Internal source handle managed by [AudioSystem].
  Object? loadedSource;

  /// Internal playback handle managed by [AudioSystem].
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
    this.effects = const [],
  });

  /// Asset path to the audio clip.
  final String clipPath;

  /// Volume, 0.0 (silent) to 1.0 (full), scaled by the sfx channel's own
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

  /// The audio channel the sound is meant for. `AudioSystem` cannot honour
  /// it yet — just_audio_engine plays every sound effect on
  /// [AudioChannel.sfx], its volume and bus included.
  AudioChannel channel;

  /// Whether the sound is placed in 3-D at the entity's
  /// `TransformComponent` position; without a transform it plays flat.
  bool is3d;

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
  /// [AudioStream]. just_audio_engine does not route a stream through its
  /// channel yet, so the channel's volume does not apply.
  AudioChannel channel;

  /// How long the stream takes to fade in from silence to [volume] when
  /// it starts; null or zero starts it at [volume] at once.
  Duration? fadeInDuration;

  /// Internal [AudioStream] instance managed by [AudioSystem].
  AudioStream? stream;

  /// Whether the stream is currently open and playing.
  bool get isPlaying => stream?.isPlaying ?? false;
}

/// Marks an entity as the audio listener (typically the camera or player).
///
/// The [AudioSystem] reads the entity's [TransformComponent] and
/// forwards it to the native listener each frame.
///
/// The listener faces the way the world does ([WorldAxes]): forward into
/// the screen, up towards −Y. Its right is then +X, so a sound to the right
/// of it on screen plays on the right.
class AudioListenerComponent extends Component {
  /// A listener facing into the screen (+Z) with −Y up, unless the
  /// direction arguments say otherwise.
  AudioListenerComponent({
    this.forwardX = WorldAxes.forwardX,
    this.forwardY = WorldAxes.forwardY,
    this.forwardZ = WorldAxes.forwardZ,
    this.upX = WorldAxes.upX,
    this.upY = WorldAxes.upY,
    this.upZ = WorldAxes.upZ,
  });

  /// The direction the listener faces, in world axes; +Z by default.
  double forwardX, forwardY, forwardZ;

  /// The listener's up direction, in world axes; −Y by default.
  double upX, upY, upZ;
}
