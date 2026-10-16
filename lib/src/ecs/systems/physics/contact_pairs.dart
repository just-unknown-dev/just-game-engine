/// The bookkeeping that turns a physics backend's begin and end reports into
/// the enters and exits gameplay sees: shared by the 2-D and 3-D physics
/// systems, and not part of the public API.
library;

import '../../ecs.dart';

/// Two bodies touching, as the backend reported: begun and not yet ended.
final class BodyContact<B extends Object> {
  BodyContact._(this.a, this.b, this.entityA, this.entityB, this.entities);

  /// The bodies, in the order the backend first named them.
  final B a, b;

  /// Their entities, in the same order.
  final Entity entityA, entityB;

  /// The pair of entities this contact keeps touching.
  final EntityContact entities;

  /// Whether one of the bodies is a sensor: an overlap, not a contact.
  bool get sensor => entities.sensor;

  /// Begins not yet ended — more than one where a backend reports each pair
  /// of shapes on its own.
  int _count = 1;

  /// Whether the begin that made this contact made its [entities] touch: an
  /// enter to send. Read right after [ContactPairs.begin].
  bool enters = false;

  /// Whether the end that took this contact away left its [entities] apart:
  /// an exit to send. Read right after [ContactPairs.end].
  bool exits = false;

  /// Began in the last step: sent no stay yet (the 2-D system's stays).
  bool fresh = true;

  /// The normal it began with (the 2-D system's stays).
  double nx = 0, ny = 0;

  /// The entity it holds up, if it is ground to one (the 2-D system).
  Entity? grounded;

  /// The body on the other side from [body].
  B other(B body) => body == a ? b : a;
}

/// Two entities touching, as gameplay was told: entered and not yet exited.
final class EntityContact {
  EntityContact._(this.a, this.b, this.sensor)
    : _key = _EntityKey(a, b, sensor);

  /// The entities, in the order the enter named them: for a sensor, the
  /// sensor first.
  final Entity a, b;

  /// Whether it is a sensor's overlap rather than a contact.
  final bool sensor;

  final _EntityKey _key;

  /// Body contacts keeping it.
  int _count = 0;

  /// Left with none by a body made again: an exit unless the new body is
  /// found touching after the next step ([ContactPairs.settle]).
  bool _orphaned = false;
}

/// The body contacts a backend reported and the entity contacts they make.
///
/// A body is made again — a changed shape, scale or sensor flag — by
/// destroying it and making a new one. Backends report no end for a body
/// they no longer know (or one for a body the system no longer knows), and
/// a begin for the new one: told straight on, gameplay saw a second enter
/// with no exit between. Here a body made again leaves its pairs of
/// entities waiting instead, and the begins of its new body pick them up
/// again with nothing sent; only a pair the new body is not found touching
/// after the next step exits ([settle]).
///
/// A body taken away for good — its entity destroyed, switched off or
/// without its collider — ends its pairs with no exit, as Unity does.
final class ContactPairs<B extends Object> {
  final Map<_BodyKey<B>, BodyContact<B>> _contacts = {};
  final Map<B, List<BodyContact<B>>> _byBody = {};
  final Map<_EntityKey, EntityContact> _entities = {};
  final List<EntityContact> _orphans = [];

  /// Every body contact.
  Iterable<BodyContact<B>> get contacts => _contacts.values;

  /// Whether no bodies touch.
  bool get isEmpty => _contacts.isEmpty;

  /// How many pairs of entities touch, waiting ones included.
  int get entityPairCount => _entities.length;

  /// The backend says [a] (of [entityA]) and [b] (of [entityB]) began to
  /// touch — overlap, when [sensor]. The new contact, with
  /// [BodyContact.enters] saying whether gameplay is to hear of it; null
  /// when they already touched (another pair of their shapes).
  BodyContact<B>? begin(
    B a,
    B b,
    Entity entityA,
    Entity entityB, {
    required bool sensor,
  }) {
    final key = _BodyKey<B>(a, b, sensor);
    final known = _contacts[key];
    if (known != null) {
      known._count++;
      return null;
    }
    final entityKey = _EntityKey(entityA, entityB, sensor);
    var pair = _entities[entityKey];
    final enters = pair == null;
    if (pair == null) {
      pair = EntityContact._(entityA, entityB, sensor);
      _entities[pair._key] = pair;
    }
    pair
      .._count += 1
      .._orphaned = false;
    final contact = BodyContact<B>._(a, b, entityA, entityB, pair)
      ..enters = enters;
    _contacts[key] = contact;
    (_byBody[a] ??= []).add(contact);
    (_byBody[b] ??= []).add(contact);
    return contact;
  }

  /// The backend says [a] and [b] stopped touching — every pair of their
  /// shapes at once, with [all]. The contact taken away,
  /// with [BodyContact.exits] saying whether gameplay is to hear of it;
  /// null when they still touch (another pair of their shapes) or were not
  /// known to touch.
  BodyContact<B>? end(B a, B b, {required bool sensor, bool all = false}) {
    final key = _BodyKey<B>(a, b, sensor);
    final contact = _contacts[key];
    if (contact == null) return null;
    contact._count = all ? 0 : contact._count - 1;
    if (contact._count > 0) return null;
    _contacts.remove(key);
    _unlist(contact.a, contact);
    _unlist(contact.b, contact);
    final pair = contact.entities;
    contact.exits = --pair._count == 0;
    if (contact.exits) _entities.remove(pair._key);
    return contact;
  }

  /// Takes away every contact of [body], which the backend no longer has.
  /// [onGone] sees each.
  ///
  /// [rebuilt]: a new body takes its place at once; a pair of entities it
  /// leaves apart waits for [settle]. Otherwise the body is gone for good
  /// and its pairs end with no exit — and so do the waiting pairs of its
  /// [entity].
  void removeBody(
    B body, {
    required bool rebuilt,
    Entity? entity,
    void Function(BodyContact<B> contact)? onGone,
  }) {
    final list = _byBody.remove(body);
    if (list != null) {
      for (final contact in list) {
        _contacts.remove(_BodyKey<B>(contact.a, contact.b, contact.sensor));
        _unlist(contact.other(body), contact);
        onGone?.call(contact);
        final pair = contact.entities;
        if (--pair._count > 0) continue;
        if (rebuilt) {
          pair._orphaned = true;
          _orphans.add(pair);
        } else {
          _entities.remove(pair._key);
        }
      }
    }
    if (rebuilt || entity == null || _orphans.isEmpty) return;
    for (final pair in _orphans) {
      if (!pair._orphaned || (pair.a != entity && pair.b != entity)) continue;
      pair._orphaned = false;
      if (pair._count == 0) _entities.remove(pair._key);
    }
  }

  /// The pairs of entities a body made again left apart and its new body
  /// was not found touching: exits to send. Call after a step — not after
  /// an update that ran none, when nothing has been looked for yet.
  List<EntityContact> settle() {
    if (_orphans.isEmpty) return const [];
    final out = <EntityContact>[];
    for (final pair in _orphans) {
      if (!pair._orphaned) continue;
      pair._orphaned = false;
      if (pair._count > 0) continue;
      _entities.remove(pair._key);
      out.add(pair);
    }
    _orphans.clear();
    return out;
  }

  /// Forgets everything, sending nothing.
  void clear() {
    _contacts.clear();
    _byBody.clear();
    _entities.clear();
    _orphans.clear();
  }

  void _unlist(B body, BodyContact<B> contact) {
    final list = _byBody[body];
    if (list == null) return;
    list.remove(contact);
    if (list.isEmpty) _byBody.remove(body);
  }
}

/// Two bodies, either way round, and whether it is an overlap.
final class _BodyKey<B extends Object> {
  _BodyKey(this.a, this.b, this.sensor);

  final B a, b;
  final bool sensor;

  @override
  bool operator ==(Object other) =>
      other is _BodyKey<B> &&
      other.sensor == sensor &&
      ((other.a == a && other.b == b) || (other.a == b && other.b == a));

  @override
  int get hashCode => (a.hashCode ^ b.hashCode) + (sensor ? 1 : 0);
}

/// Two entities, either way round, and whether it is an overlap.
final class _EntityKey {
  _EntityKey(this.a, this.b, this.sensor);

  final Entity a, b;
  final bool sensor;

  @override
  bool operator ==(Object other) =>
      other is _EntityKey &&
      other.sensor == sensor &&
      ((identical(other.a, a) && identical(other.b, b)) ||
          (identical(other.a, b) && identical(other.b, a)));

  @override
  int get hashCode =>
      (identityHashCode(a) ^ identityHashCode(b)) + (sensor ? 1 : 0);
}
