/// The 2-D material components: an entity's material, and the whole

/// frame's.
library;

import '../../../ecs/serialization/component_codec.dart';
import '../../../ecs/serialization/component_schema.dart';
import '../../../ecs/serialization/field_type.dart';
import '../../../foundation/dimensions.dart';
import 'material_2d_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'screen_material_component.dart';

/// The 2-D material components: an entity's material, and the whole
/// frame's.
abstract final class Material2DDefinitions {
  /// [Material2DComponent].
  static ComponentSchema<Material2DComponent> get material2D =>
      ComponentSchema<Material2DComponent>(
        type: 'Material2DComponent',
        id: 'material_2d_4c8e1b27',
        create: Material2DComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Material',
          group: 'Rendering',
          description:
              'Draws the sprite through a 2-D material file: an outline, a '
              'flash, a dissolve, a wave.',
          icon: Icons.auto_awesome,
          accentColor: Color(0xFFAB47BC),
          fields: {
            'material': FieldHint(
              label: 'Material',
              fileExtensions: ['material2d.json'],
            ),
            'overrides': FieldHint(
              label: 'Overrides',
              description:
                  "This entity's own values for what the game changes as it "
                  'runs, by key (flash.amount).',
            ),
          },
        ),
        fields: [
          SchemaField(
            name: 'material',
            kind: FieldTypes.assetRef,
            read: (c) => (c as Material2DComponent).material,
            write: (c, v) =>
                (c as Material2DComponent).material = v as String? ?? '',
          ),
          SchemaField(
            name: 'overrides',
            kind: MaterialOverridesFieldType.material2D,
            read: (c) =>
                Map<Object?, Object?>.of((c as Material2DComponent).overrides),
            write: (c, v) => (c as Material2DComponent).overrides = {
              if (v is Map)
                for (final e in v.entries)
                  if (e.value != null) '${e.key}': e.value as Object,
            },
          ),
        ],
      );

  /// [ScreenMaterialComponent].
  static ComponentSchema<ScreenMaterialComponent> get screenMaterial =>
      ComponentSchema<ScreenMaterialComponent>(
        type: 'ScreenMaterialComponent',
        id: 'screen_material_2d_71d3a0e5',
        create: ScreenMaterialComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Screen Material',
          group: 'Rendering',
          description:
              'Draws the whole view through a screen material: a vignette, '
              'a colour grade, scanlines, big pixels.',
          icon: Icons.filter_vintage,
          accentColor: Color(0xFFAB47BC),
          fields: {
            'material': FieldHint(
              label: 'Material',
              fileExtensions: ['material2d.json'],
            ),
            'enabled': FieldHint(label: 'Enabled'),
            'order': FieldHint(
              label: 'Order',
              description: 'Of several on, the highest is drawn.',
              scrub: ScrubHint(integer: true),
            ),
            'overrides': FieldHint(
              label: 'Overrides',
              description:
                  "This entity's own values for what changes as the game "
                  'runs, by key (vignette.amount).',
            ),
          },
        ),
        fields: [
          SchemaField(
            name: 'material',
            kind: FieldTypes.assetRef,
            read: (c) => (c as ScreenMaterialComponent).material,
            write: (c, v) =>
                (c as ScreenMaterialComponent).material = v as String? ?? '',
          ),
          SchemaField(
            name: 'enabled',
            kind: FieldTypes.boolean,
            read: (c) => (c as ScreenMaterialComponent).enabled,
            write: (c, v) =>
                (c as ScreenMaterialComponent).enabled = v as bool? ?? true,
          ),
          SchemaField(
            name: 'order',
            kind: FieldTypes.integer,
            read: (c) => (c as ScreenMaterialComponent).order,
            write: (c, v) => (c as ScreenMaterialComponent).order =
                (v as num?)?.toInt() ?? 0,
          ),
          SchemaField(
            name: 'overrides',
            kind: MaterialOverridesFieldType.material2D,
            read: (c) => Map<Object?, Object?>.of(
              (c as ScreenMaterialComponent).overrides,
            ),
            write: (c, v) => (c as ScreenMaterialComponent).overrides = {
              if (v is Map)
                for (final e in v.entries)
                  if (e.value != null) '${e.key}': e.value as Object,
            },
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [material2D, screenMaterial];
}
