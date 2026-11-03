/// The 2-D lighting components: lights, the scene's lighting, and shadow

/// casters.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_schema.dart';
import '../ecs/serialization/field_type.dart';
import '../foundation/dimensions.dart';
import 'light_2d_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'shadow_caster_2d_component.dart';

/// The 2-D lighting components: lights, the scene's lighting, and shadow
/// casters.
abstract final class Lighting2DDefinitions {
  /// [Light2DComponent].
  static ComponentSchema<Light2DComponent> get light2D =>
      ComponentSchema<Light2DComponent>(
        type: 'Light2DComponent',
        id: 'light_2d_8b5e2f94',
        create: Light2DComponent.new,
        hints: ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Light 2D',
          group: 'Lighting',
          description:
              'A point or spot light for a scene with Lighting 2D on: it '
              'shades sprites by their normal maps and casts shadows.',
          icon: Icons.lightbulb_outline,
          accentColor: const Color(0xFFFFCA28),
          fields: {
            'kind': const FieldHint(label: 'Kind'),
            'colour': const FieldHint(label: 'Colour'),
            'intensity': const FieldHint(
              label: 'Intensity',
              scrub: ScrubHint(step: 0.1, fractionDigits: 2),
            ),
            'radius': const FieldHint(
              label: 'Radius',
              scrub: ScrubHint(step: 4, fractionDigits: 0, suffix: 'px'),
            ),
            'height': const FieldHint(
              label: 'Height',
              description:
                  'How far above the scene it hangs: the lower, '
                  'the more bumps catch it from the side.',
              scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'px'),
            ),
            'falloff': const FieldHint(
              label: 'Falloff',
              scrub: ScrubHint(step: 0.1, fractionDigits: 1),
            ),
            'coneAngle': FieldHint(
              label: 'Cone',
              scrub: const ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
              visibleWhen: (c) =>
                  (c as Light2DComponent).kind == Light2DKind.spot,
            ),
            'coneSoftness': FieldHint(
              label: 'Cone edge',
              scrub: const ScrubHint(step: 0.05, fractionDigits: 2),
              visibleWhen: (c) =>
                  (c as Light2DComponent).kind == Light2DKind.spot,
            ),
            'castsShadows': const FieldHint(label: 'Casts shadows'),
            'enabled': const FieldHint(label: 'Enabled'),
          },
        ),
        fields: [
          SchemaField(
            name: 'kind',
            kind: const EnumFieldType(
              Light2DKind.values,
              fallback: Light2DKind.point,
              id: 'rendering.light2DKind',
            ),
            read: (c) => (c as Light2DComponent).kind,
            write: (c, v) => (c as Light2DComponent).kind = v as Light2DKind,
          ),
          SchemaField(
            name: 'colour',
            kind: FieldTypes.color,
            read: (c) => (c as Light2DComponent).colour,
            write: (c, v) => (c as Light2DComponent).colour = v as Color,
          ),
          SchemaField(
            name: 'intensity',
            kind: FieldTypes.decimal,
            read: (c) => (c as Light2DComponent).intensity,
            write: (c, v) =>
                (c as Light2DComponent).intensity = (v as num).toDouble(),
            min: 0,
          ),
          SchemaField(
            name: 'radius',
            kind: FieldTypes.decimal,
            read: (c) => (c as Light2DComponent).radius,
            write: (c, v) =>
                (c as Light2DComponent).radius = (v as num).toDouble(),
            min: 0,
          ),
          SchemaField(
            name: 'height',
            kind: FieldTypes.decimal,
            read: (c) => (c as Light2DComponent).height,
            write: (c, v) =>
                (c as Light2DComponent).height = (v as num).toDouble(),
            min: 0,
          ),
          SchemaField(
            name: 'falloff',
            kind: FieldTypes.decimal,
            read: (c) => (c as Light2DComponent).falloff,
            write: (c, v) =>
                (c as Light2DComponent).falloff = (v as num).toDouble(),
            min: 0.1,
          ),
          SchemaField(
            name: 'coneAngle',
            kind: FieldTypes.decimal,
            read: (c) => (c as Light2DComponent).coneAngle,
            write: (c, v) =>
                (c as Light2DComponent).coneAngle = (v as num).toDouble(),
            min: 0,
          ),
          SchemaField(
            name: 'coneSoftness',
            kind: FieldTypes.decimal,
            read: (c) => (c as Light2DComponent).coneSoftness,
            write: (c, v) =>
                (c as Light2DComponent).coneSoftness = (v as num).toDouble(),
            min: 0,
          ),
          SchemaField(
            name: 'castsShadows',
            kind: FieldTypes.boolean,
            read: (c) => (c as Light2DComponent).castsShadows,
            write: (c, v) => (c as Light2DComponent).castsShadows = v as bool,
          ),
          SchemaField(
            name: 'enabled',
            kind: FieldTypes.boolean,
            read: (c) => (c as Light2DComponent).enabled,
            write: (c, v) => (c as Light2DComponent).enabled = v as bool,
          ),
        ],
      );

  /// [Lighting2DComponent].
  static ComponentSchema<Lighting2DComponent> get lighting2D =>
      ComponentSchema<Lighting2DComponent>(
        type: 'Lighting2DComponent',
        id: 'lighting_2d_3f61c8a2',
        create: Lighting2DComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Lighting 2D',
          group: 'Lighting',
          description:
              'Turns 2-D lighting on for the scene: lit by every Light 2D '
              'over the ambient light.',
          icon: Icons.wb_twilight,
          accentColor: Color(0xFFFFCA28),
          fields: {
            'enabled': FieldHint(label: 'Enabled'),
            'ambient': FieldHint(label: 'Ambient'),
            'ambientIntensity': FieldHint(
              label: 'Ambient strength',
              scrub: ScrubHint(step: 0.05, fractionDigits: 2),
            ),
            'shadowSoftness': FieldHint(
              label: 'Shadow softness',
              scrub: ScrubHint(step: 0.05, fractionDigits: 2),
            ),
          },
        ),
        fields: [
          SchemaField(
            name: 'enabled',
            kind: FieldTypes.boolean,
            read: (c) => (c as Lighting2DComponent).enabled,
            write: (c, v) => (c as Lighting2DComponent).enabled = v as bool,
          ),
          SchemaField(
            name: 'ambient',
            kind: FieldTypes.color,
            read: (c) => (c as Lighting2DComponent).ambient,
            write: (c, v) => (c as Lighting2DComponent).ambient = v as Color,
          ),
          SchemaField(
            name: 'ambientIntensity',
            kind: FieldTypes.decimal,
            read: (c) => (c as Lighting2DComponent).ambientIntensity,
            write: (c, v) => (c as Lighting2DComponent).ambientIntensity =
                (v as num).toDouble(),
            min: 0,
          ),
          SchemaField(
            name: 'shadowSoftness',
            kind: FieldTypes.decimal,
            read: (c) => (c as Lighting2DComponent).shadowSoftness,
            write: (c, v) => (c as Lighting2DComponent).shadowSoftness =
                (v as num).toDouble(),
            min: 0,
          ),
        ],
      );

  /// [ShadowCaster2DComponent].
  static ComponentSchema<ShadowCaster2DComponent> get shadowCaster2D =>
      ComponentSchema<ShadowCaster2DComponent>(
        type: 'ShadowCaster2DComponent',
        id: 'shadow_caster_2d_d29a4c17',
        create: ShadowCaster2DComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Shadow Caster 2D',
          group: 'Lighting',
          description:
              'Its sprite or shape blocks 2-D lights: what is behind it from '
              'a light is in shadow.',
          icon: Icons.contrast,
          accentColor: Color(0xFF78909C),
          fields: {
            'enabled': FieldHint(label: 'Enabled'),
            'depth': FieldHint(
              label: 'Lit depth',
              description:
                  'How far into its shape the light reaches before its own '
                  'shadow: a wall face catching the light.',
              scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'px'),
            ),
          },
        ),
        fields: [
          SchemaField(
            name: 'enabled',
            kind: FieldTypes.boolean,
            read: (c) => (c as ShadowCaster2DComponent).enabled,
            write: (c, v) => (c as ShadowCaster2DComponent).enabled = v as bool,
          ),
          SchemaField(
            name: 'depth',
            kind: FieldTypes.decimal,
            read: (c) => (c as ShadowCaster2DComponent).depth,
            write: (c, v) =>
                (c as ShadowCaster2DComponent).depth = (v as num).toDouble(),
            min: 0,
            max: 64,
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [light2D, lighting2D, shadowCaster2D];
}
