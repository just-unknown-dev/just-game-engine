library;

import '../ecs/ecs.dart';

/// Makes its entity's sprite or shape cast shadows from the [Light2DComponent]s that
/// cast them, in a scene with [Lighting2DComponent] on: light stops at its shape, and
/// what is behind it from the light is in shadow.
///
/// The side facing the light stays lit for [depth] world units into the
/// shape — so a wall's face catches the light — then fades into its own
/// shadow. A Level Map layer casts shadows with its own switch
/// (`MapLayerData.castsShadows`).
class ShadowCaster2DComponent extends Component {
  /// A shadow caster, lit [depth] units in.
  ShadowCaster2DComponent({this.enabled = true, this.depth = 12});

  /// Whether it casts shadows.
  bool enabled;

  /// How far into its shape the light reaches, in world units, before its
  /// own shadow.
  double depth;
}
