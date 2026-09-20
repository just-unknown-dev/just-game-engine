/// Procedural camera motion.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;

/// One layer of noise: how fast and how far.
class NoiseOctave {
  const NoiseOctave(this.frequency, this.amplitude);

  /// Cycles per second.
  final double frequency;

  /// Peak contribution — screen pixels for position, radians for rotation.
  final double amplitude;
}

/// A recipe for continuous camera motion, as layers of smooth noise.
///
/// Position amplitudes are in **screen pixels**, so a shot feels equally
/// handheld at any zoom.
class CameraNoiseProfile {
  const CameraNoiseProfile({required this.position, this.rotation = const []});

  final List<NoiseOctave> position;
  final List<NoiseOctave> rotation;

  /// Screen-pixel offset at [time] seconds.
  Offset positionAt(double time) =>
      Offset(_sum(position, time, seed: 11), _sum(position, time, seed: 47));

  /// Roll, in radians, at [time] seconds.
  double rotationAt(double time) => _sum(rotation, time, seed: 83);

  static double _sum(
    List<NoiseOctave> octaves,
    double time, {
    required int seed,
  }) {
    var total = 0.0;
    for (var i = 0; i < octaves.length; i++) {
      total +=
          noise(seed + i * 13, time * octaves[i].frequency) *
          octaves[i].amplitude;
    }
    return total;
  }

  /// Smooth value noise in [-1, 1]: the same [seed] and [t] always give the
  /// same answer, on every platform, so a shot looks the same each run.
  static double noise(int seed, double t) {
    final i = t.floorToDouble();
    final f = t - i;
    final u = f * f * (3 - 2 * f);
    final a = _hash(i, seed);
    final b = _hash(i + 1, seed);
    return a + (b - a) * u;
  }

  // A sine hash rather than integer bit-twiddling: integers are 64-bit on
  // native and doubles on the web, and the two must agree.
  static double _hash(double n, int seed) {
    final v = math.sin(n * 12.9898 + seed * 78.233) * 43758.5453;
    return (v - v.floorToDouble()) * 2 - 1;
  }
}

/// The noise recipes a [CameraNoiseProfile] can be picked from by name.
enum CameraNoisePreset {
  handheldMild,
  handheldNormal,
  handheldStrong,

  /// Fast and tight: an engine running, a rumbling floor.
  shake;

  CameraNoiseProfile get profile => switch (this) {
    handheldMild => const CameraNoiseProfile(
      position: [NoiseOctave(0.35, 3), NoiseOctave(0.9, 1)],
      rotation: [NoiseOctave(0.3, 0.003)],
    ),
    handheldNormal => const CameraNoiseProfile(
      position: [
        NoiseOctave(0.45, 6),
        NoiseOctave(1.3, 2.5),
        NoiseOctave(3, 0.8),
      ],
      rotation: [NoiseOctave(0.4, 0.006), NoiseOctave(1.1, 0.002)],
    ),
    handheldStrong => const CameraNoiseProfile(
      position: [NoiseOctave(0.6, 12), NoiseOctave(1.8, 5), NoiseOctave(4, 2)],
      rotation: [NoiseOctave(0.5, 0.012), NoiseOctave(1.6, 0.005)],
    ),
    shake => const CameraNoiseProfile(
      position: [NoiseOctave(14, 4), NoiseOctave(27, 2)],
      rotation: [NoiseOctave(11, 0.004)],
    ),
  };
}
