/// How the 2-D physics components are saved and shown in an editor — laid
/// out as the 3-D ones are, field for field.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import '../foundation/dimensions.dart';
import 'joints_2d.dart';
import 'physics_components_2d.dart';
import '../ecs/ecs.dart';
import 'collider_geometry.dart';
import '../ecs/serialization/component_definition.dart';
import '../ecs/serialization/component_presentation.dart';
import '../ecs/serialization/field_type.dart';

/// The definitions of [RigidBody2DComponent], [Collider2DComponent], [CharacterBody2DComponent] and the
/// 2-D joints. Each is `Dimensions.twoD`, in the `Physics` group.
abstract final class PhysicsDefinitions2D {
  static const String _group = 'Physics';
  static const Color _accent = Color(0xFFFF7043);
  static const _plain = ScrubHint(step: 0.05, fractionDigits: 2);

  static const _bodyType = EnumFieldType(
    BodyType.values,
    fallback: BodyType.dynamic,
    id: 'enum.bodyType',
  );

  /// [RigidBody2DComponent], saved as `RigidBody2DComponent`.
  static ComponentDefinition<RigidBody2DComponent>
  get rigidBody => ComponentDefinition<RigidBody2DComponent>(
    type: 'RigidBody2DComponent',
    create: RigidBody2DComponent.new,
    hints: ComponentHints(
      dimensions: Dimensions.twoD,
      name: 'Rigid Body 2D',
      group: _group,
      description:
          'Simulates the entity: gravity, forces and collisions. Its shape is a Collider 2D.',
      icon: Icons.sports_basketball,
      accentColor: _accent,
      fieldGroups: const {
        'Body': ['bodyType', 'mass', 'layer', 'collidesWith', 'isSensor'],
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
        'Advanced': ['groupIndex'],
      },
      foldedGroups: const {'Advanced'},
      fields: {
        'bodyType': const FieldHint(
          label: 'Body type',
          description: bodyTypeDescription,
        ),
        'mass': FieldHint(
          label: 'Mass',
          description:
              'How heavy it is, in kg: how hard it pushes, and how hard it is '
              'to push. 0 works it out from the collider.',
          scrub: const ScrubHint(step: 0.1, fractionDigits: 2, suffix: 'kg'),
          visibleWhen: (c) => (c as RigidBody2DComponent).isDynamic,
        ),
        'layer': const FieldHint(label: 'Layer', description: layerDescription),
        'collidesWith': const FieldHint(
          label: 'Collides with',
          description: collidesWithDescription,
        ),
        'isSensor': const FieldHint(
          label: 'Sensor',
          description: sensorDescription,
        ),
        'friction': FieldHint(
          label: 'Friction',
          description: frictionDescription,
          slider: true,
          scrub: _plain,
          visibleWhen: (c) => !(c as RigidBody2DComponent).isSensor,
        ),
        'restitution': FieldHint(
          label: 'Bounciness',
          description: restitutionDescription,
          slider: true,
          scrub: _plain,
          visibleWhen: (c) => !(c as RigidBody2DComponent).isSensor,
        ),
        'gravityScale': FieldHint(
          label: 'Gravity scale',
          description: gravityScaleDescription,
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '×'),
          visibleWhen: (c) => (c as RigidBody2DComponent).isDynamic,
        ),
        'linearDamping': FieldHint(
          label: 'Linear damping',
          description: linearDampingDescription,
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '/s'),
          visibleWhen: (c) => (c as RigidBody2DComponent).isDynamic,
        ),
        'angularDamping': FieldHint(
          label: 'Angular damping',
          description: 'As linear damping, for its spin.',
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '/s'),
          visibleWhen: (c) => (c as RigidBody2DComponent).isDynamic,
        ),
        'continuousCollision': FieldHint(
          label: 'Continuous',
          description: continuousDescription,
          visibleWhen: (c) => (c as RigidBody2DComponent).isDynamic,
        ),
        'canSleep': FieldHint(
          label: 'Can sleep',
          description: canSleepDescription,
          visibleWhen: (c) => !(c as RigidBody2DComponent).isStatic,
        ),
        'lockRotation': FieldHint(
          label: 'Lock rotation',
          description: lockRotationDescription,
          visibleWhen: (c) => !(c as RigidBody2DComponent).isStatic,
        ),
        'initialVelocity': FieldHint(
          label: 'Start velocity',
          description:
              'The velocity it starts with: a thrown crate, a platform already on its way.',
          visibleWhen: (c) => !(c as RigidBody2DComponent).isStatic,
        ),
        'initialAngularVelocity': FieldHint(
          label: 'Start spin',
          description: 'The spin it starts with, in degrees per second.',
          unit: AngleUnit.degrees,
          scrub: const ScrubHint(step: 5, fractionDigits: 0, suffix: '°/s'),
          visibleWhen: (c) => !(c as RigidBody2DComponent).isStatic,
        ),
        'groupIndex': const FieldHint(
          label: 'Group',
          description:
              'Bodies in the same positive group always collide; in the same '
              'negative group never do. 0 leaves it to the layers.',
          scrub: ScrubHint(integer: true),
        ),
      },
    ),
    fields: [
      SchemaField(
        name: 'bodyType',
        kind: _bodyType,
        read: (c) => (c as RigidBody2DComponent).bodyType,
        write: (c, v) => (c as RigidBody2DComponent).bodyType = v as BodyType,
      ),
      _d<RigidBody2DComponent>(
        'mass',
        (c) => c.mass,
        (c, v) => c.mass = v,
        min: 0,
      ),
      SchemaField(
        name: 'layer',
        kind: FieldTypes.physicsLayer,
        read: (c) => (c as RigidBody2DComponent).layer,
        write: (c, v) =>
            (c as RigidBody2DComponent).layer = (v as num).toInt().clamp(0, 15),
      ),
      SchemaField(
        name: 'collidesWith',
        kind: FieldTypes.physicsLayerMask,
        read: (c) => (c as RigidBody2DComponent).collidesWith,
        write: (c, v) => (c as RigidBody2DComponent).collidesWith = v == null
            ? null
            : (v as num).toInt() & 0xFFFF,
      ),
      _b<RigidBody2DComponent>(
        'isSensor',
        (c) => c.isSensor,
        (c, v) => c.isSensor = v,
      ),
      _d<RigidBody2DComponent>(
        'friction',
        (c) => c.friction,
        (c, v) => c.friction = v,
        min: 0,
        max: 1,
      ),
      _d<RigidBody2DComponent>(
        'restitution',
        (c) => c.restitution,
        (c, v) => c.restitution = v,
        min: 0,
        max: 1,
      ),
      _d<RigidBody2DComponent>(
        'gravityScale',
        (c) => c.gravityScale,
        (c, v) => c.gravityScale = v,
      ),
      _d<RigidBody2DComponent>(
        'linearDamping',
        (c) => c.linearDamping,
        (c, v) => c.linearDamping = v,
        min: 0,
      ),
      _d<RigidBody2DComponent>(
        'angularDamping',
        (c) => c.angularDamping,
        (c, v) => c.angularDamping = v,
        min: 0,
      ),
      _b<RigidBody2DComponent>(
        'continuousCollision',
        (c) => c.continuousCollision,
        (c, v) => c.continuousCollision = v,
      ),
      _b<RigidBody2DComponent>(
        'canSleep',
        (c) => c.canSleep,
        (c, v) => c.canSleep = v,
      ),
      _b<RigidBody2DComponent>(
        'lockRotation',
        (c) => c.lockRotation,
        (c, v) => c.lockRotation = v,
      ),
      _o<RigidBody2DComponent>(
        'initialVelocity',
        (c) => c.initialVelocity,
        (c, v) => c.initialVelocity = v,
      ),
      _d<RigidBody2DComponent>(
        'initialAngularVelocity',
        (c) => c.initialAngularVelocity,
        (c, v) => c.initialAngularVelocity = v,
      ),
      SchemaField(
        name: 'groupIndex',
        kind: FieldTypes.integer,
        read: (c) => (c as RigidBody2DComponent).groupIndex,
        write: (c, v) =>
            (c as RigidBody2DComponent).groupIndex = (v as num).toInt(),
      ),
    ],
  );

  /// [Collider2DComponent], saved as `Collider2DComponent`.
  static ComponentDefinition<Collider2DComponent> get collider {
    bool shapeIs(Component c, Set<ColliderShape2D> shapes) =>
        shapes.contains((c as Collider2DComponent).shape);
    return ComponentDefinition<Collider2DComponent>(
      type: 'Collider2DComponent',
      create: Collider2DComponent.new,
      extent: const _Collider2DExtent(),
      hints: ComponentHints(
        dimensions: Dimensions.twoD,
        name: 'Collider 2D',
        group: _group,
        description:
            "The shape of the entity's body; without a Rigid Body 2D, a static one.",
        icon: Icons.crop_square,
        accentColor: const Color(0xFF66BB6A),
        fieldGroups: const {
          'Shape': [
            'shape',
            'size',
            'radius',
            'height',
            'points',
            'cornerRadius',
            'thickness',
            'loop',
          ],
          'Placement': ['offset', 'rotation', 'scale'],
          'One-way': ['oneWay', 'oneWayDirection'],
          'Debug': ['showDebugOutline'],
        },
        foldedGroups: const {'Debug'},
        fields: {
          'shape': const FieldHint(
            label: 'Shape',
            description: matchShapeDescription,
          ),
          'size': FieldHint(
            label: 'Size',
            visibleWhen: (c) => shapeIs(c, {ColliderShape2D.box}),
          ),
          'radius': FieldHint(
            label: 'Radius',
            scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
            visibleWhen: (c) =>
                shapeIs(c, {ColliderShape2D.circle, ColliderShape2D.capsule}),
          ),
          'height': FieldHint(
            label: 'Height',
            description: 'Its whole height, ends included.',
            scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
            visibleWhen: (c) => shapeIs(c, {ColliderShape2D.capsule}),
          ),
          'points': FieldHint(
            label: 'Points',
            description:
                'In order round it (a polygon has at most 8); a segment takes the first two.',
            visibleWhen: (c) => shapeIs(c, {
              ColliderShape2D.polygon,
              ColliderShape2D.segment,
              ColliderShape2D.chain,
            }),
          ),
          'cornerRadius': FieldHint(
            label: 'Corner radius',
            description: 'Rounds the corners: inside a box, outside a polygon.',
            scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
            visibleWhen: (c) =>
                shapeIs(c, {ColliderShape2D.box, ColliderShape2D.polygon}),
          ),
          'thickness': FieldHint(
            label: 'Thickness',
            scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
            visibleWhen: (c) =>
                shapeIs(c, {ColliderShape2D.segment, ColliderShape2D.chain}),
          ),
          'loop': FieldHint(
            label: 'Closed',
            description: 'Joins its last point to its first.',
            visibleWhen: (c) => shapeIs(c, {ColliderShape2D.chain}),
          ),
          'offset': const FieldHint(
            label: 'Offset',
            description:
                "Moves the collider off the entity's origin — a feet box under a tall sprite. Scaled and turned with the entity.",
          ),
          'rotation': const FieldHint(
            label: 'Rotation',
            unit: AngleUnit.degrees,
            scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
          ),
          'scale': const FieldHint(
            label: 'Scale',
            description: "The shape's own scale, on top of the entity's.",
          ),
          'oneWay': const FieldHint(
            label: 'One-way',
            description:
                'Solid from one side only: a platform jumped up through from below.',
          ),
          'oneWayDirection': FieldHint(
            label: 'Solid from',
            description: 'The side a one-way collider stops things from.',
            visibleWhen: (c) => (c as Collider2DComponent).oneWay,
          ),
          'showDebugOutline': const FieldHint(
            label: 'Show outline',
            description:
                'Draws the collider in the editor while the scene is edited '
                'and gizmos are shown.',
          ),
        },
      ),
      fields: [
        SchemaField(
          name: 'shape',
          kind: const EnumFieldType(
            ColliderShape2D.values,
            fallback: ColliderShape2D.box,
            id: 'enum.colliderShape2D',
          ),
          read: (c) => (c as Collider2DComponent).shape,
          write: (c, v) =>
              (c as Collider2DComponent).shape = v as ColliderShape2D,
        ),
        SchemaField(
          name: 'size',
          kind: FieldTypes.vector2,
          read: (c) => (c as Collider2DComponent).size,
          write: (c, v) {
            if (v is Vector2) {
              (c as Collider2DComponent).size = Vector2(v.x.abs(), v.y.abs());
            }
          },
        ),
        _d<Collider2DComponent>(
          'radius',
          (c) => c.radius,
          (c, v) => c.radius = v,
          min: 0.01,
        ),
        _d<Collider2DComponent>(
          'height',
          (c) => c.height,
          (c, v) => c.height = v,
          min: 0.01,
        ),
        SchemaField(
          name: 'points',
          kind: FieldTypes.offsetList,
          read: (c) => (c as Collider2DComponent).points,
          write: (c, v) => (c as Collider2DComponent).points = (v as List)
              .cast<Offset>()
              .toList(),
        ),
        _d<Collider2DComponent>(
          'cornerRadius',
          (c) => c.cornerRadius,
          (c, v) => c.cornerRadius = v,
          min: 0,
        ),
        _d<Collider2DComponent>(
          'thickness',
          (c) => c.thickness,
          (c, v) => c.thickness = v,
          min: 0,
        ),
        _b<Collider2DComponent>('loop', (c) => c.loop, (c, v) => c.loop = v),
        _o<Collider2DComponent>(
          'offset',
          (c) => c.offset,
          (c, v) => c.offset = v,
        ),
        _d<Collider2DComponent>(
          'rotation',
          (c) => c.rotation,
          (c, v) => c.rotation = v,
        ),
        SchemaField(
          name: 'scale',
          kind: FieldTypes.vector2,
          read: (c) => (c as Collider2DComponent).scale,
          write: (c, v) {
            if (v is Vector2) {
              (c as Collider2DComponent).scale = Vector2.copy(v);
            }
          },
        ),
        _b<Collider2DComponent>(
          'oneWay',
          (c) => c.oneWay,
          (c, v) => c.oneWay = v,
        ),
        SchemaField(
          name: 'oneWayDirection',
          kind: const EnumFieldType(
            OneWayDirection.values,
            fallback: OneWayDirection.fromAbove,
            id: 'enum.oneWayDirection',
          ),
          read: (c) => (c as Collider2DComponent).oneWayDirection,
          write: (c, v) =>
              (c as Collider2DComponent).oneWayDirection = v as OneWayDirection,
        ),
        _b<Collider2DComponent>(
          'showDebugOutline',
          (c) => c.showDebugOutline,
          (c, v) => c.showDebugOutline = v,
        ),
      ],
    );
  }

  /// [CharacterBody2DComponent], saved as `CharacterBody2DComponent` — laid out as
  /// the 3-D `CharacterBody3DComponent`.
  static ComponentDefinition<CharacterBody2DComponent> get characterBody {
    bool isBox(Component c) =>
        (c as CharacterBody2DComponent).shape == CharacterShape2D.box;
    return ComponentDefinition<CharacterBody2DComponent>(
      type: 'CharacterBody2DComponent',
      create: CharacterBody2DComponent.new,
      extent: const _CharacterBody2DExtent(),
      hints: ComponentHints(
        dimensions: Dimensions.twoD,
        name: 'Character Body 2D',
        group: _group,
        description: characterDescription,
        icon: Icons.directions_walk,
        accentColor: const Color(0xFF29B6F6),
        fieldGroups: const {
          'Shape': [
            'shape',
            'radius',
            'width',
            'height',
            'offset',
            'layer',
            'collidesWith',
            'detectable',
          ],
          'Walking': ['maxSlopeAngle', 'stepHeight', 'stickToFloor'],
          'Forces': ['useGravity', 'gravityScale', 'mass', 'pushStrength'],
        },
        fields: {
          'shape': const FieldHint(
            label: 'Shape',
            description:
                'A capsule slides over bumps and off ledges; a box stands on a ledge\'s corner.',
          ),
          'radius': FieldHint(
            label: 'Radius',
            scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
            visibleWhen: (c) => !isBox(c),
          ),
          'width': FieldHint(
            label: 'Width',
            scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
            visibleWhen: isBox,
          ),
          'height': const FieldHint(
            label: 'Height',
            scrub: ScrubHint(step: 0.5, fractionDigits: 1),
          ),
          'offset': const FieldHint(
            label: 'Offset',
            description: "Moves its shape off the entity's origin.",
          ),
          'layer': const FieldHint(
            label: 'Layer',
            description: layerDescription,
          ),
          'collidesWith': const FieldHint(
            label: 'Collides with',
            description: collidesWithDescription,
          ),
          'detectable': const FieldHint(
            label: 'Detectable',
            description: detectableDescription,
          ),
          'maxSlopeAngle': const FieldHint(
            label: 'Steepest slope',
            unit: AngleUnit.degrees,
            scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
          ),
          'stepHeight': const FieldHint(
            label: 'Step height',
            scrub: ScrubHint(step: 0.5, fractionDigits: 1),
          ),
          'stickToFloor': const FieldHint(
            label: 'Stick to floor',
            scrub: ScrubHint(step: 0.5, fractionDigits: 1),
          ),
          'useGravity': const FieldHint(label: 'Gravity and ground'),
          'gravityScale': FieldHint(
            label: 'Gravity scale',
            description: gravityScaleDescription,
            scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: '×'),
            visibleWhen: (c) => (c as CharacterBody2DComponent).useGravity,
          ),
          'mass': const FieldHint(
            label: 'Mass',
            scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: 'kg'),
          ),
          'pushStrength': const FieldHint(
            label: 'Push strength',
            scrub: ScrubHint(step: 50, fractionDigits: 0),
          ),
        },
      ),
      fields: [
        SchemaField(
          name: 'shape',
          kind: const EnumFieldType(
            CharacterShape2D.values,
            fallback: CharacterShape2D.capsule,
            id: 'enum.characterShape2D',
          ),
          read: (c) => (c as CharacterBody2DComponent).shape,
          write: (c, v) =>
              (c as CharacterBody2DComponent).shape = v as CharacterShape2D,
        ),
        _d<CharacterBody2DComponent>(
          'radius',
          (c) => c.radius,
          (c, v) => c.radius = v,
          min: 1.01,
        ),
        _d<CharacterBody2DComponent>(
          'width',
          (c) => c.width,
          (c, v) => c.width = v,
          min: 2.5,
        ),
        _d<CharacterBody2DComponent>(
          'height',
          (c) => c.height,
          (c, v) => c.height = v,
          min: 2.5,
        ),
        _o<CharacterBody2DComponent>(
          'offset',
          (c) => c.offset,
          (c, v) => c.offset = v,
        ),
        SchemaField(
          name: 'layer',
          kind: FieldTypes.physicsLayer,
          read: (c) => (c as CharacterBody2DComponent).layer,
          write: (c, v) => (c as CharacterBody2DComponent).layer = (v as num)
              .toInt()
              .clamp(0, 15),
        ),
        SchemaField(
          name: 'collidesWith',
          kind: FieldTypes.physicsLayerMask,
          read: (c) => (c as CharacterBody2DComponent).collidesWith,
          write: (c, v) => (c as CharacterBody2DComponent).collidesWith =
              v == null ? null : (v as num).toInt() & 0xFFFF,
        ),
        _b<CharacterBody2DComponent>(
          'detectable',
          (c) => c.detectable,
          (c, v) => c.detectable = v,
        ),
        _d<CharacterBody2DComponent>(
          'maxSlopeAngle',
          (c) => c.maxSlopeAngle,
          (c, v) => c.maxSlopeAngle = v,
          min: 0,
        ),
        _d<CharacterBody2DComponent>(
          'stepHeight',
          (c) => c.stepHeight,
          (c, v) => c.stepHeight = v,
          min: 0,
        ),
        _d<CharacterBody2DComponent>(
          'stickToFloor',
          (c) => c.stickToFloor,
          (c, v) => c.stickToFloor = v,
          min: 0,
        ),
        _b<CharacterBody2DComponent>(
          'useGravity',
          (c) => c.useGravity,
          (c, v) => c.useGravity = v,
        ),
        _d<CharacterBody2DComponent>(
          'gravityScale',
          (c) => c.gravityScale,
          (c, v) => c.gravityScale = v,
        ),
        _d<CharacterBody2DComponent>(
          'mass',
          (c) => c.mass,
          (c, v) => c.mass = v,
          min: 0,
        ),
        _d<CharacterBody2DComponent>(
          'pushStrength',
          (c) => c.pushStrength,
          (c, v) => c.pushStrength = v,
          min: 0,
        ),
      ],
    );
  }

  static List<SchemaField> _joint<T extends Joint2DComponent>() => [
    SchemaField(
      name: 'connectedBody',
      kind: FieldTypes.target,
      read: (c) => (c as T).connectedBody,
      write: (c, v) =>
          (c as T).connectedBody = v is EntityTarget ? v : EntityTarget.none,
    ),
    _o<T>('anchor', (c) => c.anchor, (c, v) => c.anchor = v),
    _o<T>(
      'connectedAnchor',
      (c) => c.connectedAnchor,
      (c, v) => c.connectedAnchor = v,
    ),
    _b<T>(
      'collideConnected',
      (c) => c.collideConnected,
      (c, v) => c.collideConnected = v,
    ),
    _b<T>('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
  ];

  static const Map<String, FieldHint> _jointHints = {
    'connectedBody': FieldHint(
      label: 'Connected body',
      description:
          'The other body: an entity by name, or by tag. Both need a Rigid Body 2D and a Collider 2D.',
    ),
    'anchor': FieldHint(
      label: 'Anchor',
      description: 'Where on this entity it holds.',
    ),
    'connectedAnchor': FieldHint(
      label: 'Other anchor',
      description: 'Where on the other entity it holds.',
    ),
    'collideConnected': FieldHint(
      label: 'Collide connected',
      description: 'Whether the two bodies still collide with each other.',
    ),
    'enabled': FieldHint(label: 'Enabled'),
  };

  static const List<String> _jointFields = [
    'connectedBody',
    'anchor',
    'connectedAnchor',
    'collideConnected',
    'enabled',
  ];

  /// [DistanceJoint2DComponent], saved as `DistanceJoint2DComponent`.
  static ComponentDefinition<DistanceJoint2DComponent> get distanceJoint =>
      ComponentDefinition<DistanceJoint2DComponent>(
        type: 'DistanceJoint2DComponent',
        create: DistanceJoint2DComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Distance Joint 2D',
          group: _group,
          description: 'Keeps two bodies a set distance apart, springily.',
          icon: Icons.hub_outlined,
          accentColor: _accent,
          fieldGroups: {
            'Joint': _jointFields,
            'Distance': ['length', 'stiffness', 'damping'],
          },
          fields: {
            ..._jointHints,
            'length': FieldHint(
              label: 'Length',
              scrub: ScrubHint(fractionDigits: 2),
            ),
            'stiffness': FieldHint(
              label: 'Stiffness',
              description:
                  'How fast the spring pulls back, in hertz. '
                  '0 holds the length rigidly.',
              scrub: ScrubHint(fractionDigits: 2),
            ),
            'damping': FieldHint(
              label: 'Damping',
              description:
                  'Damping ratio: 0 swings on, 1 settles without '
                  'overshoot.',
              scrub: _plain,
            ),
          },
        ),
        fields: [
          ..._joint<DistanceJoint2DComponent>(),
          _d<DistanceJoint2DComponent>(
            'length',
            (c) => c.length,
            (c, v) => c.length = v,
            min: 0,
          ),
          _d<DistanceJoint2DComponent>(
            'stiffness',
            (c) => c.stiffness,
            (c, v) => c.stiffness = v,
            min: 0,
          ),
          _d<DistanceJoint2DComponent>(
            'damping',
            (c) => c.damping,
            (c, v) => c.damping = v,
            min: 0,
          ),
        ],
      );

  /// [FixedJoint2DComponent], saved as `FixedJoint2DComponent`.
  static ComponentDefinition<FixedJoint2DComponent> get fixedJoint =>
      ComponentDefinition<FixedJoint2DComponent>(
        type: 'FixedJoint2DComponent',
        create: FixedJoint2DComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Fixed Joint 2D',
          group: _group,
          description: 'Holds two bodies rigidly together.',
          icon: Icons.hub_outlined,
          accentColor: _accent,
          fieldGroups: {'Joint': _jointFields},
          fields: _jointHints,
        ),
        fields: _joint<FixedJoint2DComponent>(),
      );

  /// [SliderJoint2DComponent], saved as `SliderJoint2DComponent`.
  static ComponentDefinition<SliderJoint2DComponent>
  get sliderJoint => ComponentDefinition<SliderJoint2DComponent>(
    type: 'SliderJoint2DComponent',
    create: SliderJoint2DComponent.new,
    hints: ComponentHints(
      dimensions: Dimensions.twoD,
      name: 'Slider Joint 2D',
      group: _group,
      description:
          'Lets two bodies slide along one axis: a drawer, a piston, a lift.',
      icon: Icons.sync_alt,
      accentColor: _accent,
      fieldGroups: const {
        'Joint': [..._jointFields, 'axis'],
        'Limits': ['useLimits', 'minPosition', 'maxPosition'],
        'Motor': ['enableMotor', 'motorSpeed', 'motorMaxForce'],
      },
      fieldRows: const [
        FieldRowHint('Range', {'minPosition': 'Min', 'maxPosition': 'Max'}),
      ],
      fields: {
        ..._jointHints,
        'axis': const FieldHint(label: 'Axis'),
        'useLimits': const FieldHint(label: 'Limits'),
        'minPosition': FieldHint(
          label: 'Min',
          scrub: const ScrubHint(fractionDigits: 2),
          visibleWhen: (c) => (c as SliderJoint2DComponent).useLimits,
        ),
        'maxPosition': FieldHint(
          label: 'Max',
          scrub: const ScrubHint(fractionDigits: 2),
          visibleWhen: (c) => (c as SliderJoint2DComponent).useLimits,
        ),
        'enableMotor': const FieldHint(label: 'Motor'),
        'motorSpeed': FieldHint(
          label: 'Motor speed',
          scrub: const ScrubHint(step: 0.5, fractionDigits: 2),
          visibleWhen: (c) => (c as SliderJoint2DComponent).enableMotor,
        ),
        'motorMaxForce': FieldHint(
          label: 'Max force',
          scrub: const ScrubHint(step: 5, fractionDigits: 2),
          visibleWhen: (c) => (c as SliderJoint2DComponent).enableMotor,
        ),
      },
    ),
    fields: [
      ..._joint<SliderJoint2DComponent>(),
      _o<SliderJoint2DComponent>('axis', (c) => c.axis, (c, v) => c.axis = v),
      _b<SliderJoint2DComponent>(
        'useLimits',
        (c) => c.useLimits,
        (c, v) => c.useLimits = v,
      ),
      _d<SliderJoint2DComponent>(
        'minPosition',
        (c) => c.minPosition,
        (c, v) => c.minPosition = v,
      ),
      _d<SliderJoint2DComponent>(
        'maxPosition',
        (c) => c.maxPosition,
        (c, v) => c.maxPosition = v,
      ),
      _b<SliderJoint2DComponent>(
        'enableMotor',
        (c) => c.enableMotor,
        (c, v) => c.enableMotor = v,
      ),
      _d<SliderJoint2DComponent>(
        'motorSpeed',
        (c) => c.motorSpeed,
        (c, v) => c.motorSpeed = v,
      ),
      _d<SliderJoint2DComponent>(
        'motorMaxForce',
        (c) => c.motorMaxForce,
        (c, v) => c.motorMaxForce = v,
        min: 0,
      ),
    ],
  );

  /// [WheelJoint2DComponent], saved as `WheelJoint2DComponent`.
  static ComponentDefinition<WheelJoint2DComponent> get wheelJoint =>
      ComponentDefinition<WheelJoint2DComponent>(
        type: 'WheelJoint2DComponent',
        create: WheelJoint2DComponent.new,
        hints: ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Wheel Joint 2D',
          group: _group,
          description: 'A wheel on a suspension.',
          icon: Icons.trip_origin,
          accentColor: _accent,
          fieldGroups: const {
            'Joint': [..._jointFields, 'axis'],
            'Suspension': ['stiffness', 'damping'],
            'Motor': ['enableMotor', 'motorSpeed', 'motorMaxTorque'],
          },
          fields: {
            ..._jointHints,
            'axis': const FieldHint(label: 'Suspension axis'),
            'stiffness': const FieldHint(
              label: 'Stiffness',
              description:
                  'How fast the suspension springs back, in hertz. '
                  '0 is no spring.',
              scrub: ScrubHint(fractionDigits: 2),
            ),
            'damping': const FieldHint(
              label: 'Damping',
              description:
                  'Damping ratio: 0 bounces on, 1 settles without '
                  'overshoot.',
              scrub: _plain,
            ),
            'enableMotor': const FieldHint(label: 'Motor'),
            'motorSpeed': FieldHint(
              label: 'Motor speed',
              scrub: const ScrubHint(step: 0.5, fractionDigits: 2),
              visibleWhen: (c) => (c as WheelJoint2DComponent).enableMotor,
            ),
            'motorMaxTorque': FieldHint(
              label: 'Max torque',
              scrub: const ScrubHint(step: 5, fractionDigits: 2),
              visibleWhen: (c) => (c as WheelJoint2DComponent).enableMotor,
            ),
          },
        ),
        fields: [
          ..._joint<WheelJoint2DComponent>(),
          _o<WheelJoint2DComponent>(
            'axis',
            (c) => c.axis,
            (c, v) => c.axis = v,
          ),
          _d<WheelJoint2DComponent>(
            'stiffness',
            (c) => c.stiffness,
            (c, v) => c.stiffness = v,
            min: 0,
          ),
          _d<WheelJoint2DComponent>(
            'damping',
            (c) => c.damping,
            (c, v) => c.damping = v,
            min: 0,
          ),
          _b<WheelJoint2DComponent>(
            'enableMotor',
            (c) => c.enableMotor,
            (c, v) => c.enableMotor = v,
          ),
          _d<WheelJoint2DComponent>(
            'motorSpeed',
            (c) => c.motorSpeed,
            (c, v) => c.motorSpeed = v,
          ),
          _d<WheelJoint2DComponent>(
            'motorMaxTorque',
            (c) => c.motorMaxTorque,
            (c, v) => c.motorMaxTorque = v,
            min: 0,
          ),
        ],
      );

  /// Every 2-D physics definition.
  static List<ComponentDefinition> get all => [
    rigidBody,
    collider,
    characterBody,
    distanceJoint,
    fixedJoint,
    sliderJoint,
    wheelJoint,
  ];

  // What the 2-D and 3-D bodies' fields say, word for word: the 3-D
  // definitions show the same.

  /// The body type field's description.
  static const String bodyTypeDescription =
      'Static never moves: floors and walls. Kinematic moves only as its '
      'velocity says and cannot be pushed: moving platforms. Dynamic is '
      'fully simulated: it falls, bounces and is pushed.';

  /// The layer field's description.
  static const String layerDescription =
      'The collision layer it is on. Layers are named, and which collide '
      'chosen, in the Physics Layers dock.';

  /// The collides-with field's description.
  static const String collidesWithDescription =
      "The layers it collides with: as the project's grid says for its "
      'layer, unless chosen here. Two bodies collide only if each collides '
      "with the other's layer.";

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

  /// The character body's description.
  static const String characterDescription =
      'A character gameplay moves: walks slopes, climbs steps, rides '
      'platforms. It needs no rigid body or collider.';

  /// The detectable field's description.
  static const String detectableDescription =
      'Sensors detect it, rays hit it and bodies bump into it.';

  /// The collider shape field's description.
  static const String matchShapeDescription =
      'Match shape: the shape the entity is drawn as, following it.';

  static SchemaField _d<T extends Component>(
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

  static SchemaField _b<T extends Component>(
    String name,
    bool Function(T c) read,
    void Function(T c, bool v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as bool),
  );

  static SchemaField _o<T extends Component>(
    String name,
    Offset Function(T c) read,
    void Function(T c, Offset v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.offset,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as Offset),
  );
}

/// A collider's size is its shape's bounds (with its offset, turn and own
/// scale; before its entity's scale). Matching its entity's shape it adds
/// nothing of its own.
final class _Collider2DExtent extends ComponentExtent {
  const _Collider2DExtent();

  static Rect? _bounds(Collider2DComponent c) {
    if (c.shape == ColliderShape2D.matchShape) return null;
    final shape = ColliderGeometry.of(c);
    return shape == null ? null : ColliderGeometry.boundsOf(shape);
  }

  @override
  Size? sizeOf(Component c) => _bounds(c as Collider2DComponent)?.size;

  @override
  bool boundsInto(Component c, Aabb3 out) {
    final r = _bounds(c as Collider2DComponent);
    if (r == null) return false;
    out.setValues(r.left, r.top, 0, r.right, r.bottom, 0);
    return true;
  }

  /// Resizes the collider itself — its sizes, points and offset — the way a
  /// rectangle or circle resizes: a circle by the smaller factor.
  @override
  bool scale(Component c, double sx, double sy) {
    final collider = c as Collider2DComponent;
    if (collider.shape == ColliderShape2D.matchShape) return false;
    final ax = sx.abs(), ay = sy.abs();
    collider
      ..size = Vector2(
        math.max(collider.size.x * ax, 1),
        math.max(collider.size.y * ay, 1),
      )
      ..radius = math.max(collider.radius * math.min(ax, ay), 0.5)
      ..height = math.max(collider.height * ay, 1)
      ..points = [for (final p in collider.points) Offset(p.dx * ax, p.dy * ay)]
      ..cornerRadius = collider.cornerRadius * math.min(ax, ay)
      ..thickness = collider.thickness * math.max(ax, ay)
      ..offset = Offset(collider.offset.dx * ax, collider.offset.dy * ay);
    return true;
  }

  /// Mirrors the collider across the entity's centre: its offset, its turn,
  /// and the points of a shape that is not the same both ways round.
  @override
  void flip(Component c, {required bool horizontal}) {
    final collider = c as Collider2DComponent;
    final sx = horizontal ? -1.0 : 1.0, sy = horizontal ? 1.0 : -1.0;
    collider
      ..points = [
        for (final p in collider.points.reversed) Offset(p.dx * sx, p.dy * sy),
      ]
      ..offset = Offset(collider.offset.dx * sx, collider.offset.dy * sy)
      ..rotation = -collider.rotation;
  }
}

/// A character's size is its shape's (with its offset).
final class _CharacterBody2DExtent extends ComponentExtent {
  const _CharacterBody2DExtent();

  static Rect _bounds(CharacterBody2DComponent c) {
    final w = c.shape == CharacterShape2D.box ? c.width : 2 * c.radius;
    return Rect.fromCenter(
      center: c.offset,
      width: w,
      height: math.max(c.height, w),
    );
  }

  @override
  Size? sizeOf(Component c) => _bounds(c as CharacterBody2DComponent).size;

  @override
  bool boundsInto(Component c, Aabb3 out) {
    final r = _bounds(c as CharacterBody2DComponent);
    out.setValues(r.left, r.top, 0, r.right, r.bottom, 0);
    return true;
  }

  @override
  bool scale(Component c, double sx, double sy) {
    final body = c as CharacterBody2DComponent;
    final ax = sx.abs(), ay = sy.abs();
    body
      ..width = math.max(body.width * ax, 2.5)
      ..radius = math.max(body.radius * ax, 1.01)
      ..height = math.max(body.height * ay, 2.5)
      ..offset = Offset(body.offset.dx * ax, body.offset.dy * ay);
    return true;
  }

  @override
  void flip(Component c, {required bool horizontal}) {
    final body = c as CharacterBody2DComponent;
    body.offset = horizontal
        ? Offset(-body.offset.dx, body.offset.dy)
        : Offset(body.offset.dx, -body.offset.dy);
  }
}
