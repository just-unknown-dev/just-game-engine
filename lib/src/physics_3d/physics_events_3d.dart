import 'package:just_game_engine/just_game_engine.dart';

/// Two entities' bodies started touching. Fired on the world's event bus by
/// [PhysicsSystem3D] after the step:
///
/// ```dart
/// world.events.on<CollisionEnter3DEvent>((e) {
///   print('${e.entityA.name} hit ${e.entityB.name}');
/// });
/// ```
class CollisionEnter3DEvent extends GameEvent {
  /// [entityA] touched [entityB] at [point].
  CollisionEnter3DEvent({
    required this.entityA,
    required this.entityB,
    required this.point,
    required this.normal,
    this.depth = 0,
  });

  /// One entity.
  final Entity entityA;

  /// The other.
  final Entity entityB;

  /// Where they touch, in metres.
  final Vector3 point;

  /// From A towards B.
  final Vector3 normal;

  /// How far they overlap.
  final double depth;
}

/// Two entities' bodies are still touching after a step. Only fired when
/// the service was made with `reportContactStay: true`.
class CollisionStay3DEvent extends GameEvent {
  /// [entityA] still touches [entityB].
  CollisionStay3DEvent({
    required this.entityA,
    required this.entityB,
    required this.point,
    required this.normal,
    this.depth = 0,
  });

  /// One entity.
  final Entity entityA;

  /// The other.
  final Entity entityB;

  /// Where they touch.
  final Vector3 point;

  /// From A towards B.
  final Vector3 normal;

  /// How far they overlap.
  final double depth;
}

/// Two entities' bodies stopped touching.
class CollisionExit3DEvent extends GameEvent {
  /// [entityA] and [entityB] are apart.
  CollisionExit3DEvent({required this.entityA, required this.entityB});

  /// One entity.
  final Entity entityA;

  /// The other.
  final Entity entityB;
}

/// Something entered a sensor (a [RigidBody3D] with `isSensor`): a body,
/// or a detectable character.
class SensorEnter3DEvent extends GameEvent {
  /// [other] entered [sensor].
  SensorEnter3DEvent({required this.sensor, required this.other});

  /// The sensor's entity.
  final Entity sensor;

  /// What entered it.
  final Entity other;
}

/// Something left a sensor.
class SensorExit3DEvent extends GameEvent {
  /// [other] left [sensor].
  SensorExit3DEvent({required this.sensor, required this.other});

  /// The sensor's entity.
  final Entity sensor;

  /// What left it.
  final Entity other;
}
