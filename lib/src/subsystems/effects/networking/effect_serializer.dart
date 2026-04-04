part of '../effect_system.dart';

/// JSON serialiser for [DeterministicEffect] instances.
///
/// Maintains a static factory registry keyed by [DeterministicEffect.effectType].
/// To register a custom effect type call [registerFactory] at startup.
///
/// ```dart
/// // Encode:
/// final map = EffectSerializer().encodeEffect(myEffect);
///
/// // Decode:
/// final effect = EffectSerializer().decodeEffect(map);
/// ```
class EffectSerializer {
  static final Map<String, DeterministicEffect Function(Map<String, dynamic>)>
  _factories = {
    'move': MoveEffect._fromJson,
    'scale': ScaleEffect._fromJson,
    'rotate': RotateEffect._fromJson,
    'fade': FadeEffect._fromJson,
    'colorTint': ColorTintEffect._fromJson,
    'sequence': SequenceEffect._fromJson,
    'parallel': ParallelEffect._fromJson,
    'delay': DelayEffect._fromJson,
    'repeat': RepeatEffect._fromJson,
    'shake': ShakeEffect._fromJson,
    'path': PathEffect._fromJson,
  };

  /// Register a factory for a custom [DeterministicEffect] subtype.
  ///
  /// The [typeKey] must match the subtype's [DeterministicEffect.effectType].
  static void registerFactory(
    String typeKey,
    DeterministicEffect Function(Map<String, dynamic>) factory,
  ) {
    _factories[typeKey] = factory;
  }

  /// Encode [effect] to a JSON-compatible map (adds the `'type'` discriminator).
  Map<String, dynamic> encodeEffect(DeterministicEffect effect) => {
    'type': effect.effectType,
    ...effect.toJson(),
  };

  /// Decode a [DeterministicEffect] from a JSON map produced by [encodeEffect].
  ///
  /// Throws [ArgumentError] if the `'type'` key is missing or unknown.
  DeterministicEffect decodeEffect(Map<String, dynamic> map) {
    final type = map['type'] as String?;
    if (type == null) throw ArgumentError("Effect map missing 'type' key");
    final factory = _factories[type];
    if (factory == null) throw ArgumentError("Unknown effect type: '$type'");
    return factory(map);
  }

  /// Encode a full [EffectSnapshot] to a JSON string.
  String encodeSnapshot(EffectSnapshot snapshot) =>
      jsonEncode(snapshot.toJson());

  /// Decode a full [EffectSnapshot] from a JSON string.
  EffectSnapshot decodeSnapshot(String json) =>
      EffectSnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
