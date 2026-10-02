/// Motion laid over a settled shot: handheld noise and impulses.
library;

import '../../../ecs/ecs.dart';
import '../../../subsystems/camera/camera_noise.dart';

/// Continuous procedural motion on a virtual camera: the difference between
/// a locked-off shot and one that feels held.
class CameraNoiseComponent extends Component {
  /// Noise from [preset] (normal handheld by default), played as authored
  /// unless [amplitudeGain] or [frequencyGain] say otherwise.
  CameraNoiseComponent({
    this.preset = CameraNoisePreset.handheldNormal,
    this.amplitudeGain = 1.0,
    this.frequencyGain = 1.0,
  });

  /// The recipe of motion played; its position amplitudes are screen
  /// pixels, so the shake looks the same at any zoom.
  CameraNoisePreset preset;

  /// Multiplies how far the shot moves. `0` switches the noise off.
  double amplitudeGain;

  /// Multiplies how fast it moves.
  double frequencyGain;

  @override
  String toString() => 'CameraNoise(${preset.name} ×$amplitudeGain)';
}

/// Makes a virtual camera feel the impulses emitted near it.
///
/// Impulses replace "shake the camera": whatever explodes says so once, and
/// every listening shot reacts by how close it is — including a shot that is
/// only blending in.
class CameraImpulseListenerComponent extends Component {
  /// A listener feeling impulses at full strength ([gain] `1`) on channel 1
  /// only ([channels] `1`).
  CameraImpulseListenerComponent({this.gain = 1.0, this.channels = 1});

  /// Multiplies what is felt.
  double gain;

  /// Bit mask of the impulse channels this camera reacts to.
  int channels;

  @override
  String toString() => 'CameraImpulseListener(gain: $gain)';
}

/// An authored impulse: what `CameraBrain.emitImpulseFrom` sends for this
/// entity — a landing, an explosion, a door slamming.
class CameraImpulseSourceComponent extends Component {
  /// The same defaults as a `CameraImpulse`: a 12-unit, 0.4-second jolt
  /// felt everywhere on channel 1.
  CameraImpulseSourceComponent({
    this.amplitude = 12.0,
    this.duration = 0.4,
    this.radius = 0.0,
    this.channel = 1,
  });

  /// Peak displacement, in world units, for a camera at the source.
  double amplitude;

  /// Seconds until it has died away.
  double duration;

  /// Beyond this distance nothing is felt. `0` is felt everywhere.
  double radius;

  /// The channel bit it is emitted on.
  int channel;

  @override
  String toString() => 'CameraImpulseSource($amplitude, ${duration}s)';
}
