library;

import 'component_definition_registry.dart';
import 'core_component_schemas.dart';
import 'core_definitions.dart';

/// Registers every component the engine itself defines, one definition
/// each. The definition is the wire codec: what it encodes is scene format
/// v1, and a v0 file is migrated on load.
///
/// Never overrides. Call it as often as you like; a project's replacement
/// for a built-in, registered before or after, stays in place. (It used to
/// be re-run lazily by the editor and clobbered exactly such overrides.)
void registerCoreCodecs([ComponentDefinitionRegistry? registry]) {
  (registry ?? ComponentDefinitionRegistry.instance)
    ..registerAll(CoreDefinitions.all, ifAbsent: true)
    ..registerAll(CoreComponentSchemas.all, ifAbsent: true);
}

/// The same registration, under the name that says what it does now.
void registerCoreDefinitions([ComponentDefinitionRegistry? registry]) =>
    registerCoreCodecs(registry);
