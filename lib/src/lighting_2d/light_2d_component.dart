library;

import 'dart:ui' show Color;

import '../ecs/ecs.dart';

/// What kind of light a [Light2DComponent] is.
enum Light2DKind {
  /// Light all round its entity, fading to nothing at its radius.
  point,

  /// A cone of light from its entity along the entity's turn (0 points
  /// right, +X), [Light2DComponent.coneAngle] wide.
  spot,
}

/// Lights a 2-D scene that has [Lighting2DComponent] on: sprites, shapes and tile
/// layers are shaded by it — by the bumps their materials' normal maps draw
/// — and, where [castsShadows], darkened behind what casts shadows.
///
/// Its place is its entity's; a spot shines along the entity's turn.
class Light2DComponent extends Component {
  /// A light of [kind].
  Light2DComponent({
    this.kind = Light2DKind.point,
    this.colour = const Color(0xFFFFFFFF),
    this.intensity = 1,
    this.radius = 240,
    this.height = 48,
    this.falloff = 1.5,
    this.coneAngle = 60,
    this.coneSoftness = 0.25,
    this.castsShadows = true,
    this.enabled = true,
  });

  Light2DKind kind;

  /// Its colour; multiplied by [intensity].
  Color colour;

  /// How bright: 1 lights a surface facing it fully at its centre.
  double intensity;

  /// How far it reaches, in world units.
  double radius;

  /// How far above the scene it hangs, in world units: the lower, the more
  /// a normal map's bumps catch it from the side.
  double height;

  /// How it fades towards [radius]: 1 evenly, higher keeps it near its
  /// centre.
  double falloff;

  /// [Light2DKind.spot]: how wide the cone is, in degrees.
  double coneAngle;

  /// [Light2DKind.spot]: how soft the cone's edge is (0-1).
  double coneSoftness;

  /// Whether what casts shadows blocks it.
  bool castsShadows;

  /// Whether it shines.
  bool enabled;
}

/// Turns 2-D lighting on for the scene it is in: the frame is drawn, then
/// lit by every [Light2DComponent] near the view over [ambient] light. A scene without
/// one — or with it off — is drawn as it is, and pays nothing for lighting.
///
/// Put one on any entity — the camera, or a "Lighting" entity of its own.
/// Of several on, the first found is used.
class Lighting2DComponent extends Component {
  /// Lighting over [ambient].
  Lighting2DComponent({
    this.enabled = true,
    this.ambient = const Color(0xFF383848),
    this.ambientIntensity = 1,
    this.shadowSoftness = 0.3,
  });

  /// Whether the scene is lit.
  bool enabled;

  /// The light everywhere, without a [Light2DComponent]: black for a dark cave.
  Color ambient;

  /// How strong [ambient] is.
  double ambientIntensity;

  /// How soft shadows' edges are (0-1).
  double shadowSoftness;
}
