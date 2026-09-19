library;

import '../ecs.dart';

/// Converts one component type to and from JSON.
///
/// Codecs are what let a level authored in the editor load in a shipped game
/// with no editor present. Each lives in the package that owns its component
/// — the engine for core types, a genre kit for its own, a game for its
/// components — so the runtime never depends on design-time code.
///
/// The editor serializes through the same registry, which is the point: the
/// editor and the game share one codec per type, so they cannot disagree
/// about what a saved level means.
abstract class ComponentCodec<T extends Component> {
  const ComponentCodec();

  /// The `type` string written to JSON. Stable: changing it orphans every
  /// saved level that used the old name.
  String get type;

  /// The Dart type this codec handles.
  ///
  /// Used for lookup rather than `runtimeType.toString()`, which is minified
  /// in release web builds and would not match [type].
  Type get componentType => T;

  /// Whether [component] is one this codec handles.
  bool handles(Component component) => component is T;

  /// Encodes [component]. The result must include `'type': type`.
  Map<String, dynamic> encode(T component);

  /// Decodes a component from JSON previously produced by [encode].
  ///
  /// Should tolerate missing keys by falling back to defaults — older saves
  /// predate fields added since.
  T decode(Map<String, dynamic> json);

  /// [encode] for a component typed only as [Component].
  Map<String, dynamic> encodeAny(Component component) => encode(component as T);
}

/// Thrown when a level contains a component no registered codec understands.
///
/// Loading fails loudly on purpose. The alternative — skipping it — is how
/// levels used to lose platforms, hazards and checkpoints without a single
/// error: the entity loaded, looked right, and did nothing.
class UnknownComponentTypeException implements Exception {
  UnknownComponentTypeException(this.type, {this.entityName});

  /// The unrecognised `type` string.
  final String type;

  /// The entity it was attached to, when known.
  final String? entityName;

  @override
  String toString() =>
      'UnknownComponentTypeException: no codec registered for "$type"'
      '${entityName == null ? '' : ' (on entity "$entityName")'}. '
      'Register one with ComponentCodecRegistry.instance.register, or call '
      'the owning package\'s registerCodecs() before loading.';
}
