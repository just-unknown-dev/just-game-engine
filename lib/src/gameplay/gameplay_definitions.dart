/// The gameplay components: velocity, health, lifetime, spawn points and

/// checkpoints.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_schema.dart';
import '../ecs/serialization/field_type.dart';
import '../ecs/serialization/schema_fields.dart';
import '../foundation/dimensions.dart';
import 'checkpoint_component.dart';
import 'health_component.dart';
import 'lifetime_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';
import 'spawn_component.dart';

/// The gameplay components: velocity, health, lifetime, spawn points and
/// checkpoints.
abstract final class GameplayDefinitions {
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
          SchemaFields.decimal(
            'health',
            (c) => (c as HealthComponent).health,
            (c, v) => (c as HealthComponent).health = v,
            min: 0,
          ),
          SchemaFields.decimal(
            'maxHealth',
            (c) => (c as HealthComponent).maxHealth,
            (c, v) => (c as HealthComponent).maxHealth = v,
            min: 0,
          ),
          SchemaFields.boolean(
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
          SchemaFields.decimal(
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

  /// [CheckpointComponent], from `checkpoint_editor_component.dart`.
  static ComponentSchema<CheckpointComponent> get checkpoint =>
      ComponentSchema<CheckpointComponent>(
        type: 'CheckpointComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Checkpoint',
          group: 'Gameplay',
          icon: Icons.flag_outlined,
          accentColor: Color(0xFF66BB6A),
          fields: {
            'respawnX': FieldHint(label: 'Respawn X'),
            'respawnY': FieldHint(label: 'Respawn Y'),
            'radius': FieldHint(label: 'Radius', scrub: ScrubHint()),
          },
        ),
        id: 'checkpoint_5e2b9d71',
        create: () => CheckpointComponent(respawnPosition: Vector3.zero()),
        fields: [
          SchemaField(
            name: 'respawnX',
            kind: FieldTypes.decimal,
            read: (c) => (c as CheckpointComponent).respawnPosition.x,
            write: (c, v) => (c as CheckpointComponent).respawnPosition.x =
                (v as num).toDouble(),
          ),
          SchemaField(
            name: 'respawnY',
            kind: FieldTypes.decimal,
            read: (c) => (c as CheckpointComponent).respawnPosition.y,
            write: (c, v) => (c as CheckpointComponent).respawnPosition.y =
                (v as num).toDouble(),
          ),
          SchemaField(
            name: 'radius',
            kind: FieldTypes.decimal,
            read: (c) => (c as CheckpointComponent).radius,
            write: (c, v) =>
                (c as CheckpointComponent).radius = (v as num).toDouble(),
            min: 0,
            max: 4096,
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [health, lifetime, spawn, checkpoint];
}
