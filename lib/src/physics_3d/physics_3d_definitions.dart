import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';
import 'package:just_physics_engine/physics_3d.dart';

import '../ecs/ecs.dart';
import '../ecs/serialization/serialization.dart';
import '../foundation/dimensions.dart';
import 'camera_collision_3d_component.dart';
import 'physics_3d_components.dart';
import '../physics_2d/physics_2d_definitions.dart';

/// How the 3-D physics components are saved and shown in an editor. Every
/// one is a 3-D component (`Dimensions.threeD`), in the `Physics` group the
/// 2-D ones are in — a body and a collider grouped, labelled and described
/// as `RigidBody2DComponent` and `Collider2DComponent` are.
abstract final class Physics3DDefinitions {
  static const String _group = 'Physics';

  static const _bodyType = EnumFieldType(
    BodyType3D.values,
    fallback: BodyType3D.dynamic,
    id: 'physics3d.bodyType',
  );
  static const _colliderShape = EnumFieldType(
    ColliderShape3D.values,
    fallback: ColliderShape3D.box,
    id: 'physics3d.colliderShape',
  );
  static const _motor = EnumFieldType(
    MotorState3D.values,
    fallback: MotorState3D.off,
    id: 'physics3d.motor',
  );
  static const _axisMode = EnumFieldType(
    SixDofAxisMode3D.values,
    fallback: SixDofAxisMode3D.fixed,
    id: 'physics3d.axisMode',
  );

  static const _metres = ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm');
  static const _plain = ScrubHint(step: 0.05, fractionDigits: 2);

  /// [RigidBody3DComponent]: grouped, labelled and described as `RigidBody2DComponent` is.
  static ComponentSchema<RigidBody3DComponent>
  get rigidBody => ComponentSchema<RigidBody3DComponent>(
    type: 'RigidBody3DComponent',
    id: 'rigid_body_3d_d3ff8994',
    create: RigidBody3DComponent.new,
    hints: ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Rigid Body 3D',
      group: _group,
      description:
          'Simulates the entity: gravity, forces and collisions. Its shape is a Collider 3D.',
      icon: Icons.sports_basketball,
      accentColor: const Color(0xFFFF7043),
      fieldGroups: const {
        'Body': ['bodyType', 'mass', 'layer', 'isSensor'],
        'Surface': ['friction', 'restitution'],
        'Motion': [
          'gravityScale',
          'linearDamping',
          'angularDamping',
          'continuousCollision',
          'canSleep',
          'lockRotation',
          'initialVelocity',
          'initialAngularVelocity',
        ],
      },
      fields: {
        'bodyType': const FieldHint(
          label: 'Body type',
          description: Physics2DDefinitions.bodyTypeDescription,
        ),
        'mass': FieldHint(
          label: 'Mass',
          description:
              'How heavy it is, in kg; 0 works it out from the collider.',
          scrub: const ScrubHint(step: 0.5, fractionDigits: 1, suffix: 'kg'),
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType == BodyType3D.dynamic,
        ),
        'layer': const FieldHint(
          label: 'Layer',
          description: Physics2DDefinitions.layerDescription,
        ),
        'isSensor': const FieldHint(
          label: 'Sensor',
          description: Physics2DDefinitions.sensorDescription,
        ),
        'friction': FieldHint(
          label: 'Friction',
          description: Physics2DDefinitions.frictionDescription,
          slider: true,
          scrub: _plain,
          visibleWhen: (c) => !(c as RigidBody3DComponent).isSensor,
        ),
        'restitution': FieldHint(
          label: 'Bounciness',
          description: Physics2DDefinitions.restitutionDescription,
          slider: true,
          scrub: _plain,
          visibleWhen: (c) => !(c as RigidBody3DComponent).isSensor,
        ),
        'gravityScale': FieldHint(
          label: 'Gravity scale',
          description: Physics2DDefinitions.gravityScaleDescription,
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '×'),
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType == BodyType3D.dynamic,
        ),
        'linearDamping': FieldHint(
          label: 'Linear damping',
          description: Physics2DDefinitions.linearDampingDescription,
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '/s'),
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType == BodyType3D.dynamic,
        ),
        'angularDamping': FieldHint(
          label: 'Angular damping',
          description: 'As linear damping, for its spin.',
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '/s'),
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType == BodyType3D.dynamic,
        ),
        'continuousCollision': FieldHint(
          label: 'Continuous',
          description: Physics2DDefinitions.continuousDescription,
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType == BodyType3D.dynamic,
        ),
        'canSleep': FieldHint(
          label: 'Can sleep',
          description: Physics2DDefinitions.canSleepDescription,
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType != BodyType3D.static,
        ),
        'lockRotation': FieldHint(
          label: 'Lock rotation',
          description: Physics2DDefinitions.lockRotationDescription,
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType != BodyType3D.static,
        ),
        'initialVelocity': FieldHint(
          label: 'Start velocity',
          description:
              'The velocity it starts with, in m/s: a thrown crate, a platform already on its way.',
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType != BodyType3D.static,
        ),
        'initialAngularVelocity': FieldHint(
          label: 'Start spin',
          description:
              'The spin it starts with, in radians per second about each axis.',
          visibleWhen: (c) =>
              (c as RigidBody3DComponent).bodyType != BodyType3D.static,
        ),
      },
    ),
    fields: [
      SchemaField(
        name: 'bodyType',
        kind: _bodyType,
        read: (c) => (c as RigidBody3DComponent).bodyType,
        write: (c, v) => (c as RigidBody3DComponent).bodyType = v as BodyType3D,
      ),
      _decimal<RigidBody3DComponent>(
        'mass',
        (c) => c.mass,
        (c, v) => c.mass = v,
        min: 0,
      ),
      SchemaField(
        name: 'layer',
        kind: FieldTypes.physicsLayer,
        read: (c) => (c as RigidBody3DComponent).layer,
        write: (c, v) => (c as RigidBody3DComponent).layer = (v as num).toInt(),
      ),
      _bool<RigidBody3DComponent>(
        'isSensor',
        (c) => c.isSensor,
        (c, v) => c.isSensor = v,
      ),
      _decimal<RigidBody3DComponent>(
        'friction',
        (c) => c.friction,
        (c, v) => c.friction = v,
        min: 0,
      ),
      _decimal<RigidBody3DComponent>(
        'restitution',
        (c) => c.restitution,
        (c, v) => c.restitution = v,
        min: 0,
        max: 1,
      ),
      _decimal<RigidBody3DComponent>(
        'gravityScale',
        (c) => c.gravityScale,
        (c, v) => c.gravityScale = v,
      ),
      _decimal<RigidBody3DComponent>(
        'linearDamping',
        (c) => c.linearDamping,
        (c, v) => c.linearDamping = v,
        min: 0,
      ),
      _decimal<RigidBody3DComponent>(
        'angularDamping',
        (c) => c.angularDamping,
        (c, v) => c.angularDamping = v,
        min: 0,
      ),
      _bool<RigidBody3DComponent>(
        'continuousCollision',
        (c) => c.continuousCollision,
        (c, v) => c.continuousCollision = v,
      ),
      _bool<RigidBody3DComponent>(
        'canSleep',
        (c) => c.canSleep,
        (c, v) => c.canSleep = v,
      ),
      _bool<RigidBody3DComponent>(
        'lockRotation',
        (c) => c.lockRotation,
        (c, v) => c.lockRotation = v,
      ),
      _vector<RigidBody3DComponent>(
        'initialVelocity',
        (c) => c.initialVelocity,
        (c, v) => c.initialVelocity = v,
      ),
      _vector<RigidBody3DComponent>(
        'initialAngularVelocity',
        (c) => c.initialAngularVelocity,
        (c, v) => c.initialAngularVelocity = v,
      ),
    ],
  );

  /// [Collider3DComponent].
  static ComponentSchema<Collider3DComponent> get collider {
    bool shapeIs(Component c, Set<ColliderShape3D> shapes) =>
        shapes.contains((c as Collider3DComponent).shape);
    return ComponentSchema<Collider3DComponent>(
      type: 'Collider3DComponent',
      id: 'collider_3d_1bf4c502',
      create: Collider3DComponent.new,
      extent: const _ColliderExtent(),
      hints: ComponentHints(
        dimensions: Dimensions.threeD,
        name: 'Collider 3D',
        group: _group,
        description:
            'The shape of the entity\'s body; without a Rigid Body 3D, a static one.',
        icon: Icons.crop_square,
        accentColor: const Color(0xFF66BB6A),
        fieldGroups: const {
          'Shape': ['shape', 'size', 'radius', 'height', 'model', 'meshName'],
          'Height field': ['heightFieldSize', 'cellSize', 'heights'],
          'Placement': ['offset', 'rotation', 'scale'],
        },
        fields: {
          'shape': const FieldHint(
            label: 'Shape',
            description:
                'Match shape: the shape the entity is drawn as (a Cube, Stairs, …), following it.',
          ),
          'size': FieldHint(
            label: 'Size',
            visibleWhen: (c) => shapeIs(c, {ColliderShape3D.box}),
          ),
          'radius': FieldHint(
            label: 'Radius',
            scrub: _metres,
            visibleWhen: (c) => shapeIs(c, {
              ColliderShape3D.sphere,
              ColliderShape3D.capsule,
              ColliderShape3D.cylinder,
            }),
          ),
          'height': FieldHint(
            label: 'Height',
            scrub: _metres,
            visibleWhen: (c) =>
                shapeIs(c, {ColliderShape3D.capsule, ColliderShape3D.cylinder}),
          ),
          'model': FieldHint(
            label: 'Model',
            fileExtensions: const ['glb', 'gltf'],
            visibleWhen: (c) =>
                shapeIs(c, {ColliderShape3D.convexHull, ColliderShape3D.mesh}),
          ),
          'meshName': FieldHint(
            label: 'Mesh',
            description: 'Empty uses every mesh of the model.',
            visibleWhen: (c) =>
                shapeIs(c, {ColliderShape3D.convexHull, ColliderShape3D.mesh}),
          ),
          'heightFieldSize': FieldHint(
            label: 'Samples per side',
            visibleWhen: (c) => shapeIs(c, {ColliderShape3D.heightField}),
          ),
          'cellSize': FieldHint(
            label: 'Cell size',
            scrub: _metres,
            visibleWhen: (c) => shapeIs(c, {ColliderShape3D.heightField}),
          ),
          'heights': FieldHint(
            label: 'Heights',
            visibleWhen: (c) => shapeIs(c, {ColliderShape3D.heightField}),
          ),
          'offset': const FieldHint(label: 'Offset'),
          'rotation': const FieldHint(
            label: 'Rotation',
            unit: AngleUnit.degrees,
          ),
          'scale': const FieldHint(label: 'Scale'),
        },
      ),
      fields: [
        SchemaField(
          name: 'shape',
          kind: _colliderShape,
          read: (c) => (c as Collider3DComponent).shape,
          write: (c, v) =>
              (c as Collider3DComponent).shape = v as ColliderShape3D,
        ),
        _vector<Collider3DComponent>(
          'size',
          (c) => c.size,
          (c, v) => c.size = v,
        ),
        _decimal<Collider3DComponent>(
          'radius',
          (c) => c.radius,
          (c, v) => c.radius = v,
          min: 0,
        ),
        _decimal<Collider3DComponent>(
          'height',
          (c) => c.height,
          (c, v) => c.height = v,
          min: 0,
        ),
        SchemaField(
          name: 'model',
          kind: FieldTypes.assetRef,
          read: (c) => (c as Collider3DComponent).model,
          write: (c, v) =>
              (c as Collider3DComponent).model = v as String? ?? '',
        ),
        SchemaField(
          name: 'meshName',
          kind: FieldTypes.text,
          read: (c) => (c as Collider3DComponent).meshName,
          write: (c, v) =>
              (c as Collider3DComponent).meshName = v as String? ?? '',
        ),
        SchemaField(
          name: 'heights',
          kind: FieldTypes.list,
          read: (c) => (c as Collider3DComponent).heights,
          write: (c, v) => (c as Collider3DComponent).heights = [
            if (v is List)
              for (final h in v) h is num ? h.toDouble() : 0.0,
          ],
        ),
        SchemaField(
          name: 'heightFieldSize',
          kind: FieldTypes.integer,
          read: (c) => (c as Collider3DComponent).heightFieldSize,
          write: (c, v) =>
              (c as Collider3DComponent).heightFieldSize = (v as num).toInt(),
          min: 0,
        ),
        _decimal<Collider3DComponent>(
          'cellSize',
          (c) => c.cellSize,
          (c, v) => c.cellSize = v,
          min: 0,
        ),
        _vector<Collider3DComponent>(
          'offset',
          (c) => c.offset,
          (c, v) => c.offset = v,
        ),
        SchemaField(
          name: 'rotation',
          kind: FieldTypes.euler,
          read: (c) => (c as Collider3DComponent).rotation,
          write: (c, v) => (c as Collider3DComponent).rotation = v as Vector3,
        ),
        _vector<Collider3DComponent>(
          'scale',
          (c) => c.scale,
          (c, v) => c.scale = v,
        ),
      ],
    );
  }

  /// [CharacterBody3DComponent].
  static ComponentSchema<CharacterBody3DComponent>
  get characterBody => ComponentSchema<CharacterBody3DComponent>(
    type: 'CharacterBody3DComponent',
    id: 'character_body_3d_f8ddd4a9',
    create: CharacterBody3DComponent.new,
    hints: ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Character Body 3D',
      group: _group,
      description:
          'A capsule gameplay moves: walks slopes, climbs steps, rides platforms. The entity\'s position is its feet.',
      icon: Icons.directions_walk,
      accentColor: const Color(0xFF29B6F6),
      fieldGroups: const {
        'Shape': ['radius', 'height', 'layer', 'detectable'],
        'Walking': ['maxSlopeAngle', 'stepHeight', 'stickToFloor'],
        'Forces': ['useGravity', 'gravityScale', 'mass', 'pushStrength'],
      },
      fields: {
        'radius': const FieldHint(label: 'Radius', scrub: _metres),
        'height': const FieldHint(label: 'Height', scrub: _metres),
        'layer': const FieldHint(
          label: 'Layer',
          description: Physics2DDefinitions.layerDescription,
        ),
        'detectable': const FieldHint(
          label: 'Detectable',
          description: Physics2DDefinitions.detectableDescription,
        ),
        'maxSlopeAngle': const FieldHint(
          label: 'Steepest slope',
          unit: AngleUnit.degrees,
          scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
        ),
        'stepHeight': const FieldHint(label: 'Step height', scrub: _metres),
        'stickToFloor': const FieldHint(
          label: 'Stick to floor',
          scrub: _metres,
        ),
        'useGravity': const FieldHint(label: 'Gravity and ground'),
        'gravityScale': FieldHint(
          label: 'Gravity scale',
          description: Physics2DDefinitions.gravityScaleDescription,
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '×'),
          visibleWhen: (c) => (c as CharacterBody3DComponent).useGravity,
        ),
        'mass': const FieldHint(
          label: 'Mass',
          scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'kg'),
        ),
        'pushStrength': const FieldHint(
          label: 'Push strength',
          scrub: ScrubHint(step: 5, fractionDigits: 0, suffix: 'N'),
        ),
      },
    ),
    fields: [
      _decimal<CharacterBody3DComponent>(
        'radius',
        (c) => c.radius,
        (c, v) => c.radius = v,
        min: 0.01,
      ),
      _decimal<CharacterBody3DComponent>(
        'height',
        (c) => c.height,
        (c, v) => c.height = v,
        min: 0.02,
      ),
      _decimal<CharacterBody3DComponent>(
        'maxSlopeAngle',
        (c) => c.maxSlopeAngle,
        (c, v) => c.maxSlopeAngle = v,
        min: 0,
      ),
      _decimal<CharacterBody3DComponent>(
        'stepHeight',
        (c) => c.stepHeight,
        (c, v) => c.stepHeight = v,
        min: 0,
      ),
      _decimal<CharacterBody3DComponent>(
        'stickToFloor',
        (c) => c.stickToFloor,
        (c, v) => c.stickToFloor = v,
        min: 0,
      ),
      _decimal<CharacterBody3DComponent>(
        'mass',
        (c) => c.mass,
        (c, v) => c.mass = v,
        min: 0,
      ),
      _decimal<CharacterBody3DComponent>(
        'pushStrength',
        (c) => c.pushStrength,
        (c, v) => c.pushStrength = v,
        min: 0,
      ),
      _decimal<CharacterBody3DComponent>(
        'gravityScale',
        (c) => c.gravityScale,
        (c, v) => c.gravityScale = v,
      ),
      _bool<CharacterBody3DComponent>(
        'useGravity',
        (c) => c.useGravity,
        (c, v) => c.useGravity = v,
      ),
      SchemaField(
        name: 'layer',
        kind: FieldTypes.physicsLayer,
        read: (c) => (c as CharacterBody3DComponent).layer,
        write: (c, v) =>
            (c as CharacterBody3DComponent).layer = (v as num).toInt(),
      ),
      _bool<CharacterBody3DComponent>(
        'detectable',
        (c) => c.detectable,
        (c, v) => c.detectable = v,
      ),
    ],
  );

  static const Map<String, FieldHint> _jointHints = {
    'connectedBody': FieldHint(
      label: 'Connected body',
      description:
          'The entity whose body it holds; none holds it to the world.',
    ),
    'anchor': FieldHint(label: 'Anchor'),
    'enabled': FieldHint(label: 'Enabled'),
  };

  static List<SchemaField> _jointFields<T extends Joint3DComponent>() => [
    SchemaField(
      name: 'connectedBody',
      kind: FieldTypes.target,
      read: (c) => (c as T).connectedBody,
      write: (c, v) =>
          (c as T).connectedBody = v as EntityTarget? ?? EntityTarget.none,
    ),
    _vector<T>('anchor', (c) => c.anchor, (c, v) => c.anchor = v),
    _bool<T>('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
  ];

  static ComponentHints _jointHintsFor(
    String name,
    String description,
    IconData icon, {
    Map<String, List<String>>? groups,
    Map<String, FieldHint> fields = const {},
  }) => ComponentHints(
    dimensions: Dimensions.threeD,
    name: name,
    group: _group,
    description: description,
    icon: icon,
    accentColor: const Color(0xFFFF7043),
    fieldGroups: groups,
    fields: {..._jointHints, ...fields},
  );

  /// [FixedJoint3DComponent].
  static ComponentSchema<FixedJoint3DComponent> get fixedJoint =>
      ComponentSchema<FixedJoint3DComponent>(
        type: 'FixedJoint3DComponent',
        id: 'fixed_joint_3d_6a931232',
        create: FixedJoint3DComponent.new,
        hints: _jointHintsFor(
          'Fixed Joint 3D',
          'Holds two bodies rigidly together.',
          Icons.lock_outline,
        ),
        fields: _jointFields<FixedJoint3DComponent>(),
      );

  /// [PointJoint3DComponent].
  static ComponentSchema<PointJoint3DComponent> get pointJoint =>
      ComponentSchema<PointJoint3DComponent>(
        type: 'PointJoint3DComponent',
        id: 'point_joint_3d_40e90e6c',
        create: PointJoint3DComponent.new,
        hints: _jointHintsFor(
          'Point Joint 3D',
          'Holds two bodies at one point, free to turn about it.',
          Icons.all_out,
        ),
        fields: _jointFields<PointJoint3DComponent>(),
      );

  static Map<String, FieldHint> _motorHints(
    String unitSuffix,
    String forceLabel,
  ) => {
    'motor': const FieldHint(label: 'Motor'),
    'motorTarget': FieldHint(
      label: 'Target',
      description: 'A speed or a $unitSuffix, as the motor says.',
      visibleWhen: (c) => _motorOf(c) != MotorState3D.off,
    ),
    'motorMax': FieldHint(
      label: forceLabel,
      description: '0 for no limit.',
      visibleWhen: (c) => _motorOf(c) != MotorState3D.off,
    ),
  };

  static MotorState3D _motorOf(Component c) => switch (c) {
    HingeJoint3DComponent h => h.motor,
    SliderJoint3DComponent s => s.motor,
    _ => MotorState3D.off,
  };

  /// [HingeJoint3DComponent].
  static ComponentSchema<HingeJoint3DComponent> get hingeJoint =>
      ComponentSchema<HingeJoint3DComponent>(
        type: 'HingeJoint3DComponent',
        id: 'hinge_joint_3d_d261402b',
        create: HingeJoint3DComponent.new,
        hints: _jointHintsFor(
          'Hinge Joint 3D',
          'Lets two bodies turn about one axis: a door, a wheel.',
          Icons.door_front_door_outlined,
          groups: const {
            'Joint': ['connectedBody', 'anchor', 'axis', 'enabled'],
            'Limits': ['useLimits', 'minAngle', 'maxAngle', 'friction'],
            'Motor': ['motor', 'motorTarget', 'motorMaxTorque'],
          },
          fields: {
            'axis': const FieldHint(label: 'Axis'),
            'useLimits': const FieldHint(label: 'Limited'),
            'minAngle': FieldHint(
              label: 'Min angle',
              unit: AngleUnit.degrees,
              visibleWhen: (c) => (c as HingeJoint3DComponent).useLimits,
            ),
            'maxAngle': FieldHint(
              label: 'Max angle',
              unit: AngleUnit.degrees,
              visibleWhen: (c) => (c as HingeJoint3DComponent).useLimits,
            ),
            'friction': const FieldHint(label: 'Friction torque'),
            ..._motorHints('angle', 'Max torque').map(
              (k, v) => MapEntry(k == 'motorMax' ? 'motorMaxTorque' : k, v),
            ),
          },
        ),
        fields: [
          ..._jointFields<HingeJoint3DComponent>(),
          _vector<HingeJoint3DComponent>(
            'axis',
            (c) => c.axis,
            (c, v) => c.axis = v,
          ),
          _bool<HingeJoint3DComponent>(
            'useLimits',
            (c) => c.useLimits,
            (c, v) => c.useLimits = v,
          ),
          _decimal<HingeJoint3DComponent>(
            'minAngle',
            (c) => c.minAngle,
            (c, v) => c.minAngle = v,
          ),
          _decimal<HingeJoint3DComponent>(
            'maxAngle',
            (c) => c.maxAngle,
            (c, v) => c.maxAngle = v,
          ),
          _decimal<HingeJoint3DComponent>(
            'friction',
            (c) => c.friction,
            (c, v) => c.friction = v,
            min: 0,
          ),
          SchemaField(
            name: 'motor',
            kind: _motor,
            read: (c) => (c as HingeJoint3DComponent).motor,
            write: (c, v) =>
                (c as HingeJoint3DComponent).motor = v as MotorState3D,
          ),
          _decimal<HingeJoint3DComponent>(
            'motorTarget',
            (c) => c.motorTarget,
            (c, v) => c.motorTarget = v,
          ),
          _decimal<HingeJoint3DComponent>(
            'motorMaxTorque',
            (c) => c.motorMaxTorque,
            (c, v) => c.motorMaxTorque = v,
            min: 0,
          ),
        ],
      );

  /// [SliderJoint3DComponent].
  static ComponentSchema<SliderJoint3DComponent> get sliderJoint =>
      ComponentSchema<SliderJoint3DComponent>(
        type: 'SliderJoint3DComponent',
        id: 'slider_joint_3d_4fe767d0',
        create: SliderJoint3DComponent.new,
        hints: _jointHintsFor(
          'Slider Joint 3D',
          'Lets two bodies slide along one axis: a drawer, a lift.',
          Icons.swap_horiz,
          groups: const {
            'Joint': ['connectedBody', 'anchor', 'axis', 'enabled'],
            'Limits': ['useLimits', 'minPosition', 'maxPosition', 'friction'],
            'Motor': ['motor', 'motorTarget', 'motorMaxForce'],
          },
          fields: {
            'axis': const FieldHint(label: 'Axis'),
            'useLimits': const FieldHint(label: 'Limited'),
            'minPosition': FieldHint(
              label: 'Min position',
              scrub: _metres,
              visibleWhen: (c) => (c as SliderJoint3DComponent).useLimits,
            ),
            'maxPosition': FieldHint(
              label: 'Max position',
              scrub: _metres,
              visibleWhen: (c) => (c as SliderJoint3DComponent).useLimits,
            ),
            'friction': const FieldHint(label: 'Friction force'),
            ..._motorHints(
              'position',
              'Max force',
            ).map((k, v) => MapEntry(k == 'motorMax' ? 'motorMaxForce' : k, v)),
          },
        ),
        fields: [
          ..._jointFields<SliderJoint3DComponent>(),
          _vector<SliderJoint3DComponent>(
            'axis',
            (c) => c.axis,
            (c, v) => c.axis = v,
          ),
          _bool<SliderJoint3DComponent>(
            'useLimits',
            (c) => c.useLimits,
            (c, v) => c.useLimits = v,
          ),
          _decimal<SliderJoint3DComponent>(
            'minPosition',
            (c) => c.minPosition,
            (c, v) => c.minPosition = v,
          ),
          _decimal<SliderJoint3DComponent>(
            'maxPosition',
            (c) => c.maxPosition,
            (c, v) => c.maxPosition = v,
          ),
          _decimal<SliderJoint3DComponent>(
            'friction',
            (c) => c.friction,
            (c, v) => c.friction = v,
            min: 0,
          ),
          SchemaField(
            name: 'motor',
            kind: _motor,
            read: (c) => (c as SliderJoint3DComponent).motor,
            write: (c, v) =>
                (c as SliderJoint3DComponent).motor = v as MotorState3D,
          ),
          _decimal<SliderJoint3DComponent>(
            'motorTarget',
            (c) => c.motorTarget,
            (c, v) => c.motorTarget = v,
          ),
          _decimal<SliderJoint3DComponent>(
            'motorMaxForce',
            (c) => c.motorMaxForce,
            (c, v) => c.motorMaxForce = v,
            min: 0,
          ),
        ],
      );

  /// [DistanceJoint3DComponent].
  static ComponentSchema<DistanceJoint3DComponent> get distanceJoint =>
      ComponentSchema<DistanceJoint3DComponent>(
        type: 'DistanceJoint3DComponent',
        id: 'distance_joint_3d_4db642db',
        create: DistanceJoint3DComponent.new,
        hints: _jointHintsFor(
          'Distance Joint 3D',
          'Keeps two anchors within a distance range: a rope, a spring.',
          Icons.straighten,
          groups: const {
            'Joint': ['connectedBody', 'anchor', 'connectedAnchor', 'enabled'],
            'Distance': ['minDistance', 'maxDistance'],
            'Spring': ['springFrequency', 'springDamping'],
          },
          fields: const {
            'connectedAnchor': FieldHint(label: 'Connected anchor'),
            'minDistance': FieldHint(
              label: 'Min distance',
              description: 'Below 0: as far apart as they start.',
            ),
            'maxDistance': FieldHint(
              label: 'Max distance',
              description: 'Below 0: as far apart as they start.',
            ),
            'springFrequency': FieldHint(
              label: 'Frequency',
              description: 'Hz; 0 is rigid.',
            ),
            'springDamping': FieldHint(
              label: 'Damping',
              description: '1 is critical.',
            ),
          },
        ),
        fields: [
          ..._jointFields<DistanceJoint3DComponent>(),
          _vector<DistanceJoint3DComponent>(
            'connectedAnchor',
            (c) => c.connectedAnchor,
            (c, v) => c.connectedAnchor = v,
          ),
          _decimal<DistanceJoint3DComponent>(
            'minDistance',
            (c) => c.minDistance,
            (c, v) => c.minDistance = v,
          ),
          _decimal<DistanceJoint3DComponent>(
            'maxDistance',
            (c) => c.maxDistance,
            (c, v) => c.maxDistance = v,
          ),
          _decimal<DistanceJoint3DComponent>(
            'springFrequency',
            (c) => c.springFrequency,
            (c, v) => c.springFrequency = v,
            min: 0,
          ),
          _decimal<DistanceJoint3DComponent>(
            'springDamping',
            (c) => c.springDamping,
            (c, v) => c.springDamping = v,
            min: 0,
          ),
        ],
      );

  /// [SixDofJoint3DComponent].
  static ComponentSchema<SixDofJoint3DComponent> get sixDofJoint {
    SchemaField mode(
      String name,
      SixDofAxisMode3D Function(SixDofJoint3DComponent) read,
      void Function(SixDofJoint3DComponent, SixDofAxisMode3D) write,
    ) => SchemaField(
      name: name,
      kind: _axisMode,
      read: (c) => read(c as SixDofJoint3DComponent),
      write: (c, v) =>
          write(c as SixDofJoint3DComponent, v as SixDofAxisMode3D),
    );
    return ComponentSchema<SixDofJoint3DComponent>(
      type: 'SixDofJoint3DComponent',
      id: 'six_dof_joint_3d_7cb33ceb',
      create: SixDofJoint3DComponent.new,
      hints: _jointHintsFor(
        'Six DOF Joint 3D',
        'Each of the six axes free, limited or fixed.',
        Icons.open_with,
        groups: const {
          'Joint': ['connectedBody', 'anchor', 'axis', 'normal', 'enabled'],
          'Translation': [
            'translationX',
            'translationY',
            'translationZ',
            'translationMin',
            'translationMax',
          ],
          'Rotation': [
            'rotationX',
            'rotationY',
            'rotationZ',
            'rotationMin',
            'rotationMax',
          ],
        },
        fields: const {
          'axis': FieldHint(label: 'X axis'),
          'normal': FieldHint(label: 'Y axis'),
          'translationMin': FieldHint(label: 'Min'),
          'translationMax': FieldHint(label: 'Max'),
          'rotationMin': FieldHint(label: 'Min', unit: AngleUnit.degrees),
          'rotationMax': FieldHint(label: 'Max', unit: AngleUnit.degrees),
        },
      ),
      fields: [
        ..._jointFields<SixDofJoint3DComponent>(),
        _vector<SixDofJoint3DComponent>(
          'axis',
          (c) => c.axis,
          (c, v) => c.axis = v,
        ),
        _vector<SixDofJoint3DComponent>(
          'normal',
          (c) => c.normal,
          (c, v) => c.normal = v,
        ),
        mode(
          'translationX',
          (c) => c.translationX,
          (c, v) => c.translationX = v,
        ),
        mode(
          'translationY',
          (c) => c.translationY,
          (c, v) => c.translationY = v,
        ),
        mode(
          'translationZ',
          (c) => c.translationZ,
          (c, v) => c.translationZ = v,
        ),
        mode('rotationX', (c) => c.rotationX, (c, v) => c.rotationX = v),
        mode('rotationY', (c) => c.rotationY, (c, v) => c.rotationY = v),
        mode('rotationZ', (c) => c.rotationZ, (c, v) => c.rotationZ = v),
        _vector<SixDofJoint3DComponent>(
          'translationMin',
          (c) => c.translationMin,
          (c, v) => c.translationMin = v,
        ),
        _vector<SixDofJoint3DComponent>(
          'translationMax',
          (c) => c.translationMax,
          (c, v) => c.translationMax = v,
        ),
        _vector<SixDofJoint3DComponent>(
          'rotationMin',
          (c) => c.rotationMin,
          (c, v) => c.rotationMin = v,
        ),
        _vector<SixDofJoint3DComponent>(
          'rotationMax',
          (c) => c.rotationMax,
          (c, v) => c.rotationMax = v,
        ),
      ],
    );
  }

  /// Every 3-D physics component.
  static List<ComponentSchema> get all => [
    rigidBody,
    collider,
    characterBody,
    fixedJoint,
    pointJoint,
    hingeJoint,
    sliderJoint,
    distanceJoint,
    sixDofJoint,
    cameraCollision,
  ];

  /// [CameraCollision3DComponent].
  static ComponentSchema<CameraCollision3DComponent>
  get cameraCollision => ComponentSchema<CameraCollision3DComponent>(
    type: 'CameraCollision3DComponent',
    id: 'camera_collision_3d_5d27c0e1',
    create: CameraCollision3DComponent.new,
    hints: ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Camera Collision 3D',
      group: _group,
      description:
          'Keeps a virtual camera out of walls: pulled in towards its target when something is in the way, eased back out once clear.',
      icon: Icons.videocam_off_outlined,
      accentColor: const Color(0xFF40E0D0),
      fields: {
        'radius': const FieldHint(
          label: 'Radius',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm'),
        ),
        'minDistance': const FieldHint(
          label: 'Closest',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm'),
        ),
        'recover': const FieldHint(
          label: 'Ease out',
          description: 'Seconds to move back out once the way is clear.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 's'),
        ),
        'layerMask': const FieldHint(label: 'Blocked by'),
        'offset': const FieldHint(
          label: 'Looks from',
          description: 'From the target, without an orbit pivot (-Y is up).',
        ),
      },
    ),
    fields: [
      _decimal<CameraCollision3DComponent>(
        'radius',
        (c) => c.radius,
        (c, v) => c.radius = v,
        min: 0,
      ),
      _decimal<CameraCollision3DComponent>(
        'minDistance',
        (c) => c.minDistance,
        (c, v) => c.minDistance = v,
        min: 0,
      ),
      _decimal<CameraCollision3DComponent>(
        'recover',
        (c) => c.recover,
        (c, v) => c.recover = v,
        min: 0,
      ),
      SchemaField(
        name: 'layerMask',
        kind: FieldTypes.physicsLayerMask,
        read: (c) => (c as CameraCollision3DComponent).layerMask,
        write: (c, v) =>
            (c as CameraCollision3DComponent).layerMask = (v as num).toInt(),
      ),
      _vector<CameraCollision3DComponent>(
        'offset',
        (c) => c.offset,
        (c, v) => c.offset = Vector3.copy(v),
      ),
    ],
  );

  static SchemaField _decimal<T extends Component>(
    String name,
    double Function(T c) read,
    void Function(T c, double v) write, {
    double? min,
    double? max,
  }) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toDouble()),
    min: min,
    max: max,
  );

  static SchemaField _bool<T extends Component>(
    String name,
    bool Function(T c) read,
    void Function(T c, bool v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as bool),
  );

  static SchemaField _vector<T extends Component>(
    String name,
    Vector3 Function(T c) read,
    void Function(T c, Vector3 v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.vector3,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as Vector3),
  );
}

/// A collider's size is its shape's, scaled, about its offset.
final class _ColliderExtent extends ComponentExtent {
  const _ColliderExtent();

  // Matching its entity's shape, it adds nothing to the shape's own extent.
  @override
  Size? sizeOf(Component component) {
    final c = component as Collider3DComponent;
    if (c.shape == ColliderShape3D.matchShape) return null;
    final s = c.naturalSize;
    return Size(s.x * c.scale.x.abs(), s.y * c.scale.y.abs());
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final c = component as Collider3DComponent;
    if (c.shape == ColliderShape3D.matchShape) return false;
    final s = c.naturalSize;
    final hx = s.x * c.scale.x.abs() / 2,
        hy = s.y * c.scale.y.abs() / 2,
        hz = s.z * c.scale.z.abs() / 2;
    final o = c.offset;
    out.setValues(o.x - hx, o.y - hy, o.z - hz, o.x + hx, o.y + hy, o.z + hz);
    return true;
  }
}
