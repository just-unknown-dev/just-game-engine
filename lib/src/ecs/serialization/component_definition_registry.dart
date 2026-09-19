library;

import '../ecs.dart';
import 'component_codec.dart';
import 'component_definition.dart';

/// Every component the engine can save, load, inspect, size and draw, keyed
/// by type name, alias and Dart type.
///
/// Holds two kinds of entry. A [ComponentDefinition] describes a component
/// fully and is normally also its wire codec. A plain [ComponentCodec]
/// registered for the same type takes over *only* the wire format — how the
/// engine keeps reading and writing its older hand-written JSON shapes for
/// the core components while their definitions drive everything else.
///
/// Registration never clobbers silently: re-registering the same instance is
/// a no-op, a different one for the same type throws unless `override` is
/// passed. A project's replacement for a built-in therefore stays replaced.
class ComponentDefinitionRegistry {
  ComponentDefinitionRegistry();

  /// Process-wide registry. Goes away once every registry is owned by an
  /// editor scope; kept so existing boot code keeps working.
  static final ComponentDefinitionRegistry instance =
      ComponentDefinitionRegistry();

  final Map<String, ComponentDefinition> _definitions = {};
  final Map<Type, ComponentDefinition> _definitionsByType = {};
  final Map<String, ComponentCodec> _wire = {};
  final Map<Type, ComponentCodec> _wireByType = {};
  final Map<String, String> _aliases = {};

  /// Registers [codec] — a definition, or a plain codec that becomes the
  /// wire format for its type.
  void register(ComponentCodec codec, {bool override = false}) {
    if (codec is ComponentDefinition) {
      _put(_definitions, _definitionsByType, codec, override);
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
    byName[codec.type] = codec;
    byType[codec.componentType] = codec;
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
      if (ifAbsent && _has(codec)) continue;
      register(codec, override: override);
    }
  }

  bool _has(ComponentCodec codec) => codec is ComponentDefinition
      ? _definitions.containsKey(codec.type)
      : _wire.containsKey(codec.type);

  /// Forgets everything registered under [type] (definition and wire codec).
  void unregister(String type) {
    final d = _definitions.remove(type);
    if (d != null) {
      _definitionsByType.remove(d.componentType);
      _aliases.removeWhere((_, target) => target == type);
    }
    final w = _wire.remove(type);
    if (w != null) _wireByType.remove(w.componentType);
  }

  /// Removes every registration. Mainly for tests.
  void clear() {
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

  String _canonical(String typeOrAlias) => _aliases[typeOrAlias] ?? typeOrAlias;

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

/// The name this registry had while it only held codecs.
typedef ComponentCodecRegistry = ComponentDefinitionRegistry;
