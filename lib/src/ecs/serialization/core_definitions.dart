library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import '../components/components.dart';
import '../ecs.dart';
import 'camera_definitions.dart';
import 'component_definition.dart';
import 'field_type.dart';

/// Definitions for the core components whose save format predates
/// definitions, one per built-in component.
/// today.
///
/// Field names are the legacy JSON keys, so migrating a file is a matter of
/// hoisting each component's keys under `fields` (and reshaping the two
/// vector-valued ones). Until the format flips, these drive the inspector,
/// sizing and drawing and are the wire format.
abstract final class CoreDefinitions {
  static SchemaField _d(
    String name,
    double Function(Component) read,
    void Function(Component, double) write, {
    double? min,
    double? max,
  }) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: read,
    write: (c, v) => write(c, (v as num).toDouble()),
    min: min,
    max: max,
  );

  static SchemaField _b(
    String name,
    bool Function(Component) read,
    void Function(Component, bool) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: read,
    write: (c, v) => write(c, v as bool),
  );

  static SchemaField _i(
    String name,
    int Function(Component) read,
    void Function(Component, int) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.integer,
    read: read,
    write: (c, v) => write(c, (v as num).toInt()),
  );

  static SchemaField _s(
    String name,
    String Function(Component) read,
    void Function(Component, String) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.text,
    read: read,
    write: (c, v) => write(c, v as String),
  );

  static SchemaField _o(
    String name,
    Offset Function(Component) read,
    void Function(Component, Offset) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.offset,
    read: read,
    write: (c, v) => write(c, v as Offset),
  );

  static SchemaField _style(
    String name,
    ShapePaintStyle Function(Component) read,
    void Function(Component, ShapePaintStyle) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.shapePaintStyle,
    read: read,
    write: (c, v) => write(c, v as ShapePaintStyle),
  );

  static final transform = ComponentDefinition<TransformComponent>(
    type: 'TransformComponent',
    hints: const ComponentHints(
      name: 'Transform',
      group: 'Core',
      description: 'Position, rotation, and scale.',
      icon: Icons.open_with,
      accentColor: Color(0xFF607D8B),
      deletable: false,
      fieldGroups: {
        'Position': ['position'],
        'Rotation': ['rotation', 'rotationX', 'rotationY'],
        'Scale': ['scale'],
      },
      fields: {
        'position': FieldHint(
          label: 'Position',
          scrub: ScrubHint(fractionDigits: 1),
        ),
        'rotation': FieldHint(
          label: 'Angle',
          unit: AngleUnit.degrees,
          scrub: ScrubHint(fractionDigits: 1),
        ),
        'rotationX': FieldHint(
          label: 'Tilt X',
          unit: AngleUnit.degrees,
          visible: false,
        ),
        'rotationY': FieldHint(
          label: 'Tilt Y',
          unit: AngleUnit.degrees,
          visible: false,
        ),
        'scale': FieldHint(
          label: 'Scale',
          scrub: ScrubHint(step: 0.05, fractionDigits: 3),
        ),
      },
    ),
    create: TransformComponent.new,
    fields: [
      SchemaField(
        name: 'position',
        kind: FieldTypes.vector2,
        read: (c) =>
            Vector2((c as TransformComponent).position.x, c.position.y),
        write: (c, v) =>
            (c as TransformComponent).setPositionXY((v as Vector2).x, v.y),
      ),
      _d(
        'rotation',
        (c) => (c as TransformComponent).rotation,
        (c, v) => (c as TransformComponent).rotation = v,
      ),
      SchemaField(
        name: 'scale',
        kind: FieldTypes.vector3,
        read: (c) => (c as TransformComponent).scale,
        write: (c, v) => (c as TransformComponent).scale.setFrom(v as Vector3),
      ),
      _d(
        'rotationX',
        (c) => (c as TransformComponent).rotationX,
        (c, v) => (c as TransformComponent).rotationX = v,
      ),
      _d(
        'rotationY',
        (c) => (c as TransformComponent).rotationY,
        (c, v) => (c as TransformComponent).rotationY = v,
      ),
    ],
  );

  static List<SchemaField> _styleFields<T extends Component>(
    ShapePaintStyle Function(T) fill,
    void Function(T, ShapePaintStyle) setFill,
    ShapePaintStyle Function(T) stroke,
    void Function(T, ShapePaintStyle) setStroke,
    bool Function(T) filled,
    void Function(T, bool) setFilled,
    double Function(T) strokeWidth,
    void Function(T, double) setStrokeWidth,
  ) => [
    _style('fillStyle', (c) => fill(c as T), (c, v) => setFill(c as T, v)),
    _style(
      'strokeStyle',
      (c) => stroke(c as T),
      (c, v) => setStroke(c as T, v),
    ),
    _b('filled', (c) => filled(c as T), (c, v) => setFilled(c as T, v)),
    _d(
      'strokeWidth',
      (c) => strokeWidth(c as T),
      (c, v) => setStrokeWidth(c as T, v),
      min: 0,
    ),
  ];

  static final rectangle = ComponentDefinition<RectangleComponent>(
    type: 'RectangleComponent',
    hints: const ComponentHints(
      name: 'Rectangle',
      group: 'Rendering',
      description: 'A filled or outlined rectangle.',
      icon: Icons.rectangle_outlined,
      accentColor: Color(0xFF42A5F5),
      fieldGroups: {
        'Size': ['width', 'height', 'cornerRadius'],
        'Appearance': ['filled', 'fillStyle', 'strokeStyle', 'strokeWidth'],
      },
      fieldRows: [
        FieldRowHint('Size', {'width': 'W', 'height': 'H'}),
      ],
      fields: {
        'width': FieldHint(label: 'W', scrub: ScrubHint(fractionDigits: 1)),
        'height': FieldHint(label: 'H', scrub: ScrubHint(fractionDigits: 1)),
        'cornerRadius': FieldHint(
          label: 'CR',
          scrub: ScrubHint(step: 0.5, fractionDigits: 1),
        ),
        ..._styleHints,
      },
    ),
    create: () => RectangleComponent(width: 64, height: 64),
    fields: [
      _d(
        'width',
        (c) => (c as RectangleComponent).width,
        (c, v) => (c as RectangleComponent).width = v,
        min: 1,
      ),
      _d(
        'height',
        (c) => (c as RectangleComponent).height,
        (c, v) => (c as RectangleComponent).height = v,
        min: 1,
      ),
      ..._styleFields<RectangleComponent>(
        (c) => c.fillStyle,
        (c, v) => c.fillStyle = v,
        (c) => c.strokeStyle,
        (c, v) => c.strokeStyle = v,
        (c) => c.filled,
        (c, v) => c.filled = v,
        (c) => c.strokeWidth,
        (c, v) => c.strokeWidth = v,
      ),
      _d(
        'cornerRadius',
        (c) => (c as RectangleComponent).cornerRadius,
        (c, v) => (c as RectangleComponent).cornerRadius = v,
        min: 0,
      ),
    ],
    extent: const _RectangleExtent(),
  );

  static final circle = ComponentDefinition<CircleComponent>(
    type: 'CircleComponent',
    hints: const ComponentHints(
      name: 'Circle',
      group: 'Rendering',
      description: 'A filled or outlined circle.',
      icon: Icons.circle_outlined,
      accentColor: Color(0xFF42A5F5),
      fieldGroups: {
        'Size': ['radius'],
        'Appearance': ['filled', 'fillStyle', 'strokeStyle', 'strokeWidth'],
      },
      fields: {
        'radius': FieldHint(
          label: 'Radius',
          scrub: ScrubHint(step: 0.5, fractionDigits: 1),
        ),
        ..._styleHints,
      },
    ),
    create: () => CircleComponent(radius: 32),
    fields: [
      _d(
        'radius',
        (c) => (c as CircleComponent).radius,
        (c, v) => (c as CircleComponent).radius = v,
        min: 1,
      ),
      ..._styleFields<CircleComponent>(
        (c) => c.fillStyle,
        (c, v) => c.fillStyle = v,
        (c) => c.strokeStyle,
        (c, v) => c.strokeStyle = v,
        (c) => c.filled,
        (c, v) => c.filled = v,
        (c) => c.strokeWidth,
        (c, v) => c.strokeWidth = v,
      ),
    ],
    extent: const _CircleExtent(),
  );

  static final capsule = ComponentDefinition<CapsuleComponent>(
    type: 'CapsuleComponent',
    hints: const ComponentHints(
      name: 'Capsule',
      group: 'Rendering',
      description: 'A filled or outlined capsule.',
      icon: Icons.crop_portrait,
      accentColor: Color(0xFF42A5F5),
      fieldGroups: {
        'Size': ['width', 'height'],
        'Appearance': ['filled', 'fillStyle', 'strokeStyle', 'strokeWidth'],
      },
      fieldRows: [
        FieldRowHint('Size', {'width': 'W', 'height': 'H'}),
      ],
      fields: {
        'width': FieldHint(label: 'W', scrub: ScrubHint(fractionDigits: 1)),
        'height': FieldHint(label: 'H', scrub: ScrubHint(fractionDigits: 1)),
        ..._styleHints,
      },
    ),
    create: () => CapsuleComponent(width: 32, height: 64),
    fields: [
      _d(
        'width',
        (c) => (c as CapsuleComponent).width,
        (c, v) => (c as CapsuleComponent).width = v,
        min: 1,
      ),
      _d(
        'height',
        (c) => (c as CapsuleComponent).height,
        (c, v) => (c as CapsuleComponent).height = v,
        min: 1,
      ),
      ..._styleFields<CapsuleComponent>(
        (c) => c.fillStyle,
        (c, v) => c.fillStyle = v,
        (c) => c.strokeStyle,
        (c, v) => c.strokeStyle = v,
        (c) => c.filled,
        (c, v) => c.filled = v,
        (c) => c.strokeWidth,
        (c, v) => c.strokeWidth = v,
      ),
    ],
    extent: const _CapsuleExtent(),
  );

  static final velocity = ComponentDefinition<VelocityComponent>(
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
        kind: FieldTypes.vector2,
        read: (c) => Vector2((c as VelocityComponent).velocity.x, c.velocity.y),
        write: (c, v) =>
            (c as VelocityComponent).setVelocityXY((v as Vector2).x, v.y),
      ),
      _d(
        'maxSpeed',
        (c) => (c as VelocityComponent).maxSpeed,
        (c, v) => (c as VelocityComponent).maxSpeed = v,
        min: 0,
      ),
    ],
  );

  static final health = ComponentDefinition<HealthComponent>(
    type: 'HealthComponent',
    hints: const ComponentHints(
      name: 'Health',
      group: 'Gameplay',
      description: 'Hit points and invulnerability.',
      icon: Icons.favorite,
      accentColor: Color(0xFF66BB6A),
      fieldGroups: {
        'Health': ['health', 'maxHealth'],
        'State': ['isInvulnerable'],
      },
      fieldRows: [
        FieldRowHint('Health', {'health': 'HP', 'maxHealth': 'Max'}),
      ],
      fields: {
        'health': FieldHint(label: 'HP', scrub: ScrubHint(fractionDigits: 1)),
        'maxHealth': FieldHint(
          label: 'Max',
          scrub: ScrubHint(fractionDigits: 1),
        ),
        'isInvulnerable': FieldHint(label: 'Invulnerable'),
      },
    ),
    create: () => HealthComponent(maxHealth: 100),
    fields: [
      _d(
        'health',
        (c) => (c as HealthComponent).health,
        (c, v) => (c as HealthComponent).health = v,
        min: 0,
      ),
      _d(
        'maxHealth',
        (c) => (c as HealthComponent).maxHealth,
        (c, v) => (c as HealthComponent).maxHealth = v,
        min: 0,
      ),
      _b(
        'isInvulnerable',
        (c) => (c as HealthComponent).isInvulnerable,
        (c, v) => (c as HealthComponent).isInvulnerable = v,
      ),
    ],
  );

  static final lifetime = ComponentDefinition<LifetimeComponent>(
    type: 'LifetimeComponent',
    hints: const ComponentHints(
      name: 'Lifetime',
      group: 'Gameplay',
      description: 'Destroys the entity after a delay.',
      icon: Icons.timer,
      accentColor: Color(0xFF66BB6A),
      fields: {
        'initialLifetime': FieldHint(
          label: 'Duration (s)',
          scrub: ScrubHint(step: 0.1, fractionDigits: 2),
        ),
      },
    ),
    create: () => LifetimeComponent(3.0),
    fields: [
      _d('initialLifetime', (c) => (c as LifetimeComponent).initialLifetime, (
        c,
        v,
      ) {
        (c as LifetimeComponent)
          ..initialLifetime = v
          ..timeRemaining = v;
      }, min: 0),
    ],
  );

  static final sprite = ComponentDefinition<SpriteComponent>(
    type: 'SpriteComponent',
    hints: const ComponentHints(
      name: 'Sprite',
      group: 'Rendering',
      description: 'An image, or one region of a sprite atlas.',
      icon: Icons.image,
      accentColor: Color(0xFF42A5F5),
      fieldGroups: {
        'Sprite': ['spritePath'],
        'From an atlas': ['atlasPath', 'region'],
        'Options': ['flipX', 'flipY', 'tint', 'pixelArt'],
      },
      fields: {
        'spritePath': FieldHint(label: 'Path'),
        'atlasPath': FieldHint(label: 'Atlas', fileExtensions: ['json']),
        'region': FieldHint(
          label: 'Region',
          description: 'Empty shows the first.',
        ),
        'pixelArt': FieldHint(
          label: 'Pixel art',
          description: 'No smoothing when scaled.',
        ),
        'flipX': FieldHint(label: 'Flip X'),
        'flipY': FieldHint(label: 'Flip Y'),
        'tint': FieldHint(label: 'Tint'),
      },
    ),
    create: () => SpriteComponent(spritePath: ''),
    fields: [
      SchemaField(
        name: 'spritePath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as SpriteComponent).spritePath,
        write: (c, v) => (c as SpriteComponent).spritePath = v as String,
      ),
      SchemaField(
        name: 'atlasPath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as SpriteComponent).atlasPath,
        write: (c, v) => (c as SpriteComponent).atlasPath = v as String,
      ),
      SchemaField(
        name: 'region',
        kind: FieldTypes.text,
        read: (c) => (c as SpriteComponent).region,
        write: (c, v) => (c as SpriteComponent).region = v as String,
      ),
      _b(
        'flipX',
        (c) => (c as SpriteComponent).flipX,
        (c, v) => (c as SpriteComponent).flipX = v,
      ),
      _b(
        'flipY',
        (c) => (c as SpriteComponent).flipY,
        (c, v) => (c as SpriteComponent).flipY = v,
      ),
      SchemaField(
        name: 'tint',
        kind: FieldTypes.color,
        read: (c) => (c as SpriteComponent).tint,
        write: (c, v) => (c as SpriteComponent).tint = v as Color?,
      ),
      _b(
        'pixelArt',
        (c) => (c as SpriteComponent).pixelArt,
        (c, v) => (c as SpriteComponent).pixelArt = v,
      ),
    ],
    extent: const _SpriteExtent(),
  );

  static final physicsBody = ComponentDefinition<PhysicsBodyComponent>(
    type: 'PhysicsBodyComponent',
    hints: const ComponentHints(
      name: 'Physics Body',
      group: 'Physics',
      description: 'Rigid body with a selectable collision shape.',
      icon: Icons.category_outlined,
      accentColor: Color(0xFFFF7043),
      fieldGroups: {
        'Shape': ['shape'],
        'Body': [
          'bodyType',
          'isStatic',
          'isSensor',
          'isOneWay',
          'oneWayDirection',
          'mass',
          'drag',
          'restitution',
          'gravityScale',
          'fixedRotation',
        ],
        'Collision': ['categoryBits', 'maskBits', 'groupIndex'],
        'Debug': ['showDebugOutline'],
      },
      fields: {
        'shape': FieldHint(label: 'Shape'),
        'bodyType': FieldHint(label: 'Body type'),
        'isStatic': FieldHint(label: 'Static'),
        'isSensor': FieldHint(label: 'Sensor'),
        'isOneWay': FieldHint(label: 'One-way'),
        'oneWayDirection': FieldHint(label: 'One-way dir'),
        'mass': FieldHint(
          label: 'Mass',
          scrub: ScrubHint(step: 0.1, fractionDigits: 2),
        ),
        'drag': FieldHint(
          label: 'Drag',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'restitution': FieldHint(
          label: 'Rest.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'gravityScale': FieldHint(
          label: 'Gravity scale',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'fixedRotation': FieldHint(label: 'Fixed rotation'),
        'categoryBits': FieldHint(
          label: 'Category',
          scrub: ScrubHint(integer: true),
        ),
        'maskBits': FieldHint(
          label: 'Mask Bits',
          scrub: ScrubHint(integer: true),
        ),
        'groupIndex': FieldHint(
          label: 'Group Index',
          scrub: ScrubHint(integer: true),
        ),
        'showDebugOutline': FieldHint(label: 'Show Outline'),
      },
    ),
    create: () => PhysicsBodyComponent(shape: RectangleShape(64, 64)),
    fields: [
      SchemaField(
        name: 'shape',
        kind: FieldTypes.physicsShape,
        read: (c) => (c as PhysicsBodyComponent).shape,
        write: (c, v) {
          if (v is CollisionShape) (c as PhysicsBodyComponent).shape = v;
        },
      ),
      _d(
        'mass',
        (c) => (c as PhysicsBodyComponent).mass,
        (c, v) => (c as PhysicsBodyComponent).mass = v,
        min: 0,
      ),
      _d(
        'restitution',
        (c) => (c as PhysicsBodyComponent).restitution,
        (c, v) => (c as PhysicsBodyComponent).restitution = v,
        min: 0,
        max: 1,
      ),
      _d(
        'drag',
        (c) => (c as PhysicsBodyComponent).drag,
        (c, v) => (c as PhysicsBodyComponent).drag = v,
        min: 0,
        max: 1,
      ),
      _b(
        'isStatic',
        (c) => (c as PhysicsBodyComponent).isStatic,
        (c, v) => (c as PhysicsBodyComponent).isStatic = v,
      ),
      _b(
        'isOneWay',
        (c) => (c as PhysicsBodyComponent).isOneWay,
        (c, v) => (c as PhysicsBodyComponent).isOneWay = v,
      ),
      _b(
        'isSensor',
        (c) => (c as PhysicsBodyComponent).isSensor,
        (c, v) => (c as PhysicsBodyComponent).isSensor = v,
      ),
      _i(
        'categoryBits',
        (c) => (c as PhysicsBodyComponent).categoryBits,
        (c, v) => (c as PhysicsBodyComponent).categoryBits = v,
      ),
      _i(
        'maskBits',
        (c) => (c as PhysicsBodyComponent).maskBits,
        (c, v) => (c as PhysicsBodyComponent).maskBits = v,
      ),
      _i(
        'groupIndex',
        (c) => (c as PhysicsBodyComponent).groupIndex,
        (c, v) => (c as PhysicsBodyComponent).groupIndex = v,
      ),
      _b(
        'showDebugOutline',
        (c) => (c as PhysicsBodyComponent).showDebugOutline,
        (c, v) => (c as PhysicsBodyComponent).showDebugOutline = v,
      ),
      SchemaField(
        name: 'bodyType',
        kind: const EnumFieldType(
          BodyType.values,
          fallback: BodyType.dynamic,
          id: 'enum.bodyType',
        ),
        read: (c) => (c as PhysicsBodyComponent).bodyType,
        write: (c, v) => (c as PhysicsBodyComponent).bodyType = v as BodyType,
      ),
      _b(
        'fixedRotation',
        (c) => (c as PhysicsBodyComponent).fixedRotation,
        (c, v) => (c as PhysicsBodyComponent).fixedRotation = v,
      ),
      _d(
        'gravityScale',
        (c) => (c as PhysicsBodyComponent).gravityScale,
        (c, v) => (c as PhysicsBodyComponent).gravityScale = v,
      ),
      SchemaField(
        name: 'oneWayDirection',
        kind: const EnumFieldType(
          OneWayDirection.values,
          fallback: OneWayDirection.fromAbove,
          id: 'enum.oneWayDirection',
        ),
        read: (c) => (c as PhysicsBodyComponent).oneWayDirection,
        write: (c, v) =>
            (c as PhysicsBodyComponent).oneWayDirection = v as OneWayDirection,
      ),
    ],
    extent: const _PhysicsBodyExtent(),
  );

  static final spawn = ComponentDefinition<SpawnComponent>(
    type: 'SpawnComponent',
    hints: const ComponentHints(
      name: 'Spawn Point',
      group: 'Gameplay',
      description: 'Where a spawner places an entity, by tag.',
      icon: Icons.person_pin_circle_rounded,
      accentColor: Color(0xFFFFB74D),
      fields: {'tag': FieldHint(label: 'Tag')},
    ),
    create: SpawnComponent.new,
    fields: [
      _s(
        'tag',
        (c) => (c as SpawnComponent).tag,
        (c, v) => (c as SpawnComponent).tag = v,
      ),
    ],
  );

  static final tag = ComponentDefinition<TagComponent>(
    type: 'TagComponent',
    hints: const ComponentHints(
      name: 'Tag',
      group: 'Gameplay',
      description: 'A label systems query by.',
      icon: Icons.label,
      accentColor: Color(0xFF66BB6A),
      fields: {'tag': FieldHint(label: 'Tag')},
    ),
    create: () => TagComponent(''),
    fields: [
      _s(
        'tag',
        (c) => (c as TagComponent).tag,
        (c, v) => (c as TagComponent).tag = v,
      ),
    ],
  );

  static final input = ComponentDefinition<InputComponent>(
    type: 'InputComponent',
    hints: const ComponentHints(
      name: 'Input',
      group: 'Input',
      icon: Icons.keyboard,
      accentColor: Color(0xFFEF5350),
    ),
    create: InputComponent.new,
    fields: const [],
  );

  static final effect = ComponentDefinition<EffectComponent>(
    type: 'EffectComponent',
    hints: const ComponentHints(
      name: 'Effects',
      group: 'Effects',
      icon: Icons.auto_awesome,
      accentColor: Color(0xFFFF4081),
    ),
    create: EffectComponent.new,
    fields: const [],
  );

  static final simpleMovement = ComponentDefinition<SimpleMovementComponent>(
    type: 'SimpleMovementComponent',
    hints: const ComponentHints(
      name: 'Simple Movement',
      group: 'Input',
      description: 'Keyboard / joystick movement.',
      icon: Icons.directions_run,
      accentColor: Color(0xFFEF5350),
      fieldGroups: {
        'Movement': ['speed', 'deadZone', 'normalizeDiagonal'],
        'Input': ['useKeyboard', 'useJoystick'],
      },
      fields: {
        'speed': FieldHint(
          label: 'Speed',
          scrub: ScrubHint(step: 5, fractionDigits: 1),
        ),
        'deadZone': FieldHint(
          label: 'Dead Zone',
          scrub: ScrubHint(step: 0.01, fractionDigits: 2),
        ),
        'normalizeDiagonal': FieldHint(label: 'Normalize Diagonal'),
        'useKeyboard': FieldHint(label: 'Use Keyboard'),
        'useJoystick': FieldHint(label: 'Use Joystick'),
      },
    ),
    create: SimpleMovementComponent.new,
    fields: [
      _d(
        'speed',
        (c) => (c as SimpleMovementComponent).speed,
        (c, v) => (c as SimpleMovementComponent).speed = v,
        min: 0,
      ),
      _b(
        'useKeyboard',
        (c) => (c as SimpleMovementComponent).useKeyboard,
        (c, v) => (c as SimpleMovementComponent).useKeyboard = v,
      ),
      _b(
        'useJoystick',
        (c) => (c as SimpleMovementComponent).useJoystick,
        (c, v) => (c as SimpleMovementComponent).useJoystick = v,
      ),
      _b(
        'normalizeDiagonal',
        (c) => (c as SimpleMovementComponent).normalizeDiagonal,
        (c, v) => (c as SimpleMovementComponent).normalizeDiagonal = v,
      ),
      _d(
        'deadZone',
        (c) => (c as SimpleMovementComponent).deadZone,
        (c, v) => (c as SimpleMovementComponent).deadZone = v,
        min: 0,
        max: 1,
      ),
    ],
  );

  static final children = ComponentDefinition<ChildrenComponent>(
    type: 'ChildrenComponent',
    hints: const ComponentHints(
      name: 'Children',
      group: 'Hierarchy',
      description: 'The entities parented to this one.',
      icon: Icons.account_tree,
      accentColor: Color(0xFF26A69A),
      fields: {'childIds': FieldHint(label: 'Children', editable: false)},
    ),
    create: ChildrenComponent.new,
    fields: [
      // Saved for reference only: ids are not stable across sessions, so the
      // loader re-links children by their parent's name instead.
      SchemaField(
        name: 'childIds',
        kind: FieldTypes.list,
        read: (c) => List<int>.of((c as ChildrenComponent).childIds),
      ),
    ],
  );

  static final parent = ComponentDefinition<ParentComponent>(
    type: 'ParentComponent',
    hints: const ComponentHints(
      name: 'Parent',
      group: 'Hierarchy',
      description: 'Follows another entity at a local offset.',
      icon: Icons.link,
      accentColor: Color(0xFF26A69A),
      fields: {
        'parentId': FieldHint(label: 'Parent', editable: false),
        'localOffset': FieldHint(
          label: 'Local offset',
          scrub: ScrubHint(fractionDigits: 1),
        ),
        'localRotation': FieldHint(
          label: 'Local angle',
          unit: AngleUnit.degrees,
          scrub: ScrubHint(fractionDigits: 1),
        ),
      },
    ),
    create: ParentComponent.new,
    fields: [
      // Re-linked by name on load; see childIds.
      SchemaField(
        name: 'parentId',
        kind: FieldTypes.integer,
        read: (c) => (c as ParentComponent).parentId,
      ),
      _o(
        'localOffset',
        (c) => Offset((c as ParentComponent).localOffset.x, c.localOffset.y),
        (c, v) => (c as ParentComponent).localOffset = Vector3(v.dx, v.dy, 0),
      ),
      _d(
        'localRotation',
        (c) => (c as ParentComponent).localRotation,
        (c, v) => (c as ParentComponent).localRotation = v,
      ),
    ],
  );

  static List<SchemaField> _jointCommon<T extends Component>(
    String Function(T) target,
    void Function(T, String) setTarget,
    bool Function(T) collide,
    void Function(T, bool) setCollide,
  ) => [
    _s(
      'targetEntityName',
      (c) => target(c as T),
      (c, v) => setTarget(c as T, v),
    ),
    _b(
      'collideConnected',
      (c) => collide(c as T),
      (c, v) => setCollide(c as T, v),
    ),
  ];

  static final distanceJoint = ComponentDefinition<DistanceJointComponent>(
    type: 'DistanceJointComponent',
    hints: const ComponentHints(
      name: 'Distance Joint',
      group: 'Physics',
      description: 'Keeps two bodies a set distance apart.',
      icon: Icons.hub_outlined,
      accentColor: Color(0xFFFF7043),
      fieldGroups: {
        'Joint': [
          'targetEntityName',
          'localAnchorA',
          'localAnchorB',
          'length',
          'collideConnected',
        ],
        'Spring': ['stiffness', 'damping'],
      },
      fields: {
        ..._jointHints,
        'length': FieldHint(
          label: 'Length',
          scrub: ScrubHint(fractionDigits: 2),
        ),
        'stiffness': FieldHint(
          label: 'Stiffness',
          scrub: ScrubHint(fractionDigits: 2),
        ),
        'damping': FieldHint(
          label: 'Damping',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
      },
    ),
    create: DistanceJointComponent.new,
    fields: [
      ..._jointCommon<DistanceJointComponent>(
        (c) => c.targetEntityName,
        (c, v) => c.targetEntityName = v,
        (c) => c.collideConnected,
        (c, v) => c.collideConnected = v,
      ),
      _o(
        'localAnchorA',
        (c) => (c as DistanceJointComponent).localAnchorA,
        (c, v) => (c as DistanceJointComponent).localAnchorA = v,
      ),
      _o(
        'localAnchorB',
        (c) => (c as DistanceJointComponent).localAnchorB,
        (c, v) => (c as DistanceJointComponent).localAnchorB = v,
      ),
      _d(
        'length',
        (c) => (c as DistanceJointComponent).length,
        (c, v) => (c as DistanceJointComponent).length = v,
        min: 0,
      ),
      _d(
        'stiffness',
        (c) => (c as DistanceJointComponent).stiffness,
        (c, v) => (c as DistanceJointComponent).stiffness = v,
        min: 0,
      ),
      _d(
        'damping',
        (c) => (c as DistanceJointComponent).damping,
        (c, v) => (c as DistanceJointComponent).damping = v,
        min: 0,
      ),
    ],
  );

  static final weldJoint = ComponentDefinition<WeldJointComponent>(
    type: 'WeldJointComponent',
    hints: const ComponentHints(
      name: 'Weld Joint',
      group: 'Physics',
      description: 'Fixes two bodies together.',
      icon: Icons.hub_outlined,
      accentColor: Color(0xFFFF7043),
      fields: {..._jointHints},
    ),
    create: WeldJointComponent.new,
    fields: [
      ..._jointCommon<WeldJointComponent>(
        (c) => c.targetEntityName,
        (c, v) => c.targetEntityName = v,
        (c) => c.collideConnected,
        (c, v) => c.collideConnected = v,
      ),
      _o(
        'localAnchorA',
        (c) => (c as WeldJointComponent).localAnchorA,
        (c, v) => (c as WeldJointComponent).localAnchorA = v,
      ),
      _o(
        'localAnchorB',
        (c) => (c as WeldJointComponent).localAnchorB,
        (c, v) => (c as WeldJointComponent).localAnchorB = v,
      ),
    ],
  );

  static final prismaticJoint = ComponentDefinition<PrismaticJointComponent>(
    type: 'PrismaticJointComponent',
    hints: const ComponentHints(
      name: 'Prismatic Joint',
      group: 'Physics',
      description: 'Slides along one axis.',
      icon: Icons.sync_alt,
      accentColor: Color(0xFFFF7043),
      fieldGroups: {
        'Joint': [
          'targetEntityName',
          'localAnchorA',
          'localAnchorB',
          'axis',
          'collideConnected',
        ],
        'Motor': ['enableMotor', 'motorSpeed', 'maxMotorForce'],
        'Limits': ['enableLimit', 'lowerTranslation', 'upperTranslation'],
      },
      fieldRows: [
        FieldRowHint('Range', {
          'lowerTranslation': 'Min',
          'upperTranslation': 'Max',
        }),
      ],
      fields: {
        ..._jointHints,
        'axis': FieldHint(label: 'Axis'),
        'enableMotor': FieldHint(label: 'Enable Motor'),
        'motorSpeed': FieldHint(
          label: 'Motor Speed',
          scrub: ScrubHint(step: 0.5, fractionDigits: 2),
        ),
        'maxMotorForce': FieldHint(
          label: 'Max Force',
          scrub: ScrubHint(step: 5, fractionDigits: 2),
        ),
        'enableLimit': FieldHint(label: 'Enable Limit'),
        'lowerTranslation': FieldHint(
          label: 'Lower',
          scrub: ScrubHint(fractionDigits: 2),
        ),
        'upperTranslation': FieldHint(
          label: 'Upper',
          scrub: ScrubHint(fractionDigits: 2),
        ),
      },
    ),
    create: PrismaticJointComponent.new,
    fields: [
      ..._jointCommon<PrismaticJointComponent>(
        (c) => c.targetEntityName,
        (c, v) => c.targetEntityName = v,
        (c) => c.collideConnected,
        (c, v) => c.collideConnected = v,
      ),
      _o(
        'axis',
        (c) => (c as PrismaticJointComponent).axis,
        (c, v) => (c as PrismaticJointComponent).axis = v,
      ),
      _b(
        'enableLimit',
        (c) => (c as PrismaticJointComponent).enableLimit,
        (c, v) => (c as PrismaticJointComponent).enableLimit = v,
      ),
      _d(
        'lowerTranslation',
        (c) => (c as PrismaticJointComponent).lowerTranslation,
        (c, v) => (c as PrismaticJointComponent).lowerTranslation = v,
      ),
      _d(
        'upperTranslation',
        (c) => (c as PrismaticJointComponent).upperTranslation,
        (c, v) => (c as PrismaticJointComponent).upperTranslation = v,
      ),
      _b(
        'enableMotor',
        (c) => (c as PrismaticJointComponent).enableMotor,
        (c, v) => (c as PrismaticJointComponent).enableMotor = v,
      ),
      _d(
        'motorSpeed',
        (c) => (c as PrismaticJointComponent).motorSpeed,
        (c, v) => (c as PrismaticJointComponent).motorSpeed = v,
      ),
      _d(
        'maxMotorForce',
        (c) => (c as PrismaticJointComponent).maxMotorForce,
        (c, v) => (c as PrismaticJointComponent).maxMotorForce = v,
        min: 0,
      ),
    ],
  );

  static final wheelJoint = ComponentDefinition<WheelJointComponent>(
    type: 'WheelJointComponent',
    hints: const ComponentHints(
      name: 'Wheel Joint',
      group: 'Physics',
      description: 'A wheel on a suspension.',
      icon: Icons.trip_origin,
      accentColor: Color(0xFFFF7043),
      fieldGroups: {
        'Joint': [
          'targetEntityName',
          'localAnchorA',
          'localAnchorB',
          'suspensionAxis',
          'collideConnected',
        ],
        'Motor': ['enableMotor', 'motorSpeed', 'maxMotorTorque'],
        'Spring': ['stiffness', 'damping'],
      },
      fields: {
        ..._jointHints,
        'suspensionAxis': FieldHint(label: 'Suspension Axis'),
        'enableMotor': FieldHint(label: 'Enable Motor'),
        'motorSpeed': FieldHint(
          label: 'Motor Speed',
          scrub: ScrubHint(step: 0.5, fractionDigits: 2),
        ),
        'maxMotorTorque': FieldHint(
          label: 'Max Torque',
          scrub: ScrubHint(step: 5, fractionDigits: 2),
        ),
        'stiffness': FieldHint(
          label: 'Stiffness',
          scrub: ScrubHint(fractionDigits: 2),
        ),
        'damping': FieldHint(
          label: 'Damping',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
      },
    ),
    create: WheelJointComponent.new,
    fields: [
      ..._jointCommon<WheelJointComponent>(
        (c) => c.targetEntityName,
        (c, v) => c.targetEntityName = v,
        (c) => c.collideConnected,
        (c, v) => c.collideConnected = v,
      ),
      _o(
        'suspensionAxis',
        (c) => (c as WheelJointComponent).suspensionAxis,
        (c, v) => (c as WheelJointComponent).suspensionAxis = v,
      ),
      _d(
        'stiffness',
        (c) => (c as WheelJointComponent).stiffness,
        (c, v) => (c as WheelJointComponent).stiffness = v,
        min: 0,
      ),
      _d(
        'damping',
        (c) => (c as WheelJointComponent).damping,
        (c, v) => (c as WheelJointComponent).damping = v,
        min: 0,
      ),
      _b(
        'enableMotor',
        (c) => (c as WheelJointComponent).enableMotor,
        (c, v) => (c as WheelJointComponent).enableMotor = v,
      ),
      _d(
        'motorSpeed',
        (c) => (c as WheelJointComponent).motorSpeed,
        (c, v) => (c as WheelJointComponent).motorSpeed = v,
      ),
      _d(
        'maxMotorTorque',
        (c) => (c as WheelJointComponent).maxMotorTorque,
        (c, v) => (c as WheelJointComponent).maxMotorTorque = v,
        min: 0,
      ),
    ],
  );

  /// Every definition above.
  static List<ComponentDefinition> get all => [
    transform,
    rectangle,
    circle,
    capsule,
    velocity,
    health,
    lifetime,
    sprite,
    physicsBody,
    ...CameraDefinitions.all,
    spawn,
    tag,
    input,
    effect,
    simpleMovement,
    children,
    parent,
    distanceJoint,
    weldJoint,
    prismaticJoint,
    wheelJoint,
  ];

  /// Presentation shared by the shape components' style fields.
  static const Map<String, FieldHint> _styleHints = {
    'filled': FieldHint(label: 'Filled'),
    'fillStyle': FieldHint(label: 'Fill'),
    'strokeStyle': FieldHint(label: 'Stroke'),
    'strokeWidth': FieldHint(
      label: 'SW',
      scrub: ScrubHint(step: 0.5, fractionDigits: 1),
    ),
  };

  /// Presentation shared by every joint's common fields.
  static const Map<String, FieldHint> _jointHints = {
    'targetEntityName': FieldHint(label: 'Target Name'),
    'localAnchorA': FieldHint(label: 'Anchor A'),
    'localAnchorB': FieldHint(label: 'Anchor B'),
    'collideConnected': FieldHint(label: 'Collide Connected'),
  };
}

class _RectangleExtent extends ComponentExtent {
  const _RectangleExtent();
  @override
  Size? sizeOf(Component c) => Size((c as RectangleComponent).width, c.height);
  @override
  bool scale(Component c, double sx, double sy) {
    (c as RectangleComponent)
      ..width = (c.width * sx).abs().clamp(1, double.infinity)
      ..height = (c.height * sy).abs().clamp(1, double.infinity);
    return true;
  }
}

class _CircleExtent extends ComponentExtent {
  const _CircleExtent();
  @override
  Size? sizeOf(Component c) => Size.square((c as CircleComponent).radius * 2);
  @override
  bool scale(Component c, double sx, double sy) {
    final k = sx < sy ? sx : sy;
    (c as CircleComponent).radius = (c.radius * k).abs().clamp(
      0.5,
      double.infinity,
    );
    return true;
  }
}

class _CapsuleExtent extends ComponentExtent {
  const _CapsuleExtent();
  @override
  Size? sizeOf(Component c) => Size((c as CapsuleComponent).width, c.height);
  @override
  bool scale(Component c, double sx, double sy) {
    (c as CapsuleComponent)
      ..width = (c.width * sx).abs().clamp(1, double.infinity)
      ..height = (c.height * sy).abs().clamp(1, double.infinity);
    return true;
  }
}

class _SpriteExtent extends ComponentExtent {
  const _SpriteExtent();
  @override
  Size? sizeOf(Component c) => null;
  @override
  void flip(Component c, {required bool horizontal}) {
    final s = c as SpriteComponent;
    horizontal ? s.flipX = !s.flipX : s.flipY = !s.flipY;
  }
}

class _PhysicsBodyExtent extends ComponentExtent {
  const _PhysicsBodyExtent();
  @override
  Size? sizeOf(Component c) =>
      (c as PhysicsBodyComponent).shape.getBounds(Offset.zero).size;
  @override
  bool scale(Component c, double sx, double sy) {
    final body = c as PhysicsBodyComponent;
    final shape = body.shape;
    if (shape is RectangleShape) {
      body.shape = RectangleShape(
        (shape.width * sx).abs().clamp(1, double.infinity),
        (shape.height * sy).abs().clamp(1, double.infinity),
      );
      return true;
    }
    if (shape is CircleShape) {
      final k = sx < sy ? sx : sy;
      body.shape = CircleShape(
        (shape.radius * k).abs().clamp(0.5, double.infinity),
      );
      return true;
    }
    return false;
  }
}
