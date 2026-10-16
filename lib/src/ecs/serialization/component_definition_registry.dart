library;

import '../ecs.dart';
import 'component_codec.dart';
import 'component_definition.dart';
import 'core_codecs.dart';

/// Every component the engine can save, load, inspect, size and draw, keyed
/// by type name, alias and Dart type.
///
/// Holds two kinds of entry. A [ComponentDefinition] describes a component
/// fully and is normally also its wire codec — the engine's own components
/// are all saved that way. A plain [ComponentCodec] registered for the same
/// type takes over *only* the wire format: how a package keeps its own JSON
/// shape for a type while the definition drives everything else.
///
/// Registration never clobbers silently: re-registering the same instance is
/// a no-op, a different one for the same type throws unless `override` is
/// passed. A project's replacement for a built-in therefore stays replaced.
///
/// There is no process-wide registry: each engine's is its context's
/// (`engine.context.definitions`, `world.context.definitions`).
class ComponentDefinitionRegistry {
  /// An empty registry.
  ComponentDefinitionRegistry();

  /// A fresh registry holding the engine's own definitions — what every
  /// `EngineContext` starts from.
  factory ComponentDefinitionRegistry.core() {
    final registry = ComponentDefinitionRegistry();
    registerCoreCodecs(registry);
    return registry;
  }

  final Map<String, ComponentDefinition> _definitions = {};
  final Map<Type, ComponentDefinition> _definitionsByType = {};
  final Map<String, ComponentCodec> _wire = {};
  final Map<Type, ComponentCodec> _wireByType = {};
  final Map<String, String> _aliases = {};

  /// Types whose registration a project chose on purpose — with `override`,
  /// or by being there first when an `ifAbsent` registration came — and
  /// which [refresh] therefore leaves alone.
  final Set<String> _kept = {};

  /// Types whose registration came from `registerAll(ifAbsent: true)` — a
  /// built-in default, which another such registration finding it in place
  /// does not mark as [_kept].
  final Set<String> _defaults = {};

  int _revision = 0;

  /// Moves on whenever a definition or codec is registered, replaced or
  /// removed — for a cache of what the definitions say (which component
  /// types have an extent, say) to know when to look again.
  int get revision => _revision;

  /// Registers [codec] — a definition, or a plain codec that becomes the
  /// wire format for its type.
  void register(ComponentCodec codec, {bool override = false}) {
    _register(codec, override: override);
    _defaults.remove(codec.type);
  }

  void _register(ComponentCodec codec, {required bool override}) {
    if (override) _kept.add(codec.type);
    if (codec is ComponentDefinition) {
      final replaced = _definitions[codec.type];
      _put(_definitions, _definitionsByType, codec, override);
      if (replaced != null && !identical(replaced, codec)) {
        _aliases.removeWhere((_, target) => target == codec.type);
      }
      for (final alias in codec.aliases) {
        _aliases[alias] = codec.type;
      }
    } else {
      _put(_wire, _wireByType, codec, override);
    }
  }

  void _put<C extends ComponentCodec>(
    Map<String, C> byName,
    Map<Type, C> byType,
    C codec,
    bool override,
  ) {
    final existing = byName[codec.type];
    if (existing != null && !identical(existing, codec) && !override) {
      throw StateError(
        'A ${existing.runtimeType} is already registered for '
        '"${codec.type}". Pass override: true to replace it, or use '
        'registerAll(ifAbsent: true) to keep what is there.',
      );
    }
    // A replacement for another Dart type must not leave the old type
    // still pointing at the definition it replaced.
    if (existing != null &&
        !identical(existing, codec) &&
        identical(byType[existing.componentType], existing)) {
      byType.remove(existing.componentType);
    }
    byName[codec.type] = codec;
    byType[codec.componentType] = codec;
    _revision++;
  }

  /// Registers several codecs. With [ifAbsent], types already registered
  /// are left as they are — for core registrations that must never undo a
  /// project's override.
  void registerAll(
    Iterable<ComponentCodec> codecs, {
    bool override = false,
    bool ifAbsent = false,
  }) {
    for (final codec in codecs) {
      if (ifAbsent && _has(codec)) {
        // Someone else's is in place, and is to stay in place — unless it
        // is a default too (the same built-ins registered again), which a
        // refresh may still replace.
        if (!identical(_existing(codec), codec) &&
            !_defaults.contains(codec.type)) {
          _kept.add(codec.type);
        }
        continue;
      }
      _register(codec, override: override);
      if (ifAbsent) {
        _defaults.add(codec.type);
      } else {
        _defaults.remove(codec.type);
      }
    }
  }

  bool _has(ComponentCodec codec) => codec is ComponentDefinition
      ? _definitions.containsKey(codec.type)
      : _wire.containsKey(codec.type);

  ComponentCodec? _existing(ComponentCodec codec) =>
      codec is ComponentDefinition
      ? _definitions[codec.type]
      : _wire[codec.type];

  /// Puts [codecs] in place as the code now makes them — for a hot reload,
  /// where definitions built again from edited code take the place of the
  /// ones the engine was booted with, so what reads them (an editor's
  /// inspector, a scene codec) sees the new fields.
  ///
  /// A type not yet registered is added; one that is, replaced, with its
  /// aliases. A type a project replaced on purpose stays as the project has
  /// it, unless [override] — which the project's own refresh passes.
  ///
  /// A game never needs this: it registers once, at boot.
  void refresh(Iterable<ComponentCodec> codecs, {bool override = false}) {
    for (final codec in codecs) {
      final old = _existing(codec);
      if (identical(old, codec)) continue;
      if (old != null && !override && _kept.contains(codec.type)) continue;
      _revision++;
      if (codec is ComponentDefinition) {
        if (old != null &&
            identical(_definitionsByType[old.componentType], old)) {
          _definitionsByType.remove(old.componentType);
        }
        _aliases.removeWhere((_, target) => target == codec.type);
        _definitions[codec.type] = codec;
        _definitionsByType[codec.componentType] = codec;
        for (final alias in codec.aliases) {
          _aliases[alias] = codec.type;
        }
      } else {
        if (old != null && identical(_wireByType[old.componentType], old)) {
          _wireByType.remove(old.componentType);
        }
        _wire[codec.type] = codec;
        _wireByType[codec.componentType] = codec;
      }
    }
  }

  /// Forgets everything registered under [type] (definition and wire codec).
  void unregister(String type) {
    _revision++;
    final d = _definitions.remove(type);
    if (d != null) {
      _unindex(_definitionsByType, _definitions.values, d);
      _aliases.removeWhere((_, target) => target == type);
    }
    final w = _wire.remove(type);
    if (w != null) _unindex(_wireByType, _wire.values, w);
    _kept.remove(type);
    _defaults.remove(type);
  }

  /// Drops [gone] from [byType] when it is what its Dart type points at,
  /// handing the Dart type to another registration of it, if any.
  static void _unindex<C extends ComponentCodec>(
    Map<Type, C> byType,
    Iterable<C> remaining,
    C gone,
  ) {
    if (!identical(byType[gone.componentType], gone)) return;
    byType.remove(gone.componentType);
    for (final other in remaining) {
      if (other.componentType == gone.componentType) {
        byType[gone.componentType] = other;
        break;
      }
    }
  }

  /// Removes every registration. Mainly for tests.
  void clear() {
    _revision++;
    _kept.clear();
    _defaults.clear();
    _definitions.clear();
    _definitionsByType.clear();
    _wire.clear();
    _wireByType.clear();
    _aliases.clear();
  }

  /// Every registered type name.
  Iterable<String> get types => {..._definitions.keys, ..._wire.keys};

  /// Every definition.
  Iterable<ComponentDefinition> get definitions => _definitions.values;

  /// A registered type name is itself, even where an alias of another
  /// type has the same spelling; otherwise the alias's type.
  String _canonical(String typeOrAlias) =>
      _definitions.containsKey(typeOrAlias) || _wire.containsKey(typeOrAlias)
      ? typeOrAlias
      : _aliases[typeOrAlias] ?? typeOrAlias;

  /// The definition for a type name or alias, or null.
  ComponentDefinition? definitionByType(String typeOrAlias) =>
      _definitions[_canonical(typeOrAlias)];

  /// The definition for [component]'s exact type, or null.
  ///
  /// Exact on purpose. A subclass of a defined component is *not* its base:
  /// encoding it as the base would drop the subclass's fields. Define the
  /// subclass with [ComponentDefinition.extend].
  ComponentDefinition? definitionFor(Component component) =>
      _definitionsByType[component.runtimeType];

  /// The wire codec for a type name or alias: a plain codec if one was
  /// registered, else the definition.
  ComponentCodec? byName(String typeOrAlias) {
    final type = _canonical(typeOrAlias);
    return _wire[type] ?? _definitions[type];
  }

  /// The wire codec for [component]'s exact type, or null.
  ComponentCodec? forComponent(Component component) =>
      _wireByType[component.runtimeType] ??
      _definitionsByType[component.runtimeType];

  /// The nearest registered codec whose type [component] `is`, for telling a
  /// user *which* base their undefined subclass would otherwise save as.
  ComponentCodec? nearestFor(Component component) {
    for (final codec in [..._definitions.values, ..._wire.values]) {
      if (codec.handles(component)) return codec;
    }
    return null;
  }

  /// Whether [component] can be saved.
  bool canEncode(Component component) => forComponent(component) != null;

  /// Encodes [component], or returns null if nothing handles its type.
  Map<String, dynamic>? encode(Component component) =>
      forComponent(component)?.encodeAny(component);

  /// Decodes [json], or returns null if its type is unregistered.
  Component? decode(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) return null;
    return byName(type)?.decode(json);
  }
}
