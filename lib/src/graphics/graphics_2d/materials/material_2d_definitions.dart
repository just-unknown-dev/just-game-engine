/// The 2-D material components: an entity's material, and the whole

/// frame's.
library;

import '../../../ecs/serialization/component_codec.dart';
import '../../../ecs/serialization/component_definition.dart';
import '../../../ecs/serialization/field_type.dart';
import '../../../foundation/dimensions.dart';
import 'material_2d_component.dart';
import 'material_2d_overrides_field_type.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'screen_material_component.dart';

/// The 2-D material components: an entity's material, and the whole
/// frame's.
abstract final class Material2DDefinitions {
  /// The kind of both components' `overrides`: the values an entity
  /// overrides of its material.
  static const Material2DOverridesFieldType overridesType =
      Material2DOverridesFieldType();

  /// The field types the 2-D material components are saved through,
  /// registered into a context with the engine's definitions
  /// (`BuiltInComponents.extension`).
  static const List<FieldType> fieldTypes = [overridesType];

  /// [Material2DComponent].
  static ComponentDefinition<Material2DComponent> get material2D =>
      ComponentDefinition<Material2DComponent>(
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
          FieldDefinition(
            name: 'material',
            kind: FieldTypes.assetRef,
            read: (c) => (c as Material2DComponent).material,
            write: (c, v) =>
                (c as Material2DComponent).material = v as String? ?? '',
          ),
          FieldDefinition(
            name: 'overrides',
            kind: overridesType,
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
  static ComponentDefinition<ScreenMaterialComponent> get screenMaterial =>
      ComponentDefinition<ScreenMaterialComponent>(
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
          FieldDefinition(
            name: 'material',
            kind: FieldTypes.assetRef,
            read: (c) => (c as ScreenMaterialComponent).material,
            write: (c, v) =>
                (c as ScreenMaterialComponent).material = v as String? ?? '',
          ),
          FieldDefinition(
            name: 'enabled',
            kind: FieldTypes.boolean,
            read: (c) => (c as ScreenMaterialComponent).enabled,
            write: (c, v) =>
                (c as ScreenMaterialComponent).enabled = v as bool? ?? true,
          ),
          FieldDefinition(
            name: 'order',
            kind: FieldTypes.integer,
            read: (c) => (c as ScreenMaterialComponent).order,
            write: (c, v) => (c as ScreenMaterialComponent).order =
                (v as num?)?.toInt() ?? 0,
          ),
          FieldDefinition(
            name: 'overrides',
            kind: overridesType,
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
