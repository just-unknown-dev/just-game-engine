/// Audio ECS Components
///
/// Components for integrating audio with the ECS architecture.
library;

import '../../../subsystems/audio/audio.dart';
import '../../ecs.dart';

/// Component describing an audio source attached to an entity.
///
/// This is data-only. The actual loading and playback is handled by
/// [AudioSystem].
class AudioSourceComponent extends Component {
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
  final String clipPath;

  /// Volume [0.0 – 1.0].
  double volume;

  /// Stereo pan [-1.0 … +1.0]. Ignored if [is3d] is true.
  double pan;

  /// Whether to loop the clip.
  bool loop;

  /// If true, playback starts as soon as the system processes this entity.
  bool playOnAdd;

  /// Which audio channel this source belongs to.
  AudioChannel channel;

  /// If true, the source uses 3D positional audio derived from the entity's
  /// [TransformComponent].
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

  final String clipPath;
  double volume;
  double pan;
  double pitch;
  double speed;
  AudioChannel channel;
  bool is3d;
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
  AudioStreamComponent({
    required this.path,
    this.volume = 1.0,
    this.loop = true,
    this.playOnAdd = true,
    this.channel = AudioChannel.music,
    this.fadeInDuration,
  });

  /// Asset path to the audio file.
  final String path;

  /// Volume [0.0 – 1.0].
  double volume;

  /// Whether to loop the stream indefinitely.
  bool loop;

  /// If true, streaming starts as soon as the system processes this entity.
  bool playOnAdd;

  /// Which audio channel this stream belongs to.
  AudioChannel channel;

  /// Optional fade-in duration applied when streaming starts.
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
class AudioListenerComponent extends Component {
  AudioListenerComponent({
    this.forwardX = 0,
    this.forwardY = 0,
    this.forwardZ = -1,
    this.upX = 0,
    this.upY = 1,
    this.upZ = 0,
  });

  double forwardX, forwardY, forwardZ;
  double upX, upY, upZ;
}
