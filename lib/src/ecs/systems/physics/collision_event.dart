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

  /// Approximate world-space contact point (midpoint of the two bodies
  /// projected half-penetration along the normal).
  final Offset contactPoint;

  CollisionEvent({
    required this.entityA,
    required this.entityB,
    required this.normal,
    required this.penetration,
    this.contactPoint = Offset.zero,
  });
}

/// Fired when two physics entities that were colliding stop overlapping.
///
/// Subscribe via the world event bus:
/// ```dart
/// world.events.on<ContactExitEvent>((e) {
///   print('${e.entityA.id} separated from ${e.entityB.id}');
/// });
/// ```
class ContactExitEvent extends GameEvent {
  final Entity entityA;
  final Entity entityB;

  ContactExitEvent({required this.entityA, required this.entityB});
}
