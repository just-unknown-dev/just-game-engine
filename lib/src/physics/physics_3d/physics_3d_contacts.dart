/// The contacts side of `Physics3DSystem`: the world's events turned into
/// the enter, stay and exit events gameplay hears.
library;

import 'package:just_physics_engine/physics_3d.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import '../contact_pairs.dart';
import 'physics_3d_events.dart';

/// What `Physics3DSystem` knows of what its bodies touch — the 3-D twin of
/// the 2-D system's contacts, through the same [ContactPairs] bookkeeping:
/// a body made again sends no second enter, and a body gone for good ends
/// its pairs with no exit.
///
/// Two policies differ from 2-D because the backends do: a stay
/// ([CollisionStay3DEvent]) is the world's own, sent each step while
/// `Physics3D.reportContactStay` asks the world for them, where the 2-D
/// system makes its stays itself; and jointed bodies send their contacts
/// like any others, because Jolt lets jointed bodies collide, where a 2-D
/// joint keeps its bodies apart unless its `collideConnected` is on.
@internal
final class Physics3DContacts {
  /// Contacts in the world [physics] gives, named by [entities].
  /// [isSensor] says whether an entity's rigid body is a sensor.
  Physics3DContacts(this._physics, this.entities, {required this.isSensor});

  final Physics3DWorld Function() _physics;

  /// Each body's entity.
  final Map<int, Entity> entities;

  /// Whether [entity]'s rigid body is a sensor.
  final bool Function(Entity entity) isSensor;

  final ContactPairs<int> _pairs = ContactPairs();

  // The world's events, read into one buffer kept between updates: no
  // object per event, only for the events gameplay is sent.
  final Physics3DEvents _events = Physics3DEvents();

  /// [body]'s contacts end: with no exit when it is gone for good (its
  /// entity destroyed, switched off or without its collider, as Unity
  /// does); when it was [rebuilt], its pairs wait for its new body and what
  /// it touched is woken.
  void forgetBody(int body, Entity entity, {required bool rebuilt}) {
    _pairs.removeBody(
      body,
      rebuilt: rebuilt,
      entity: entity,
      onGone: rebuilt ? (c) => _physics().wake(c.other(body)) : null,
    );
  }

  /// Forgets everything, sending nothing.
  void clear() => _pairs.clear();

  /// Sends the world's events since the last update to [bus]; after a step
  /// ([stepped]), also the exits of pairs a body made again left apart.
  void dispatch(EventBus bus, {required bool stepped}) {
    final events = _events;
    _physics().readEvents(events);
    for (var i = 0; i < events.count; i++) {
      final bodyA = events.bodyAOf(i), bodyB = events.bodyBOf(i);
      switch (events.typeOf(i)) {
        case Physics3DEventType.contactBegin:
          final a = entities[bodyA];
          final b = entities[bodyB];
          if (a == null || b == null) continue; // Not a body it made.
          final contact = _pairs.begin(bodyA, bodyB, a, b, sensor: false);
          if (contact == null || !contact.enters) continue;
          bus.fire(
            CollisionEnter3DEvent(
              entityA: a,
              entityB: b,
              point: _pointOf(i),
              normal: _normalOf(i),
              depth: events.depthOf(i),
            ),
          );
        case Physics3DEventType.contactStay:
          final a = entities[bodyA];
          final b = entities[bodyB];
          if (a == null || b == null) continue;
          bus.fire(
            CollisionStay3DEvent(
              entityA: a,
              entityB: b,
              point: _pointOf(i),
              normal: _normalOf(i),
              depth: events.depthOf(i),
            ),
          );
        case Physics3DEventType.contactEnd:
          // Known by its bodies: a body destroyed since is ended already.
          final contact = _pairs.end(bodyA, bodyB, sensor: false);
          if (contact == null || !contact.exits) continue;
          final pair = contact.entities;
          bus.fire(CollisionExit3DEvent(entityA: pair.a, entityB: pair.b));
        case Physics3DEventType.sensorBegin:
          final a = entities[bodyA];
          final b = entities[bodyB];
          if (a == null || b == null) continue;
          final (sensor, other) = _sensorFirst(a, b);
          final contact = identical(sensor, a)
              ? _pairs.begin(bodyA, bodyB, a, b, sensor: true)
              : _pairs.begin(bodyB, bodyA, b, a, sensor: true);
          if (contact == null || !contact.enters) continue;
          bus.fire(SensorEnter3DEvent(sensor: sensor, other: other));
        case Physics3DEventType.sensorEnd:
          final contact = _pairs.end(bodyA, bodyB, sensor: true);
          if (contact == null || !contact.exits) continue;
          final pair = contact.entities;
          bus.fire(SensorExit3DEvent(sensor: pair.a, other: pair.b));
        case Physics3DEventType.bodyActivated ||
            Physics3DEventType.bodyDeactivated:
          break;
      }
    }
    // Pairs a body made again left apart, and its new body was not found
    // touching: they have parted.
    if (!stepped) return;
    for (final pair in _pairs.settle()) {
      final a = pair.a, b = pair.b;
      if (!a.isAlive || !b.isAlive || !a.isActive || !b.isActive) continue;
      bus.fire(
        pair.sensor
            ? SensorExit3DEvent(sensor: a, other: b)
            : CollisionExit3DEvent(entityA: a, entityB: b),
      );
    }
  }

  /// The [i]th event's point, as the event sent keeps it.
  Vector3 _pointOf(int i) {
    final v = Vector3.zero();
    _events.pointInto(i, v);
    return v;
  }

  /// The [i]th event's normal, as the event sent keeps it.
  Vector3 _normalOf(int i) {
    final v = Vector3.zero();
    _events.normalInto(i, v);
    return v;
  }

  (Entity, Entity) _sensorFirst(Entity a, Entity b) =>
      isSensor(b) && !isSensor(a) ? (b, a) : (a, b);
}
