import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

import '../../../ecs/ecs.dart';
import '../../../foundation/dimensions.dart';
import 'material_3d_overrides_field_type.dart';
import 'material_overrides_3d_component.dart';

/// How the 3-D material components are saved and shown in an editor.
abstract final class Material3DDefinitions {
  /// The kind of [MaterialOverrides3DComponent.values]: the values an
  /// entity overrides of its materials.
  static const Material3DOverridesFieldType overridesType =
      Material3DOverridesFieldType();

  /// The field types the 3-D material components are saved through,
  /// registered by `Graphics3D` with its definitions.
  static const List<FieldType> fieldTypes = [overridesType];

  /// [MaterialOverrides3DComponent].
  static ComponentDefinition<MaterialOverrides3DComponent>
  get materialOverrides3D => ComponentDefinition<MaterialOverrides3DComponent>(
    type: 'MaterialOverrides3DComponent',
    id: 'material_overrides_3d_9a4f2c61',
    create: MaterialOverrides3DComponent.new,
    hints: const ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Material Overrides',
      group: '3D',
      description:
          "This entity's own values for the material files it is drawn "
          'with: a colour, a glow, how its maps repeat.',
      icon: Icons.tune,
      accentColor: Color(0xFFAB47BC),
      fields: {'values': FieldHint(label: 'Values')},
    ),
    fields: [
      FieldDefinition(
        name: 'values',
        kind: overridesType,
        read: (c) => Map<Object?, Object?>.of(
          (c as MaterialOverrides3DComponent).values,
        ),
        write: (c, v) => (c as MaterialOverrides3DComponent).values = {
          if (v is Map)
            for (final e in v.entries)
              if (e.value != null) '${e.key}': e.value as Object,
        },
      ),
    ],
  );

  /// Every material component.
  static List<ComponentDefinition> get all => [materialOverrides3D];
}
