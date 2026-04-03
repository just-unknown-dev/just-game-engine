part of '../effect_system.dart';

/// A serialisable point-in-time snapshot of all active effects across all
/// entities.
///
/// Suitable for network transmission (late-join, reconnect) and for
/// prediction-rollback checkpoints.  Convert to JSON with
/// [EffectSnapshot.toJson] or to compact bytes with [EffectBinaryCodec].
class EffectSnapshot {
  /// The absolute tick count at which this snapshot was captured.
  final int tick;

  /// Map from [EntityId] to the JSON-encoded list of in-flight effects,
  /// as produced by [EffectPlayer.toJson].
  final Map<EntityId, List<Map<String, dynamic>>> entityEffects;

  const EffectSnapshot({required this.tick, required this.entityEffects});

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'tick': tick,
    'entities': entityEffects.map(
      (id, effects) => MapEntry(id.toString(), effects),
    ),
  };

  /// Deserialise from a JSON-compatible map.
  factory EffectSnapshot.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entities'] as Map<String, dynamic>;
    return EffectSnapshot(
      tick: json['tick'] as int,
      entityEffects: rawEntities.map(
        (idStr, raw) => MapEntry(
          int.parse(idStr),
          (raw as List).cast<Map<String, dynamic>>(),
        ),
      ),
    );
  }
}
