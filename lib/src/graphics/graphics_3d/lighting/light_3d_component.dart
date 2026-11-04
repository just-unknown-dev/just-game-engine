import 'dart:ui' show Color;

import '../../../ecs/ecs.dart';

// Plain data with no GPU imports, so scenes that hold it load everywhere,
// the web included (where it simply draws nothing).

/// The kind of a [Light3DComponent].
enum Light3DKind {
  /// Light from far away along the entity's forward (+Z) axis: the sun.
  directional,

  /// Light from the entity's position in every direction.
  point,

  /// A cone of light from the entity's position along its forward axis.
  spot,
}

/// A light at its entity's transform. Directional and spot lights shine
/// along the entity's forward (+Z) axis.
class Light3DComponent extends Component {
  /// A light of [kind].
  Light3DComponent({
    this.kind = Light3DKind.point,
    this.color = const Color(0xFFFFFFFF),
    this.intensity = 10.0,
    this.range = 0.0,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = 0.7853981633974483,
  });

  /// Directional, point or spot.
  Light3DKind kind;

  /// Its colour (sRGB, as picked).
  Color color;

  /// Brightness: lux-like for a directional light, candela-like otherwise.
  double intensity;

  /// Where a point or spot light stops reaching, in metres; 0 for no limit.
  double range;

  /// Spot: full brightness inside this angle (radians).
  double innerConeAngle;

  /// Spot: no light outside this angle (radians).
  double outerConeAngle;
}
