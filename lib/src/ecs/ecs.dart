/// Core ECS (Entity-Component-System) Architecture
///
/// Provides the foundational types for data-oriented game architecture:
/// - [Component] — pure data, no logic
/// - [Archetype] — cache-friendly dense storage grouped by component set
/// - [Entity] — lightweight handle (ID + component access)
/// - [System] — logic that operates on matching entities
/// - [World] — central manager for entities, systems, and queries
library;

import 'dart:collection';
import 'dart:math';
import 'dart:ui' show Canvas, Size;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kReleaseMode;
import 'package:meta/meta.dart' show internal;

import 'engine_context.dart';

export 'engine_context.dart';
import 'transform/children_component.dart';
import 'transform/parent_component.dart';
import 'transform/transform_hierarchy.dart';
import 'system_priorities.dart';
export 'transform/transform_component.dart';
export 'transform/euler_rotation.dart';
export 'transform/hierarchy_system.dart';
export 'generated_entity_component.dart';
export 'transform/parent_component.dart';
export 'transform/children_component.dart';
export 'transform/transform_hierarchy.dart';
export 'system_priorities.dart';
export 'serialization/component_codec.dart';
export 'serialization/component_definition.dart';
export 'serialization/component_presentation.dart';
export 'serialization/component_definition_registry.dart';
export 'serialization/field_type.dart';
export 'serialization/component_schema.dart';
export 'serialization/ecs_definitions.dart';
export 'serialization/field_value_codec.dart';
export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show
        SceneFormat,
        SceneManifest,
        SceneNames,
        SceneStarters,
        FieldMigration,
        MigrationHooks,
        MigrationNote,
        MigrationRun,
        MigrationResult,
        UnsupportedFormatVersionException;
export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show
        SceneMigration,
        ComponentMigration,
        EntityMigration,
        V0ToV1,
        V1ToV2,
        V2ToV3,
        V3ToV4,
        V4ToV5,
        V5ToV6,
        V6ToV7,
        V7ToV8,
        V8ToV9,
        V9ToV10,
        V10ToV11,
        SceneMigrations;
export 'serialization/tag_library.dart';
export 'spatial/entity_spatial_grid.dart';
export 'spatial/spatial_index.dart';

part 'component.dart';
part 'archetype.dart';
part 'entity.dart';
part 'system.dart';
part 'world.dart';
part 'command_buffer.dart';
part 'event_bus.dart';
part 'entity_prefab.dart';
part 'tags.dart';
part 'entity_target.dart';
