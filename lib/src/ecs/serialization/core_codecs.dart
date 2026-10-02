library;

import 'component_definition_registry.dart';
import 'core_component_schemas.dart';
import 'core_definitions.dart';

/// Registers every component the engine itself defines into [registry],
/// one definition each. The definition is the wire codec: what it encodes is
/// scene format v1, and a v0 file is migrated on load.
///
/// Never overrides. Call it as often as you like; a project's replacement
/// for a built-in, registered before or after, stays in place.
///
/// Every `EngineContext` does this for its own registry, so a game never
/// needs to (`world.context.definitions` has the core definitions already);
/// [ComponentDefinitionRegistry.core] makes a fresh registry with them.
void registerCoreCodecs(ComponentDefinitionRegistry registry) {
  registry
    ..registerAll(CoreDefinitions.all, ifAbsent: true)
    ..registerAll(CoreComponentSchemas.all, ifAbsent: true);
}
