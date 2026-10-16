library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import '../../foundation/dimensions.dart';
import 'package:just_dart/just_dart.dart';

import '../components/components.dart';
import '../ecs.dart';
import 'camera_definitions.dart';
import 'timeline_definitions.dart';
import 'component_definition.dart';
import 'component_presentation.dart';
import 'field_type.dart';
import 'level_map_definitions.dart';
import 'physics_definitions_2d.dart';

/// Definitions for the core components whose save format predates
/// definitions, one per built-in component.
///
/// Field names are the legacy JSON keys, so migrating an old file was a
/// matter of hoisting each component's keys under `fields` (and reshaping
/// the two vector-valued ones) — what `V0ToV1` does. These drive the
/// inspector, sizing and drawing, and are the save format.
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

  /// Definition of [TransformComponent], saved as `TransformComponent`:
  /// `position`, `rotation` (Euler angles in radians) and `scale`. It
  /// cannot be removed in the inspector.
  static ComponentDefinition<TransformComponent> get transform =>
      ComponentDefinition<TransformComponent>(
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
            'Rotation': ['rotation'],
            'Scale': ['scale'],
          },
          fields: {
            'position': FieldHint(
              label: 'Position',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            // Three angles; a 2-D scene shows only the one about Z.
            'rotation': FieldHint(
              label: 'Rotation',
              unit: AngleUnit.degrees,
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'scale': FieldHint(
              label: 'Scale',
              scrub: ScrubHint(step: 0.05, fractionDigits: 3),
            ),
          },
        ),
        create: TransformComponent.new,
        // A loaded transform has not moved yet: its previous pose is the one
        // just read. Left at the origin, render interpolation would draw a
        // physics body sliding in from (0, 0) until its first physics step.
        afterDecode: (c) => (c as TransformComponent).capturePrevious(),
        fields: [
          SchemaField(
            name: 'position',
            kind: FieldTypes.vector3,
            read: (c) => Vector3.copy((c as TransformComponent).position),
            write: (c, v) =>
                (c as TransformComponent).position.setFrom(v as Vector3),
          ),
          SchemaField(
            name: 'rotation',
            kind: FieldTypes.euler,
            read: (c) {
              final t = c as TransformComponent;
              return Vector3(t.eulerX, t.eulerY, t.angle);
            },
            write: (c, v) {
              final e = v as Vector3;
              (c as TransformComponent).setEuler(e.x, e.y, e.z);
            },
          ),
          SchemaField(
            name: 'scale',
            kind: FieldTypes.vector3,
            read: (c) => (c as TransformComponent).scale,
            write: (c, v) =>
                (c as TransformComponent).scale.setFrom(v as Vector3),
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

  /// Definition of [RectangleComponent], saved as `RectangleComponent`; a
  /// new one is 64 × 64. 2-D only.
  static ComponentDefinition<RectangleComponent> get rectangle =>
      ComponentDefinition<RectangleComponent>(
        type: 'RectangleComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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
            'height': FieldHint(
              label: 'H',
              scrub: ScrubHint(fractionDigits: 1),
            ),
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

  /// Definition of [CircleComponent], saved as `CircleComponent`; a new one
  /// has radius 32. 2-D only.
  static ComponentDefinition<CircleComponent> get circle =>
      ComponentDefinition<CircleComponent>(
        type: 'CircleComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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

  /// Definition of [CapsuleComponent], saved as `CapsuleComponent`; a new
  /// one is 32 wide, 64 high. 2-D only.
  static ComponentDefinition<CapsuleComponent> get capsule =>
      ComponentDefinition<CapsuleComponent>(
        type: 'CapsuleComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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
            'height': FieldHint(
              label: 'H',
              scrub: ScrubHint(fractionDigits: 1),
            ),
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
          _d(
            'maxSpeed',
            (c) => (c as VelocityComponent).maxSpeed,
            (c, v) => (c as VelocityComponent).maxSpeed = v,
            min: 0,
          ),
        ],
      );

  /// Definition of [HealthComponent], saved as `HealthComponent`; a new one
  /// has 100 max health.
  static ComponentDefinition<HealthComponent> get health =>
      ComponentDefinition<HealthComponent>(
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
            'health': FieldHint(
              label: 'HP',
              scrub: ScrubHint(fractionDigits: 1),
            ),
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

  /// Definition of [LifetimeComponent], saved as `LifetimeComponent`; a new
  /// one lasts 3 seconds.
  static ComponentDefinition<LifetimeComponent> get lifetime =>
      ComponentDefinition<LifetimeComponent>(
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
          _d(
            'initialLifetime',
            (c) => (c as LifetimeComponent).initialLifetime,
            (c, v) {
              (c as LifetimeComponent)
                ..initialLifetime = v
                ..timeRemaining = v;
            },
            min: 0,
          ),
        ],
      );

  /// Definition of [SpriteComponent], saved as `SpriteComponent`. 2-D
  /// only.
  static ComponentDefinition<SpriteComponent> get sprite =>
      ComponentDefinition<SpriteComponent>(
        type: 'SpriteComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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

  /// Definition of [SpawnComponent] (a spawn point), saved as
  /// `SpawnComponent`.
  static ComponentDefinition<SpawnComponent> get spawn =>
      ComponentDefinition<SpawnComponent>(
        type: 'SpawnComponent',
        hints: const ComponentHints(
          name: 'Spawn Point',
          group: 'Gameplay',
          description:
              'Where the game creates something when the level starts.',
          icon: Icons.person_pin_circle_rounded,
          accentColor: Color(0xFFFFB74D),
          fields: {
            'spawner': FieldHint(
              label: 'Spawns',
              description:
                  'What is created here, from the spawners the game '
                  'registers.',
            ),
          },
        ),
        create: SpawnComponent.new,
        // Saved as `tag` until scene format 7.
        fields: [
          SchemaField(
            name: 'spawner',
            kind: FieldTypes.spawnerRef,
            read: (c) => (c as SpawnComponent).spawner,
            write: (c, v) => (c as SpawnComponent).spawner = v as String? ?? '',
          ),
        ],
      );

  /// Definition of [TagComponent], saved as `TagComponent` with its tags as
  /// a `tags` list.
  static ComponentDefinition<TagComponent> get tag =>
      ComponentDefinition<TagComponent>(
        type: 'TagComponent',
        hints: const ComponentHints(
          name: 'Tag',
          group: 'Gameplay',
          description:
              'Labels cameras, triggers and systems find this entity by. An '
              'entity can carry several.',
          icon: Icons.label,
          accentColor: Color(0xFF66BB6A),
          fields: {'tags': FieldHint(label: 'Tags')},
        ),
        create: TagComponent.new,
        // Saved as one `tag` until scene format 7.
        fields: [
          SchemaField(
            name: 'tags',
            kind: FieldTypes.tagList,
            read: (c) => (c as TagComponent).tags.toList(),
            write: (c, v) => (c as TagComponent).tags = [
              for (final t in v as List? ?? const []) '$t',
            ],
          ),
        ],
      );

  /// Definition of [InputComponent], saved as `InputComponent`: its
  /// `playerIndex` (-1 reads every device).
  static ComponentDefinition<InputComponent> get input =>
      ComponentDefinition<InputComponent>(
        type: 'InputComponent',
        hints: const ComponentHints(
          name: 'Input',
          group: 'Input',
          description: "A player's actions, by name, for this entity.",
          icon: Icons.keyboard,
          accentColor: Color(0xFFEF5350),
          fields: {
            'playerIndex': FieldHint(
              label: 'Player',
              description:
                  '0 is player 1. -1 reads every device, whoever is playing.',
            ),
          },
        ),
        create: InputComponent.new,
        fields: [
          _i(
            'playerIndex',
            (c) => (c as InputComponent).playerIndex,
            (c, v) => (c as InputComponent).playerIndex = v,
          ),
        ],
      );

  /// Definition of [EffectComponent], saved as `EffectComponent` with no
  /// fields: its effect queue is not saved, so a loaded one starts empty.
  static ComponentDefinition<EffectComponent> get effect =>
      ComponentDefinition<EffectComponent>(
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

  /// Definition of [SimpleMovementComponent], saved as
  /// `SimpleMovementComponent`. 2-D only.
  static ComponentDefinition<SimpleMovementComponent> get simpleMovement =>
      ComponentDefinition<SimpleMovementComponent>(
        type: 'SimpleMovementComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Simple Movement',
          group: 'Input',
          description: 'Moves straight from a vector action, no physics.',
          icon: Icons.directions_run,
          accentColor: Color(0xFFEF5350),
          fieldGroups: {
            'Movement': ['speed', 'deadZone', 'normalizeDiagonal'],
            'Input': ['action', 'playerIndex'],
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
            'action': FieldHint(label: 'Action'),
            'playerIndex': FieldHint(
              label: 'Player',
              description: '0 is player 1. -1 reads every device.',
            ),
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
          _s(
            'action',
            (c) => (c as SimpleMovementComponent).action,
            (c, v) => (c as SimpleMovementComponent).action = v,
          ),
          _i(
            'playerIndex',
            (c) => (c as SimpleMovementComponent).playerIndex,
            (c, v) => (c as SimpleMovementComponent).playerIndex = v,
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

  /// Definition of [ChildrenComponent], saved as `ChildrenComponent`. Its
  /// `childIds` are saved for reference only and never read back.
  static ComponentDefinition<ChildrenComponent>
  get children => ComponentDefinition<ChildrenComponent>(
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

  /// Definition of [ParentComponent], saved as `ParentComponent`. Its
  /// `parentId` is saved for reference only; no local transform is saved.
  static ComponentDefinition<ParentComponent> get parent =>
      ComponentDefinition<ParentComponent>(
        type: 'ParentComponent',
        hints: const ComponentHints(
          name: 'Parent',
          group: 'Hierarchy',
          description:
              'Hangs this entity under another: it moves, turns and scales '
              'with it. The local values are worked out from where things are.',
          icon: Icons.link,
          accentColor: Color(0xFF26A69A),
          fields: {'parentId': FieldHint(label: 'Parent', editable: false)},
        ),
        create: ParentComponent.new,
        fields: [
          // Re-linked by name on load; see childIds.
          SchemaField(
            name: 'parentId',
            kind: FieldTypes.integer,
            read: (c) => (c as ParentComponent).parentId,
          ),
          // Nothing local is saved: the offset from the parent follows from
          // the world transforms, which are what the file means.
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
    ...PhysicsDefinitions2D.all,
    ...CameraDefinitions.all,
    ...TimelineDefinitions.all,
    ...LevelMapDefinitions.all,
    spawn,
    tag,
    input,
    effect,
    simpleMovement,
    children,
    parent,
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
