/// The bodies side of `Physics3DSystem`: a body for each entity with a
/// [Collider3DComponent], made, kept in step and read back.
library;

import 'package:just_physics_engine/physics_3d.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import '../../foundation/solid_shape.dart';
import '../body_rebuild.dart';
import 'collider_3d_shapes.dart';
import 'physics_3d_components.dart';

/// The bodies `Physics3DSystem` keeps: one for every entity with a
/// [TransformComponent] and a [Collider3DComponent], whose
/// [RigidBody3DComponent] says how it moves (none: a static body) — the
/// 3-D twin of the 2-D system's bodies.
///
/// [sync] makes, rebuilds and updates them from their components before
/// the step: forces, impulses and velocities queued on a
/// [RigidBody3DComponent], and transforms written by hand — a teleport, or
/// for a kinematic body a move the physics carries what it touches along.
/// [readBack] writes the moved bodies' poses back into their
/// [TransformComponent]s, after `capturePrevious()` so the renderer
/// interpolates between steps.
@internal
final class Physics3DBodies {
  /// Bodies in the world [physics] gives (made the first time it is asked
  /// for); [entities] gets each body's entity. [onBodyGone] hears of each
  /// body destroyed — `rebuilt` when a new one takes its place at once.
  Physics3DBodies(
    this._physics,
    this.shapes,
    this.entities, {
    required this.onBodyGone,
  });

  final PhysicsWorld3D Function() _physics;

  /// Turns colliders into shapes.
  final Collider3DShapes shapes;

  /// Each body's entity — shared with the characters' bodies.
  final Map<int, Entity> entities;

  /// [body], [entity]'s, was destroyed.
  final void Function(int body, Entity entity, {required bool rebuilt})
  onBodyGone;

  final Map<Entity, _BodyLink> _bodies = {};
  final Map<int, _BodyLink> _linkByBody = {};
  final BodyPoses3D _moved = BodyPoses3D();
  final Quaternion _q = Quaternion.identity();
  final Quaternion _scratch = Quaternion.identity();
  final Vector3 _zero = Vector3.zero();

  /// Whether there are no colliders.
  bool get isEmpty => _bodies.isEmpty;

  /// [entity]'s body, or 0.
  int bodyOf(Entity entity) => _bodies[entity]?.body ?? 0;

  /// Whether [entity]'s rigid body is a sensor.
  bool isSensor(Entity entity) => _bodies[entity]?.rigid?.isSensor ?? false;

  /// Brings the links up to date with [world] at structure [version]: new
  /// colliders are linked, and the bodies of entities destroyed or without
  /// their collider go.
  void refresh(World world, int version) {
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      Collider3DComponent,
    ])) {
      final ids = archetype.entityIds;
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(Collider3DComponent)!;
      final rigids = archetype.getColumn(RigidBody3DComponent);
      for (var row = 0; row < ids.length; row++) {
        final entity = archetype.entityAt(row);
        final link = _bodies[entity] ??= _BodyLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..collider = colliders[row] as Collider3DComponent
          ..rigid = rigids?[row] as RigidBody3DComponent?
          ..version = version;
      }
    }
    // Destroyed, or no longer carrying the components.
    _bodies.removeWhere((_, link) {
      if (link.version == version) return false;
      _removeBody(link);
      return true;
    });
  }

  /// [model] was loaded again: its mesh and hull colliders take its new
  /// triangles once they are there.
  void reloadModel(String model) {
    shapes.forgetModel(model);
    for (final link in _bodies.values) {
      final c = link.collider;
      if (c.model == model &&
          (c.shape == Collider3DShape.mesh ||
              c.shape == Collider3DShape.convexHull)) {
        link.reloading = true;
      }
    }
  }

  /// Brings every body up to date with its components before a step of
  /// [dt] seconds.
  void sync(double dt) {
    for (final link in _bodies.values) {
      if (!link.entity.isActiveInHierarchy) {
        _removeBody(link);
        continue;
      }
      final transform = link.transform;
      final rigid = link.rigid;
      // The collider is turned into a shape again only when it, the
      // entity's scale or (matching it) the entity's shape changed — or
      // while its triangles are loading.
      final source = link.collider.shape == Collider3DShape.matchShape
          ? link.source()
          : null;
      final solidKey = source?.solidKey;
      final colliderChanged = !link.colliderMatches(
        link.collider,
        transform.scale,
        solidKey,
      );
      var shape = colliderChanged || link.shape == null || link.reloading
          ? shapes.build(link.collider, transform.scale, source: source)
          : link.shape;
      if (link.reloading) {
        // Its model is loading again: its old shape until the new is there.
        if (shape == null && !colliderChanged) {
          shape = link.shape;
        } else {
          link.reloading = false;
        }
      }
      if (colliderChanged) {
        link.rememberCollider(link.collider, transform.scale, solidKey);
      }
      if (link.body != 0 && (shape != link.shape || !link.matches(rigid))) {
        // The shape or something fixed at creation changed: made again,
        // moving as it was.
        if (rigid != null) {
          link.keepVelocity = Vector3.copy(rigid.linearVelocity);
          link.keepSpin = Vector3.copy(rigid.angularVelocity);
        }
        _removeBody(link, rebuilt: true);
      }
      if (shape == null) continue; // Triangles still loading.
      if (link.body == 0) {
        // One that could not be made is tried again only once it changes.
        if (link.failed && !colliderChanged && link.failedWith(rigid)) {
          continue;
        }
        _createBody(link, shape);
        if (link.body == 0) continue;
      } else {
        _applySettings(link);
        _followTransform(link, dt);
      }
      if (rigid != null) _flushCommands(link.body, rigid);
    }
  }

  /// [rigid]'s motion quality as the physics engine takes it: continuous
  /// collision is a linear cast.
  static MotionQuality3D quality(RigidBody3DComponent? rigid) =>
      (rigid?.continuousCollision ?? false)
      ? MotionQuality3D.linearCast
      : MotionQuality3D.discrete;

  void _createBody(_BodyLink link, Shape3D shape) {
    final transform = link.transform;
    final rigid = link.rigid;
    transform.rotationInto(_q);
    final type = rigid?.bodyType ?? BodyType3D.static;
    final body = _physics().createBody(
      shape,
      BodySettings3D(
        position: transform.position,
        rotation: _q,
        linearVelocity: link.keepVelocity ?? rigid?.initialVelocity,
        angularVelocity: link.keepSpin ?? rigid?.initialAngularVelocity,
        type: type,
        motionQuality: quality(rigid),
        layer: rigid?.layer ?? 0,
        isSensor: rigid?.isSensor ?? false,
        allowSleeping: rigid?.canSleep ?? true,
        lockRotation: rigid?.lockRotation ?? false,
        friction: rigid?.friction ?? 0.5,
        restitution: rigid?.restitution ?? 0.0,
        linearDamping: rigid?.linearDamping ?? 0.05,
        angularDamping: rigid?.angularDamping ?? 0.05,
        gravityFactor: rigid?.gravityScale ?? 1.0,
        mass: rigid?.mass ?? 0.0,
      ),
    );
    link
      ..keepVelocity = null
      ..keepSpin = null;
    if (body == 0) {
      // A mesh on a dynamic body, say: nothing to simulate until it changes.
      link
        ..shape = shape
        ..failed = true
        ..remember(rigid);
      return;
    }
    link
      ..failed = false
      ..body = body
      ..shape = shape
      ..remember(rigid)
      ..rememberPose(_scratch);
    rigid?.body = body;
    entities[body] = link.entity;
    _linkByBody[body] = link;
    transform.capturePrevious();
  }

  void _applySettings(_BodyLink link) {
    final rigid = link.rigid;
    if (rigid == null) return;
    final physics = _physics();
    final body = link.body;
    if (rigid.friction != link.friction) {
      physics.setFriction(body, link.friction = rigid.friction);
    }
    if (rigid.restitution != link.restitution) {
      physics.setRestitution(body, link.restitution = rigid.restitution);
    }
    if (rigid.gravityScale != link.gravityFactor) {
      physics.setGravityFactor(body, link.gravityFactor = rigid.gravityScale);
      physics.wake(body);
    }
    if (rigid.layer != link.layer) {
      physics.setLayer(body, link.layer = rigid.layer);
      physics.wake(body);
    }
    if (quality(rigid) != link.motionQuality) {
      physics.setMotionQuality(body, link.motionQuality = quality(rigid));
    }
  }

  /// A transform written by someone else since the last step: a kinematic
  /// body is moved there by the physics, anything else teleported.
  void _followTransform(_BodyLink link, double dt) {
    final physics = _physics();
    final transform = link.transform;
    final p = transform.position;
    transform.rotationInto(_q);
    if (link.isAt(p, _q)) {
      if (link.kinematicMoved) {
        // Gameplay stopped moving it: a kinematic body would otherwise keep
        // the velocity its last move gave it.
        link.kinematicMoved = false;
        physics
          ..setLinearVelocity(link.body, _zero)
          ..setAngularVelocity(link.body, _zero);
      }
      return;
    }
    final type = link.rigid?.bodyType ?? BodyType3D.static;
    if (type == BodyType3D.kinematic && dt > 0) {
      physics.moveKinematic(link.body, p, _q, dt);
      // Drawn from where it was to where it is going.
      link
        ..savePrevious()
        ..prevFromLast = true
        ..kinematicMoved = true;
    } else {
      physics.setBodyPose(link.body, p, _q, wake: type != BodyType3D.static);
      transform.capturePrevious();
    }
    link.rememberPose(_scratch);
  }

  void _flushCommands(int body, RigidBody3DComponent rigid) {
    final physics = _physics();
    final velocity = rigid.pendingVelocity;
    if (velocity != null) {
      physics.setLinearVelocity(body, velocity);
      rigid.pendingVelocity = null;
    }
    final spin = rigid.pendingAngularVelocity;
    if (spin != null) {
      physics.setAngularVelocity(body, spin);
      rigid.pendingAngularVelocity = null;
    }
    if (rigid.pendingImpulse.lengthSquared > 0) {
      physics.addImpulse(body, rigid.pendingImpulse);
      rigid.pendingImpulse.setZero();
    }
    if (rigid.pendingAngularImpulse.lengthSquared > 0) {
      physics.addAngularImpulse(body, rigid.pendingAngularImpulse);
      rigid.pendingAngularImpulse.setZero();
    }
    if (rigid.pendingForce.lengthSquared > 0) {
      physics.addForce(body, rigid.pendingForce);
      rigid.pendingForce.setZero();
    }
    if (rigid.pendingTorque.lengthSquared > 0) {
      physics.addTorque(body, rigid.pendingTorque);
      rigid.pendingTorque.setZero();
    }
    if (rigid.pendingWake) {
      physics.wake(body);
      rigid.pendingWake = false;
    }
  }

  /// Destroys [link]'s body, if it has one — [rebuilt] when a new one takes
  /// its place at once: its pairs of entities then wait for the new body
  /// and what it touched is woken, so the next step looks for that body.
  void _removeBody(_BodyLink link, {bool rebuilt = false}) {
    final body = link.body;
    if (body == 0) return;
    _physics().destroyBody(body);
    onBodyGone(body, link.entity, rebuilt: rebuilt);
    entities.remove(body);
    _linkByBody.remove(body);
    link.body = 0;
    link.shape = null;
    final rigid = link.rigid;
    if (rigid != null) {
      rigid.body = 0;
      rigid.isAwake = false;
    }
  }

  /// Writes the poses of the bodies step [stepIndex] moved back into their
  /// transforms; what did not move keeps its previous pose equal to its
  /// pose.
  void readBack(int stepIndex) {
    _physics().readMovedBodies(_moved);
    final moved = _moved;
    for (var i = 0; i < moved.count; i++) {
      final link = _linkByBody[moved.bodies[i]];
      if (link == null) continue;
      final transform = link.transform;
      if (link.prevFromLast) {
        // Moved by gameplay this step: drawn from where it was.
        link.capturePreviousFromLast(_scratch);
      } else {
        transform.capturePrevious();
      }
      moved.positionInto(i, transform.position);
      moved.rotationInto(i, _q);
      transform.setRotation(_q);
      link
        ..rememberPose(_scratch)
        ..movedAt = stepIndex
        ..prevFromLast = false;
      final rigid = link.rigid;
      if (rigid != null) {
        moved.linearVelocityInto(i, rigid.linearVelocity);
        moved.angularVelocityInto(i, rigid.angularVelocity);
        rigid.isAwake = moved.isAwake(i);
      }
    }
    // What did not move keeps its previous pose equal to its pose, or the
    // renderer would draw it between a stale pose and this one.
    for (final link in _bodies.values) {
      if (link.body == 0 || link.movedAt == stepIndex) continue;
      if (link.prevFromLast) {
        link
          ..capturePreviousFromLast(_scratch)
          ..prevFromLast = false;
        continue;
      }
      final t = link.transform;
      final prev = t.prevPosition, now = t.position;
      if (prev.x != now.x ||
          prev.y != now.y ||
          prev.z != now.z ||
          t.prevAngle != t.angle) {
        t.capturePrevious();
      }
    }
  }

  /// Destroys every body — unless the world is gone already ([worldGone]),
  /// when there is nothing left to destroy — and forgets every entity.
  void removeAll({required bool worldGone}) {
    if (!worldGone) {
      for (final link in _bodies.values) {
        _removeBody(link);
      }
    }
    _bodies.clear();
    _linkByBody.clear();
  }
}

/// An entity with a collider, and the body made for it.
final class _BodyLink {
  _BodyLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late Collider3DComponent collider;
  RigidBody3DComponent? rigid;
  int version = -1;

  // The component whose shape a collider matching it takes, found when
  // [version] was [_sourceVersion]: again only after the world's structure
  // changes, not every step.
  SolidShapeSource? _source;
  int _sourceVersion = -2;

  /// The entity's [SolidShapeSource], for a collider matching its shape.
  SolidShapeSource? source() {
    if (_sourceVersion != version) {
      _sourceVersion = version;
      _source = null;
      for (final c in entity.components) {
        if (c is SolidShapeSource) {
          _source = c as SolidShapeSource;
          break;
        }
      }
    }
    return _source;
  }

  int body = 0;
  Shape3D? shape;
  bool failed = false;

  /// Its model was loaded again: its shape is made again from the new
  /// triangles once they are there.
  bool reloading = false;
  bool kinematicMoved = false;
  int movedAt = -1;
  bool prevFromLast = false;
  Vector3? keepVelocity;
  Vector3? keepSpin;

  // What the body was made with, of what a change rebuilds.
  bool _hasRigid = false;
  BodyType3D _type = BodyType3D.static;
  bool _sensor = false, _canSleep = true, _lockRotation = false;
  double _mass = 0, _linearDamping = 0, _angularDamping = 0;

  // What can change on a live body.
  double friction = 0, restitution = 0, gravityFactor = 1;
  int layer = 0;
  MotionQuality3D motionQuality = MotionQuality3D.discrete;

  // The pose the body was last at, as the transform holds it, and the one
  // before a gameplay move (see capturePreviousFromLast).
  double _x = 0, _y = 0, _z = 0, _qx = 0, _qy = 0, _qz = 0, _qw = 1;
  double _px = 0, _py = 0, _pz = 0, _pqx = 0, _pqy = 0, _pqz = 0, _pqw = 1;

  // The collider and entity scale the shape was made from, and the look
  // matched.
  Collider3DShape? _kind;
  Object? _solid;
  double _sx = 0, _sy = 0, _sz = 0, _cx = 0, _cy = 0, _cz = 0;
  double _radius = 0, _height = 0, _cell = 0;
  double _ox = 0, _oy = 0, _oz = 0, _rx = 0, _ry = 0, _rz = 0;
  double _esx = 0, _esy = 0, _esz = 0;
  String _model = '', _mesh = '';
  List<double>? _heights;
  int _heightCount = 0, _fieldSize = 0;

  void rememberCollider(Collider3DComponent c, Vector3 scale, Object? solid) {
    _solid = solid;
    _kind = c.shape;
    _sx = c.size.x;
    _sy = c.size.y;
    _sz = c.size.z;
    _cx = c.scale.x;
    _cy = c.scale.y;
    _cz = c.scale.z;
    _radius = c.radius;
    _height = c.height;
    _cell = c.cellSize;
    _ox = c.offset.x;
    _oy = c.offset.y;
    _oz = c.offset.z;
    _rx = c.rotation.x;
    _ry = c.rotation.y;
    _rz = c.rotation.z;
    _esx = scale.x;
    _esy = scale.y;
    _esz = scale.z;
    _model = c.model;
    _mesh = c.meshName;
    _heights = c.heights;
    _heightCount = c.heights.length;
    _fieldSize = c.heightFieldSize;
  }

  bool colliderMatches(Collider3DComponent c, Vector3 scale, Object? solid) =>
      _kind == c.shape &&
      _solid == solid &&
      _sx == c.size.x &&
      _sy == c.size.y &&
      _sz == c.size.z &&
      _cx == c.scale.x &&
      _cy == c.scale.y &&
      _cz == c.scale.z &&
      _radius == c.radius &&
      _height == c.height &&
      _cell == c.cellSize &&
      _ox == c.offset.x &&
      _oy == c.offset.y &&
      _oz == c.offset.z &&
      _rx == c.rotation.x &&
      _ry == c.rotation.y &&
      _rz == c.rotation.z &&
      BodyRebuild.sameScale(_esx, scale.x) &&
      BodyRebuild.sameScale(_esy, scale.y) &&
      BodyRebuild.sameScale(_esz, scale.z) &&
      _model == c.model &&
      _mesh == c.meshName &&
      identical(_heights, c.heights) &&
      _heightCount == c.heights.length &&
      _fieldSize == c.heightFieldSize;

  void savePrevious() {
    _px = _x;
    _py = _y;
    _pz = _z;
    _pqx = _qx;
    _pqy = _qy;
    _pqz = _qz;
    _pqw = _qw;
  }

  void remember(RigidBody3DComponent? r) {
    _hasRigid = r != null;
    _type = r?.bodyType ?? BodyType3D.static;
    _sensor = r?.isSensor ?? false;
    _canSleep = r?.canSleep ?? true;
    _lockRotation = r?.lockRotation ?? false;
    _mass = r?.mass ?? 0;
    _linearDamping = r?.linearDamping ?? 0.05;
    _angularDamping = r?.angularDamping ?? 0.05;
    friction = r?.friction ?? 0.5;
    restitution = r?.restitution ?? 0;
    gravityFactor = r?.gravityScale ?? 1;
    layer = r?.layer ?? 0;
    motionQuality = Physics3DBodies.quality(r);
  }

  bool matches(RigidBody3DComponent? r) =>
      _hasRigid == (r != null) &&
      _type == (r?.bodyType ?? BodyType3D.static) &&
      _sensor == (r?.isSensor ?? false) &&
      _canSleep == (r?.canSleep ?? true) &&
      _lockRotation == (r?.lockRotation ?? false) &&
      _mass == (r?.mass ?? 0) &&
      _linearDamping == (r?.linearDamping ?? 0.05) &&
      _angularDamping == (r?.angularDamping ?? 0.05);

  /// Whether [r] asks for the body exactly as the one that could not be
  /// made: its layer too (one outside 0-15 is refused, and tried again once
  /// it is fixed).
  bool failedWith(RigidBody3DComponent? r) =>
      matches(r) &&
      layer == (r?.layer ?? 0) &&
      motionQuality == Physics3DBodies.quality(r);

  /// Remembers the transform's pose as the body's; [scratch] is room to
  /// read its rotation into.
  void rememberPose(Quaternion scratch) {
    final p = transform.position;
    transform.rotationInto(scratch);
    _x = p.x;
    _y = p.y;
    _z = p.z;
    _qx = scratch.x;
    _qy = scratch.y;
    _qz = scratch.z;
    _qw = scratch.w;
  }

  bool isAt(Vector3 p, Quaternion q) {
    const e = moveEpsilon3D;
    if ((p.x - _x).abs() > e || (p.y - _y).abs() > e || (p.z - _z).abs() > e) {
      return false;
    }
    final dot = q.x * _qx + q.y * _qy + q.z * _qz + q.w * _qw;
    return dot.abs() > 1 - 1e-10;
  }

  /// Sets the transform's previous pose to the one saved before a gameplay
  /// move ([savePrevious]); [scratch] is room for rotations.
  void capturePreviousFromLast(Quaternion scratch) {
    final t = transform;
    final p = t.position;
    final nx = p.x, ny = p.y, nz = p.z;
    t.rotationInto(scratch);
    final nqx = scratch.x, nqy = scratch.y, nqz = scratch.z, nqw = scratch.w;
    p.setValues(_px, _py, _pz);
    t.setRotation(scratch..setValues(_pqx, _pqy, _pqz, _pqw));
    t.capturePrevious();
    p.setValues(nx, ny, nz);
    t.setRotation(scratch..setValues(nqx, nqy, nqz, nqw));
  }
}

/// Below this a transform is where the 3-D physics left it (metres):
/// `Physics3DSystem.moveEpsilon`.
@internal
const double moveEpsilon3D = 1e-5;
