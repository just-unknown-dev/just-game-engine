/// What 2-D bodies do to each other, on the world's event bus — the same
/// events, with the same fields, as the 3-D ones
/// (`CollisionEnter3DEvent` and the rest).
///
/// ```dart
/// world.events.on<CollisionEnter2DEvent>((e) {
///   print('${e.entityA.name} hit ${e.entityB.name}');
/// });
/// world.events.on<SensorEnter2DEvent>((e) {
///   print('${e.other.name} entered ${e.sensor.name}');
/// });
/// ```
library;

import 'dart:ui' show Offset;

import '../../ecs.dart';

/// Two bodies have begun touching.
class CollisionEnter2DEvent extends GameEvent {
  /// [entityA] and [entityB] touching at [point], [normal] pointing from A
  /// towards B.
  CollisionEnter2DEvent({
    required this.entityA,
    required this.entityB,
    required this.point,
    required this.normal,
    this.depth = 0,
  });

  /// One of the two.
  final Entity entityA;

  /// The other.
  final Entity entityB;

  /// Where they touch, in the world. The physics backends do not report
  /// it in 2-D, so it is worked out from where the two bodies' bounds meet.
  final Offset point;

  /// The contact's normal, pointing from [entityA] towards [entityB].
  final Offset normal;

  /// How far they overlap; 0 where the backend does not say (both do not,
  /// in 2-D).
  final double depth;
}

/// Two bodies are still touching, each step after [CollisionEnter2DEvent]
/// — only when `PhysicsSystem.reportContactStay` is on.
class CollisionStay2DEvent extends GameEvent {
  /// [entityA] and [entityB] still touching.
  CollisionStay2DEvent({
    required this.entityA,
    required this.entityB,
    required this.point,
    required this.normal,
    this.depth = 0,
  });

  /// One of the two.
  final Entity entityA;

  /// The other.
  final Entity entityB;

  /// Where they touch (see [CollisionEnter2DEvent.point]).
  final Offset point;

  /// The contact's normal, pointing from [entityA] towards [entityB].
  final Offset normal;

  /// How far they overlap (see [CollisionEnter2DEvent.depth]).
  final double depth;
}

/// Two bodies have stopped touching.
class CollisionExit2DEvent extends GameEvent {
  /// [entityA] and [entityB] apart.
  CollisionExit2DEvent({required this.entityA, required this.entityB});

  /// One of the two.
  final Entity entityA;

  /// The other.
  final Entity entityB;
}

/// Something has entered a sensor (a body with `RigidBody2D.isSensor`).
class SensorEnter2DEvent extends GameEvent {
  /// [other] entering [sensor].
  SensorEnter2DEvent({required this.sensor, required this.other});

  /// The sensor.
  final Entity sensor;

  /// What entered it.
  final Entity other;
}

/// Something has left a sensor.
class SensorExit2DEvent extends GameEvent {
  /// [other] leaving [sensor].
  SensorExit2DEvent({required this.sensor, required this.other});

  /// The sensor.
  final Entity sensor;

  /// What left it.
  final Entity other;
}
