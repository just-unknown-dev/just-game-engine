/// What a camera shows, as a value — and how one shot becomes another.
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/painting.dart' show Offset;

import 'camera_lens.dart';

/// Where a camera is, how far it is zoomed, how it is turned and through
/// what lens it looks.
///
/// A virtual camera *produces* one of these every frame; the brain blends
/// them and writes the result to the output camera. Being a value is the
/// point: two shots can be compared, blended and drawn as gizmos without
/// either of them being "the" camera.
///
/// A 2-D shot uses [position], [zoom] and [rotation] (roll) and leaves the
/// rest at their defaults: depth 0, no pitch or yaw, an orthographic lens.
class CameraState {
  const CameraState({
    this.position = Offset.zero,
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.z = 0.0,
    this.pitch = 0.0,
    this.yaw = 0.0,
    this.lens = const CameraLens(),
  });

  /// World point at the centre of the view (x, y).
  final Offset position;

  /// `1` = one world unit per pixel; larger is closer. Orthographic only.
  final double zoom;

  /// Roll, in radians.
  final double rotation;

  /// Depth of the camera — its world z.
  final double z;

  /// Turn about the world X axis, in radians (tilting up or down).
  final double pitch;

  /// Turn about the world Y axis, in radians (turning left or right).
  final double yaw;

  /// Orthographic or perspective, and how much it sees.
  final CameraLens lens;

  /// Whether this is a plain 2-D shot: no pitch or yaw, orthographic.
  bool get isPlanar => pitch == 0 && yaw == 0 && lens.isOrthographic;

  CameraState copyWith({
    Offset? position,
    double? zoom,
    double? rotation,
    double? z,
    double? pitch,
    double? yaw,
    CameraLens? lens,
  }) => CameraState(
    position: position ?? this.position,
    zoom: zoom ?? this.zoom,
    rotation: rotation ?? this.rotation,
    z: z ?? this.z,
    pitch: pitch ?? this.pitch,
    yaw: yaw ?? this.yaw,
    lens: lens ?? this.lens,
  );

  /// The shot [t] of the way from [a] to [b].
  ///
  /// Zoom is interpolated geometrically — halfway between 1× and 4× is 2×,
  /// which is what reads as "halfway" on screen; a linear 2.5× looks like the
  /// blend rushes at one end. Every angle takes the short way round; depth
  /// blends linearly and the lens as [CameraLens.lerp] says.
  static CameraState lerp(CameraState a, CameraState b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    final za = a.zoom <= 0 ? 0.0001 : a.zoom;
    final zb = b.zoom <= 0 ? 0.0001 : b.zoom;
    return CameraState(
      position: Offset.lerp(a.position, b.position, t)!,
      zoom: za * math.pow(zb / za, t),
      rotation: _angle(a.rotation, b.rotation, t),
      z: a.z + (b.z - a.z) * t,
      pitch: _angle(a.pitch, b.pitch, t),
      yaw: _angle(a.yaw, b.yaw, t),
      lens: CameraLens.lerp(a.lens, b.lens, t),
    );
  }

  /// [t] of the way from [a] to [b], the short way round.
  static double _angle(double a, double b, double t) {
    if (a == b) return a;
    var turn = (b - a) % (2 * math.pi);
    if (turn > math.pi) turn -= 2 * math.pi;
    return a + turn * t;
  }

  @override
  bool operator ==(Object other) =>
      other is CameraState &&
      other.position == position &&
      other.zoom == zoom &&
      other.rotation == rotation &&
      other.z == z &&
      other.pitch == pitch &&
      other.yaw == yaw &&
      other.lens == lens;

  @override
  int get hashCode =>
      Object.hash(position, zoom, rotation, z, pitch, yaw, lens);

  @override
  String toString() =>
      'CameraState(${position.dx.toStringAsFixed(1)}, '
      '${position.dy.toStringAsFixed(1)} ×${zoom.toStringAsFixed(2)})';
}

/// How long a change of shot takes, and how it eases.
class CameraBlend {
  const CameraBlend({this.duration = 0.5, this.curve = Curves.easeInOut});

  /// No blend: the new shot is on screen the next frame.
  static const CameraBlend cut = CameraBlend(duration: 0);

  /// Seconds from the old shot to the new one.
  final double duration;

  final Curve curve;

  bool get isCut => duration <= 0;
}

/// A blend for one pair of cameras, by entity name. `'*'` matches any.
class CameraBlendRule {
  const CameraBlendRule({this.from = any, this.to = any, required this.blend});

  static const String any = '*';

  final String from;
  final String to;
  final CameraBlend blend;

  int _scoreFor(String? fromName, String? toName) {
    final fromExact = from != any && from == fromName;
    final toExact = to != any && to == toName;
    if ((from != any && !fromExact) || (to != any && !toExact)) return -1;
    return (fromExact ? 2 : 0) + (toExact ? 1 : 0);
  }
}

/// Per-pair blends, over the brain's default.
///
/// The most specific rule wins: a named pair over a named side over `* → *`.
/// Between two one-sided rules, the one that names where the blend comes
/// *from* wins — leaving a cutscene camera is usually the special case.
class CameraBlendTable {
  CameraBlendTable([List<CameraBlendRule> rules = const []])
    : rules = List.of(rules);

  final List<CameraBlendRule> rules;

  /// The blend for going from [from] to [to], or null to use the default.
  CameraBlend? resolve(String? from, String? to) {
    CameraBlendRule? best;
    var bestScore = -1;
    for (final rule in rules) {
      final score = rule._scoreFor(from, to);
      if (score > bestScore) {
        best = rule;
        bestScore = score;
      }
    }
    return best?.blend;
  }
}
