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
    this.channel = AudioChannel.sfx,
    this.is3d = false,
  });

  final String clipPath;
  double volume;
  double pan;
  AudioChannel channel;
  bool is3d;
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
