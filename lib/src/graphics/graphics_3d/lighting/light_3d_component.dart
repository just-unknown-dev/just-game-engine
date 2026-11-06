import 'dart:ui' show Color;

// just_graphics_engine's light kinds; its assets library is plain data and
// reaches no GPU code.
import 'package:just_graphics_engine/assets.dart' show Light3DKind;

import '../../../ecs/ecs.dart';

// Plain data with no GPU imports, so scenes that hold it load everywhere,
// the web included (where it simply draws nothing).

/// A light at its entity's transform. A [Light3DKind.directional] light
/// shines from far away along the entity's forward (+Z) axis (the sun), a
/// [Light3DKind.point] light from its position in every direction, and a
/// [Light3DKind.spot] light in a cone from its position along that axis.
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
