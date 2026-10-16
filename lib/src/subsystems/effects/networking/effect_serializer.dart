part of '../effect_system.dart';

/// Reads one effect from its saved form; [serializer] reads any effects
/// nested in it.
typedef EffectDecoder =
    DeterministicEffect Function(
      Map<String, dynamic> json,
      EffectSerializer serializer,
    );

/// The effect types that can be read back, keyed by
/// [DeterministicEffect.effectType]. The engine's eleven are always there;
/// a game registers its own into an engine's (`engine.context.effectTypes`).
/// [builtIn] holds only the engine's and cannot be changed.
final class EffectTypes {
  /// The engine's types (unless [withBuiltIns] is false), to add to.
  EffectTypes({bool withBuiltIns = true}) : _frozen = false {
    if (withBuiltIns) _decoders.addAll(_engine);
  }

  EffectTypes._frozen() : _frozen = true {
    _decoders.addAll(_engine);
  }

  /// The engine's types and nothing else. Read-only: [register] throws.
  static final EffectTypes builtIn = EffectTypes._frozen();

  static final Map<String, EffectDecoder> _engine = {
    'move': (json, _) => MoveEffect._fromJson(json),
    'scale': (json, _) => ScaleEffect._fromJson(json),
    'rotate': (json, _) => RotateEffect._fromJson(json),
    'fade': (json, _) => FadeEffect._fromJson(json),
    'colorTint': (json, _) => ColorTintEffect._fromJson(json),
    'sequence': SequenceEffect._fromJson,
    'parallel': ParallelEffect._fromJson,
    'delay': (json, _) => DelayEffect._fromJson(json),
    'repeat': RepeatEffect._fromJson,
    'shake': (json, _) => ShakeEffect._fromJson(json),
    'path': (json, _) => PathEffect._fromJson(json),
  };

  final bool _frozen;
  final Map<String, EffectDecoder> _decoders = {};

  /// Reads effects of [typeKey] — a [DeterministicEffect.effectType] — with
  /// [decode], replacing any reader for it.
  void register(String typeKey, EffectDecoder decode) {
    if (_frozen) {
      throw UnsupportedError(
        "EffectTypes.builtIn cannot be changed: register into an engine's "
        '(engine.context.effectTypes).',
      );
    }
    _decoders[typeKey] = decode;
  }

  /// The reader for [typeKey], or null.
  EffectDecoder? decoderFor(String typeKey) => _decoders[typeKey];
}

/// JSON serialiser for [DeterministicEffect] instances.
///
/// Reads the types in [types] — the engine's own ([EffectTypes.builtIn])
/// when none are given; an [EffectSystemECS] reads with its world's
/// (`world.context.effectTypes`).
///
/// ```dart
/// // Encode:
/// final map = EffectSerializer().encodeEffect(myEffect);
///
/// // Decode:
/// final effect = EffectSerializer(engine.context.effectTypes).decodeEffect(map);
/// ```
class EffectSerializer {
  /// A serialiser reading the effect types in [types]; only the engine's
  /// own ([EffectTypes.builtIn]) when null.
  EffectSerializer([EffectTypes? types]) : types = types ?? EffectTypes.builtIn;

  /// What it can read back.
  final EffectTypes types;

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
    final decode = types.decoderFor(type);
    if (decode == null) throw ArgumentError("Unknown effect type: '$type'");
    return decode(map, this);
  }

  /// Encode a full [EffectSnapshot] to a JSON string.
  String encodeSnapshot(EffectSnapshot snapshot) =>
      jsonEncode(snapshot.toJson());

  /// Decode a full [EffectSnapshot] from a JSON string.
  EffectSnapshot decodeSnapshot(String json) =>
      EffectSnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
