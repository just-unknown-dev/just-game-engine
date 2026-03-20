/// Physics-related game events published to the [EventBus].
library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Fired when two physics entities collide.
///
/// Subscribe via the world event bus:
/// ```dart
/// world.events.on<CollisionEvent>((e) {
///   print('${e.entityA.id} hit ${e.entityB.id}');
/// });
/// ```
class CollisionEvent extends GameEvent {
  /// First colliding entity.
  final Entity entityA;

  /// Second colliding entity.
  final Entity entityB;

  /// Collision normal pointing from A → B.
  final Offset normal;

  /// Penetration depth.
  final double penetration;

  CollisionEvent({
    required this.entityA,
    required this.entityB,
    required this.normal,
    required this.penetration,
  });
}
