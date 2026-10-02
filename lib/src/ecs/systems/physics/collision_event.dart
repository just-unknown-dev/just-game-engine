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

  /// Always 0 from `PhysicsSystem`: no physics backend reports a contact's
  /// penetration depth with it.
  @Deprecated(
    'Always 0: no physics backend reports penetration depth with a '
    'contact. Work it out from the shapes of the two bodies if you need it; '
    'this field will be removed.',
  )
  final double penetration;

  /// Always [Offset.zero] from `PhysicsSystem`: no physics backend reports
  /// where a contact is.
  @Deprecated(
    'Always Offset.zero: no physics backend reports the contact point. '
    'This field will be removed.',
  )
  final Offset contactPoint;

  /// A collision between [entityA] and [entityB] along [normal].
  CollisionEvent({
    required this.entityA,
    required this.entityB,
    required this.normal,
    @Deprecated(
      'Always 0 from PhysicsSystem; leave it out. It will be removed.',
    )
    this.penetration = 0.0,
    @Deprecated(
      'Always Offset.zero from PhysicsSystem; leave it out. It will be '
      'removed.',
    )
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
  /// One of the two entities that stopped touching.
  final Entity entityA;

  /// The other entity.
  final Entity entityB;

  /// [entityA] and [entityB] have stopped touching.
  ContactExitEvent({required this.entityA, required this.entityB});
}
