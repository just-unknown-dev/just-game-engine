/// The contacts side of `Physics2DSystem`: the backend's begins and ends
/// turned into the enter, stay and exit events gameplay hears, and the
/// ground each rigid body stands on.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:just_physics_engine/just_physics_engine.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import '../contact_pairs.dart';
import 'physics_2d_components.dart';
import 'physics_2d_events.dart';

/// The narrowest gap between two bodies' shapes: its unit normal, and
/// whether it ends on a face (see `Physics2DContacts._separation`).
typedef _Gap = ({Offset normal, bool onFace});

/// What `Physics2DSystem` knows of what its bodies touch: the pairs of
/// bodies touching or overlapping, and of entities as gameplay was told —
/// what turns the backend's begins and ends into [CollisionEnter2DEvent],
/// [CollisionStay2DEvent], [CollisionExit2DEvent], [SensorEnter2DEvent] and
/// [SensorExit2DEvent], keeps a body made again from sending a second
/// enter, and holds each contact's ground.
@internal
final class Physics2DContacts {
  /// Contacts of [physics]'s bodies, named by [entities].
  Physics2DContacts(this.physics, this.entities);

  /// The physics engine whose contacts these are.
  final Physics2DEngine physics;

  /// Each body's entity.
  final Map<Physics2DBody, Entity> entities;

  final ContactPairs<Physics2DBody> _pairs = ContactPairs();

  // Per-entity count of currently-active ground-normal contacts, so
  // isGrounded stays true for the whole duration a body rests on something
  // (not just the first frame of contact).
  final Map<Entity, int> _groundContactCount = {};

  /// A removed body sends no contact-end events that can still be traced to
  /// an entity, so the contacts it was part of are settled here: whatever it
  /// stood on stops counting, and whatever stood on it loses that ground.
  /// Its pairs of entities end with no exit, unless it was [rebuilt]: then
  /// they wait for its new body ([ContactPairs.removeBody]), and what it
  /// touched is woken, so the next step looks for that body.
  void forgetBody(Physics2DBody body, Entity? entity, {required bool rebuilt}) {
    if (entity != null) _groundContactCount.remove(entity);
    _pairs.removeBody(
      body,
      rebuilt: rebuilt,
      entity: entity,
      onGone: (contact) {
        final grounded = contact.grounded;
        if (grounded != null) {
          _removeGroundContact(contact);
          final rigid = grounded.getComponent<RigidBody2DComponent>();
          if (rigid != null && identical(rigid.groundEntity, entity)) {
            rigid.groundEntity = null;
          }
        }
        if (rebuilt) {
          final other = contact.other(body);
          if (!other.isStatic) physics.wakeBody(other);
        }
      },
    );
  }

  /// Forgets everything, sending nothing.
  void clear() {
    _groundContactCount.clear();
    _pairs.clear();
  }

  /// Sends this update's events to [events]: the begins and ends the
  /// backend reported, then — after a step ([stepped]) and with
  /// [reportStay] — a stay for each pair still touching that touched
  /// before it. An update that ran no step sends no stays: nothing was
  /// simulated.
  void dispatch(
    EventBus events, {
    required bool stepped,
    required bool reportStay,
  }) {
    // Built only for someone to hear: the point a contact is at walks both
    // bodies' shapes.
    final hearsEnter = events.hasListeners<CollisionEnter2DEvent>();

    physics.pollContactBeginEvents((a, b, nx, ny) {
      final entityA = entities[a];
      final entityB = entities[b];
      if (entityA == null || entityB == null) return;
      final contact = _pairs.begin(a, b, entityA, entityB, sensor: false);
      // Another pair of their shapes: they touch already.
      if (contact == null) return;
      contact
        ..nx = nx
        ..ny = ny
        // A body made again picks up its stays where its old one left them.
        ..fresh = contact.enters;

      // Whichever side sits "above" (normal points from A down to B, or
      // from B down to A) is the one resting on the other.
      // The normal points from A to B; the ground's surface normal points
      // from the ground up at whoever stands on it.
      if (ny > 0.5) {
        _addGroundContact(contact, entityA, entityB, Offset(-nx, -ny));
      } else if (ny < -0.5) {
        _addGroundContact(contact, entityB, entityA, Offset(nx, ny));
      }

      if (!contact.enters || !hearsEnter) return;
      events.fire(
        CollisionEnter2DEvent(
          entityA: entityA,
          entityB: entityB,
          point: contactPoint(a, b),
          normal: Offset(nx, ny),
        ),
      );
    });

    physics.pollContactEndEvents((a, b) {
      final contact = _pairs.end(a, b, sensor: false);
      if (contact == null) return;
      _removeGroundContact(contact);
      if (!contact.exits) return;
      final pair = contact.entities;
      events.fire(CollisionExit2DEvent(entityA: pair.a, entityB: pair.b));
    });

    physics.pollSensorBeginEvents((sensorBody, visitorBody) {
      // Two bodies that never move never begin or end touching: the native
      // backend reports a static sensor over a static collider, the
      // pure-Dart one and Jolt do not, and neither does this.
      if (sensorBody.isStatic && visitorBody.isStatic) return;
      final sensor = entities[sensorBody];
      final other = entities[visitorBody];
      if (sensor == null || other == null) return;
      final contact = _pairs.begin(
        sensorBody,
        visitorBody,
        sensor,
        other,
        sensor: true,
      );
      if (contact == null || !contact.enters) return;
      events.fire(SensorEnter2DEvent(sensor: sensor, other: other));
    });

    physics.pollSensorEndEvents((sensorBody, visitorBody) {
      final contact = _pairs.end(sensorBody, visitorBody, sensor: true);
      if (contact == null || !contact.exits) return;
      final pair = contact.entities;
      events.fire(SensorExit2DEvent(sensor: pair.a, other: pair.b));
    });

    // The rest needs a step: nothing has been looked for since the last.
    if (!stepped) return;

    if (!_pairs.isEmpty) {
      _reground();
      if (reportStay) _sendStays(events);
    }

    // Pairs a body made again left apart, and its new body was not found
    // touching: they have parted.
    for (final pair in _pairs.settle()) {
      final a = pair.a, b = pair.b;
      if (!a.isAlive || !b.isAlive || !a.isActive || !b.isActive) continue;
      events.fire(
        pair.sensor
            ? SensorExit2DEvent(sensor: a, other: b)
            : CollisionExit2DEvent(entityA: a, entityB: b),
      );
    }
  }

  /// A stay for every pair that touched before this step and still does —
  /// none for one that began in it (it had its enter) or ended in it (it
  /// has its exit). Built only when someone listens, but each new contact
  /// is aged either way, so a listener coming later hears no stay for a
  /// pair that only just began.
  void _sendStays(EventBus events) {
    final hears = events.hasListeners<CollisionStay2DEvent>();
    for (final contact in _pairs.contacts) {
      if (contact.sensor) continue;
      if (contact.fresh) {
        contact.fresh = false;
        continue;
      }
      if (!hears) continue;
      events.fire(
        CollisionStay2DEvent(
          entityA: contact.entityA,
          entityB: contact.entityB,
          point: contactPoint(contact.a, contact.b),
          normal: Offset(contact.nx, contact.ny),
        ),
      );
    }
  }

  /// How far a body is lifted to see what it rests on: more than the two
  /// backends let resting shapes sink into each other.
  static const double _restProbe = 4.0;

  /// Looks again, from where the two bodies are now, at contacts with a
  /// dynamic rigid body awake on either side — the backends report a
  /// contact's normal only as it begins, so a body that first touched a
  /// crate from the side and then landed on it was never grounded, and one
  /// walking over a curve kept its first touch's normal:
  /// - a contact not yet ground that one body now rests on becomes ground;
  /// - a ground contact takes the normal of the face it rests on now — but
  ///   only a face: where two sharp corners are nearest (where two tiles of
  ///   a ramp meet) the gap between them says nothing of the surface, and
  ///   the normal the contact has is kept;
  /// - nothing stops being ground here: a contact ends as the backend says.
  ///
  /// A body at rest, or one with no rigid body to read, keeps what it had.
  void _reground() {
    Map<Physics2DBody, List<Shape2DProxy>>? proxies;
    List<Shape2DProxy> proxiesOf(
      Physics2DBody body, [
      Offset shift = Offset.zero,
    ]) {
      if (shift != Offset.zero) return body.proxies(shift: shift);
      return (proxies ??= {})[body] ??= body.proxies();
    }

    for (final contact in _pairs.contacts) {
      if (contact.sensor) continue;
      final a = contact.a, b = contact.b;
      if (!_movesItself(a) && !_movesItself(b)) continue;
      if (!_hasRigid(contact.entityA) && !_hasRigid(contact.entityB)) continue;

      // Lifted off the other, a body resting on it is clear of it, the
      // other below: the gap's normal points from it down to the other.
      const lift = Offset(0, -_restProbe);
      final fromA = _separation(proxiesOf(a, lift), proxiesOf(b));
      final Entity grounded, ground;
      final _Gap gap;
      if (fromA != null && fromA.normal.dy > 0.5) {
        grounded = contact.entityA;
        ground = contact.entityB;
        gap = fromA;
      } else {
        final fromB = _separation(proxiesOf(b, lift), proxiesOf(a));
        // Neither rests on the other, or too deep to tell: as it was.
        if (fromB == null || fromB.normal.dy <= 0.5) continue;
        grounded = contact.entityB;
        ground = contact.entityA;
        gap = fromB;
      }
      // The ground's surface normal points up at whoever stands on it.
      final normal = -gap.normal;

      final was = contact.grounded;
      if (was == null) {
        // Ground now: the side it was touched from no longer counts. A
        // corner's normal does not replace one its other ground gave.
        final counted = (_groundContactCount[grounded] ?? 0) > 0;
        _addGroundContact(
          contact,
          grounded,
          ground,
          normal,
          keepSurface: counted && !gap.onFace,
        );
      } else if (identical(was, grounded) && gap.onFace) {
        final rigid = grounded.getComponent<RigidBody2DComponent>();
        if (rigid != null && identical(rigid.groundEntity, ground)) {
          rigid.groundNormal = normal;
        }
      }
    }
  }

  static bool _movesItself(Physics2DBody body) =>
      body.isDynamic && body.isAwake;

  static bool _hasRigid(Entity entity) =>
      entity.hasComponent<RigidBody2DComponent>();

  /// The narrowest gap from shapes [a] to shapes [b]: its unit normal, from
  /// [a] towards [b], and whether it ends on a face of either — not
  /// between two sharp corners, whose gap can point any way. Null when any
  /// of their cores overlap (no gap to tell by) or either has none.
  static _Gap? _separation(List<Shape2DProxy> a, List<Shape2DProxy> b) {
    if (a.isEmpty || b.isEmpty) return null;
    _Gap? best;
    var bestDistance = double.infinity;
    for (final pa in a) {
      for (final pb in b) {
        final d = Shape2DDistance.between(pa, pb);
        if (d.overlaps) return null;
        final gap = d.distance - pa.radius - pb.radius;
        if (gap < bestDistance) {
          bestDistance = gap;
          best = (
            normal: d.normal,
            onFace: !_sharpCorner(pa, d.pointA) || !_sharpCorner(pb, d.pointB),
          );
        }
      }
    }
    return best;
  }

  /// Whether [point] on [proxy]'s core is one of its corners, and a sharp
  /// one: not rounded off by a radius (a circle, a capsule's end).
  static bool _sharpCorner(Shape2DProxy proxy, Offset point) {
    if (proxy.radius > 0.5) return false;
    for (final corner in proxy.points) {
      if ((corner - point).distanceSquared < 1e-6) return true;
    }
    return false;
  }

  /// Where [a] and [b] touch, as near as their bounds tell: the middle of
  /// where the two boxes round them meet (neither physics backend reports a
  /// contact's point in 2-D).
  static Offset contactPoint(Physics2DBody a, Physics2DBody b) {
    final ra = a.boundsAt(Offset(a.position.x, a.position.y)).inflate(0.5);
    final rb = b.boundsAt(Offset(b.position.x, b.position.y)).inflate(0.5);
    final left = math.max(ra.left, rb.left),
        right = math.min(ra.right, rb.right);
    final top = math.max(ra.top, rb.top),
        bottom = math.min(ra.bottom, rb.bottom);
    if (left <= right && top <= bottom) {
      return Offset((left + right) / 2, (top + bottom) / 2);
    }
    return (ra.center + rb.center) / 2;
  }

  /// [contact] is ground: [grounded] stands on [ground], whose surface
  /// has [surfaceNormal] there — unless [keepSurface], when the ground and
  /// normal [grounded] already has are kept.
  void _addGroundContact(
    BodyContact<Physics2DBody> contact,
    Entity grounded,
    Entity ground,
    Offset surfaceNormal, {
    bool keepSurface = false,
  }) {
    contact.grounded = grounded;
    final count = (_groundContactCount[grounded] ?? 0) + 1;
    _groundContactCount[grounded] = count;
    final rigid = grounded.getComponent<RigidBody2DComponent>();
    if (rigid == null) return;
    rigid.isGrounded = true;
    if (keepSurface) return;
    // Recorded so a rider can inherit a moving platform's velocity. With
    // several ground contacts at once the most recent wins, which is the
    // right answer when stepping from static ground onto a platform — and
    // from flat ground onto a slope.
    rigid.groundEntity = ground;
    rigid.groundNormal = surfaceNormal;
  }

  void _removeGroundContact(BodyContact<Physics2DBody> contact) {
    final grounded = contact.grounded;
    if (grounded == null) return;
    contact.grounded = null;
    final count = (_groundContactCount[grounded] ?? 1) - 1;
    if (count <= 0) {
      _groundContactCount.remove(grounded);
      final rigid = grounded.getComponent<RigidBody2DComponent>();
      if (rigid != null) {
        rigid.isGrounded = false;
        rigid.groundEntity = null;
        rigid.groundNormal = const Offset(0, -1);
      }
    } else {
      _groundContactCount[grounded] = count;
    }
  }
}
