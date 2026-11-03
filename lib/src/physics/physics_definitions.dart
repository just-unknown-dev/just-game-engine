/// Shared physics components: velocity, which 2-D physics, movement and
/// the camera all read.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_schema.dart';
import '../ecs/serialization/field_type.dart';
import '../ecs/serialization/schema_fields.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';
import 'velocity_component.dart';

/// Shared physics components: velocity.
abstract final class PhysicsDefinitions {
  /// Definition of [VelocityComponent], saved as `VelocityComponent`.
  static ComponentDefinition<VelocityComponent> get velocity =>
      ComponentDefinition<VelocityComponent>(
        type: 'VelocityComponent',
        hints: const ComponentHints(
          name: 'Velocity',
          group: 'Core',
          description: 'Linear velocity.',
          icon: Icons.speed,
          accentColor: Color(0xFF607D8B),
          fieldGroups: {
            'Velocity': ['velocity'],
            'Settings': ['maxSpeed'],
          },
          fields: {
            'velocity': FieldHint(
              label: 'Velocity',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'maxSpeed': FieldHint(
              label: 'Max Speed',
              scrub: ScrubHint(fractionDigits: 1),
            ),
          },
        ),
        create: VelocityComponent.new,
        fields: [
          SchemaField(
            name: 'velocity',
            kind: FieldTypes.vector3,
            read: (c) => Vector3.copy((c as VelocityComponent).velocity),
            write: (c, v) =>
                (c as VelocityComponent).velocity.setFrom(v as Vector3),
          ),
          SchemaFields.decimal(
            'maxSpeed',
            (c) => (c as VelocityComponent).maxSpeed,
            (c, v) => (c as VelocityComponent).maxSpeed = v,
            min: 0,
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [velocity];
}
