/// One-off camera disturbances: say what happened, let every shot react.
library;

import 'package:flutter/painting.dart' show Offset;

import 'camera_noise.dart';

/// Something that happened in the world that a camera should feel.
class CameraImpulse {
  CameraImpulse({
    required this.position,
    this.amplitude = 12.0,
    this.duration = 0.4,
    this.radius = 0.0,
    this.channel = 1,
    this.frequency = 22.0,
  });

  /// Where it happened, in world space.
  final Offset position;

  /// Peak displacement, in world units, for a camera at [position].
  final double amplitude;

  /// Seconds until it has died away.
  final double duration;

  /// Beyond this distance nothing is felt. `0` is felt everywhere.
  final double radius;

  /// The channel bit it is emitted on.
  final int channel;

  /// How fast it rattles, in cycles per second.
  final double frequency;

  double _age = 0;
  late final int _seed = _nextSeed++;
  static int _nextSeed = 1;

  bool get isSpent => duration <= 0 || _age >= duration;

  /// What a listener at [listener] feels right now.
  Offset _feltAt(Offset listener) {
    if (isSpent) return Offset.zero;
    var strength = amplitude;
    if (radius > 0) {
      final distance = (listener - position).distance;
      if (distance >= radius) return Offset.zero;
      strength *= 1 - distance / radius;
    }
    // Quadratic decay: a sharp hit that settles, rather than a linear fade
    // that still looks busy at the end.
    final left = 1 - _age / duration;
    strength *= left * left;
    final t = _age * frequency;
    return Offset(
          CameraNoiseProfile.noise(_seed * 3, t),
          CameraNoiseProfile.noise(_seed * 3 + 1, t),
        ) *
        strength;
  }
}

/// The impulses in the air. Owned by the camera brain, which ages them once a
/// frame; cameras with a listener read from it.
class CameraImpulseBus {
  final List<CameraImpulse> _active = [];

  int get activeCount => _active.length;

  void emit(CameraImpulse impulse) {
    if (impulse.duration > 0 && impulse.amplitude != 0) _active.add(impulse);
  }

  /// Ages every impulse by [dt] and drops the spent ones.
  void update(double dt) {
    if (_active.isEmpty || dt <= 0) return;
    for (final impulse in _active) {
      impulse._age += dt;
    }
    _active.removeWhere((i) => i.isSpent);
  }

  /// The total displacement felt at [listener] on any of [channels].
  Offset feltAt(Offset listener, {int channels = 1}) {
    var total = Offset.zero;
    for (final impulse in _active) {
      if (impulse.channel & channels == 0) continue;
      total += impulse._feltAt(listener);
    }
    return total;
  }

  void clear() => _active.clear();
}
