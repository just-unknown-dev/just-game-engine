/// Shared physics components: velocity, which 2-D physics, movement and
/// the camera all read.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_definition.dart';
import '../ecs/serialization/field_type.dart';
import '../ecs/serialization/field_definitions.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';
import 'physics_field_types.dart';
import 'velocity_component.dart';

/// Shared physics components: velocity; and the field types both
/// dimensions' physics components are saved through.
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
          FieldDefinition(
            name: 'velocity',
            kind: FieldTypes.vector3,
            read: (c) => Vector3.copy((c as VelocityComponent).velocity),
            write: (c, v) =>
                (c as VelocityComponent).velocity.setFrom(v as Vector3),
          ),
          FieldDefinitions.decimal(
            'maxSpeed',
            (c) => (c as VelocityComponent).maxSpeed,
            (c, v) => (c as VelocityComponent).maxSpeed = v,
            min: 0,
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [velocity];

  /// A collision layer, 0 to 15, saved as its number; the editor offers the
  /// project's layer names.
  static const PhysicsLayerFieldType layerType = PhysicsLayerFieldType();

  /// A set of collision layers as a mask (bit `n` for layer `n`), or null
  /// for "as the project's grid says"; the editor offers the layers by name.
  static const PhysicsLayerMaskFieldType layerMaskType =
      PhysicsLayerMaskFieldType();

  /// A 2-D collision shape, stored as `{kind, ...dimensions}`.
  static const Shape2DFieldType shapeType = Shape2DFieldType();

  /// The physics field types, registered into a context with the engine's
  /// definitions (`BuiltInComponents.extension`); 3-D physics registers the
  /// layer and mask types itself.
  static const List<FieldType> fieldTypes = [
    layerType,
    layerMaskType,
    shapeType,
  ];

  // What the 2-D and 3-D bodies' fields say, word for word: both
  // dimensions' definitions show the same.

  /// The body type field's description.
  static const String bodyTypeDescription =
      'Static never moves: floors and walls. Kinematic moves only as its '
      'velocity says and cannot be pushed: moving platforms. Dynamic is '
      'fully simulated: it falls, bounces and is pushed.';

  /// The layer field's description.
  static const String layerDescription =
      'The collision layer it is on. Layers are named, and which collide '
      'chosen, in the Physics Layers dock.';

  /// The sensor field's description.
  static const String sensorDescription =
      'Reports what overlaps it and stops nothing: triggers, pickups, zones.';

  /// The friction field's description.
  static const String frictionDescription =
      'How much it holds back what slides along it: 0 is ice, 1 is rubber. '
      "A contact uses both bodies' friction together.";

  /// The restitution field's description.
  static const String restitutionDescription =
      'How much speed a hit gives back: 0 stops dead, 1 bounces back as fast '
      'as it came. A contact bounces as much as the less bouncy of its two '
      'bodies.';

  /// The gravity scale field's description.
  static const String gravityScaleDescription =
      'Gravity on it, times this: 0 floats, 2 falls hard.';

  /// The linear damping field's description.
  static const String linearDampingDescription =
      'How much of its speed it loses on its own each second, as air '
      'resistance would: 0 none, 1 about two thirds.';

  /// The continuous collision field's description.
  static const String continuousDescription =
      'Sweeps a small, fast body along its path each step, so it cannot pass '
      'through a thin wall. Costs more.';

  /// The can-sleep field's description.
  static const String canSleepDescription =
      'Lets it stop being simulated while it rests, until something touches '
      'it. Off keeps it awake, at a cost.';

  /// The lock-rotation field's description.
  static const String lockRotationDescription =
      'Never turned by what it hits: a character that slides along scenery '
      'instead of tipping over.';

  /// The detectable field's description.
  static const String detectableDescription =
      'Sensors detect it, rays hit it and bodies bump into it.';
}
