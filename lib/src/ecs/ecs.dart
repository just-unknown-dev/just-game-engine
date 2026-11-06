/// Core ECS (Entity-Component-System) Architecture
///
/// Provides the foundational types for data-oriented game architecture:
/// - [Component] — pure data, no logic
/// - [Archetype] — cache-friendly dense storage grouped by component set
/// - [Entity] — lightweight handle (ID + component access)
/// - [System] — logic that operates on matching entities
/// - [World] — central manager for entities, systems, and queries
///
/// The folder's barrel: it exports, and holds nothing itself. The types
/// above are one library, `world.dart`.
library;

export 'world.dart';
export 'engine_context.dart';
export 'generated_entity_component.dart';
export 'system_priorities.dart';
export 'transform/transform_component.dart';
export 'transform/euler_rotation.dart';
export 'transform/parent_component.dart';
export 'transform/children_component.dart';
export 'transform/transform_hierarchy.dart';
export 'transform/velocity_component.dart';
export 'serialization/component_codec.dart';
export 'serialization/component_definition.dart';
export 'serialization/component_presentation.dart';
export 'serialization/component_definition_registry.dart';
export 'serialization/built_in_field_types.dart' hide UnknownFieldType;
export 'serialization/field_type.dart';
export 'serialization/ecs_definitions.dart';
export 'serialization/field_value_codec.dart';
export 'serialization/tag_library.dart';
export 'spatial/entity_spatial_grid.dart';
export 'spatial/spatial_index.dart';

// The hooks a package adds its own scene migrations through
// (`context.migrations`), and the error a file newer than this version
// reads fails with (the tags file is one). The scene format itself and
// its results are the scenes barrel's; the migration steps are internal to
// the formats package.
export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show
        ComponentMigration,
        EntityMigration,
        FieldMigration,
        MigrationHooks,
        UnsupportedFormatVersionException;
