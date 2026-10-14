import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_physics_engine/physics_3d.dart';

import 'collider_shapes_3d.dart';
import 'physics_components_3d.dart';
import 'physics_events_3d.dart';

/// Steps a [PhysicsWorld3D] and keeps it in step with the ECS: the 3-D
/// counterpart of the engine's 2-D `PhysicsSystem` (a 3-D game leaves that
/// one out).
///
/// Each update it
/// 1. makes, rebuilds and removes bodies for entities with a [Collider3D]
///    (a [RigidBody3D] says how they move; without one they are static),
///    characters for [CharacterBody3D]s and joints for [Joint3D]s;
/// 2. sends what gameplay did: forces, impulses and velocities queued on a
///    [RigidBody3D], and transforms written by hand — a teleport, or for a
///    kinematic body a move the physics carries what it touches along;
/// 3. moves each character, then steps the world;
/// 4. writes the moved bodies' poses back into their [TransformComponent]s,
///    after `capturePrevious()` so the renderer interpolates between steps;
/// 5. fires [CollisionEnter3DEvent], [CollisionExit3DEvent],
///    [SensorEnter3DEvent] and the rest on the world's event bus.
///
/// It runs at [SystemPriorities.physics] (90), after input and player
/// control. Taking it out of its world or disposing it removes everything
/// it made from [physics]; the world itself belongs to whoever made it.
class PhysicsSystem3D extends System {
  /// A system stepping [physics]; mesh and hull colliders take their
  /// triangles from [geometry].
  PhysicsSystem3D(PhysicsWorld3D physics, {ColliderGeometry3D? geometry})
    : _physics = physics,
      _create = null,
      shapes = ColliderShapes3D(geometry: geometry) {
    priority = SystemPriorities.physics;
  }

  /// A system that makes its world with [create] only when the first 3-D
  /// body or character appears. Until then an update costs a structure
  /// check and nothing else, and there is no world at all — no worker
  /// threads, no tables sized for thousands of bodies — so a game whose 3-D
  /// scenes come later (a 2-D menu first) pays nothing for them.
  PhysicsSystem3D.lazy(
    PhysicsWorld3D Function() create, {
    ColliderGeometry3D? geometry,
  }) : _physics = null,
       _create = create,
       shapes = ColliderShapes3D(geometry: geometry) {
    priority = SystemPriorities.physics;
  }

  PhysicsWorld3D? _physics;
  final PhysicsWorld3D Function()? _create;

  /// The world it steps; a [PhysicsSystem3D.lazy] system makes it now if it
  /// has not yet.
  PhysicsWorld3D get physics => _physics ??= _create!();

  /// Whether the world exists (always, unless made with
  /// [PhysicsSystem3D.lazy] and still waiting for its first body).
  bool get hasWorld => _physics != null;

  /// Turns colliders into shapes.
  final ColliderShapes3D shapes;

  /// One collision pass per this much of a step; a longer step gets more.
  static const double collisionStep = 1 / 60;

  /// Below this a transform is where the system left it (metres).
  static const double moveEpsilon = 1e-5;

  @override
  List<Type> get requiredComponents => const [TransformComponent];

  final Map<Entity, _BodyLink> _bodies = {};
  final Map<Entity, _CharacterLink> _characters = {};
  final Map<Joint3D, _JointLink> _joints = Map.identity();
  final Map<int, Entity> _entityByBody = {};
  final Map<int, _BodyLink> _linkByBody = {};
  int _seenStructureVersion = -1;
  int _stepIndex = 0;
  final BodyPoses3D _moved = BodyPoses3D();
  final CharacterState3D _state = CharacterState3D();
  final Vector3 _v = Vector3.zero();
  final Vector3 _up = Vector3.zero();
  final Vector3 _down = Vector3.zero();
  final Vector3 _stepUp = Vector3.zero();
  final Quaternion _q = Quaternion.identity();
  static final Vector3 _zero = Vector3.zero();

  /// The entity whose body, or character's body, [body] is; null for one
  /// this system did not make.
  Entity? entityOf(int body) => _entityByBody[body];

  /// [entity]'s body, or 0.
  int bodyOf(Entity entity) => _bodies[entity]?.body ?? 0;

  /// [entity]'s character, or 0.
  int characterOf(Entity entity) => _characters[entity]?.character ?? 0;

  @override
  void update(double deltaTime) {
    if (_physics?.isDisposed ?? false) return;
    _refresh();
    // Nothing 3-D yet: no world to make, step or read.
    if (_physics == null && _bodies.isEmpty && _characters.isEmpty) return;
    _syncBodies(deltaTime);
    _syncJoints();
    if (deltaTime > 0) _moveCharacters(deltaTime);
    if (deltaTime > 0) {
      physics.step(
        deltaTime,
        collisionSteps: math.max(1, (deltaTime / collisionStep - 1e-6).ceil()),
      );
      _stepIndex++;
    }
    _readBack();
    _dispatchEvents();
  }

  @override
  void onRemovedFromWorld() => _removeAll();

  @override
  void dispose() => _removeAll();

  // ── Links ─────────────────────────────────────────────────────────────

  static const List<Type> _jointTypes = [
    FixedJoint3D,
    PointJoint3D,
    HingeJoint3D,
    SliderJoint3D,
    DistanceJoint3D,
    SixDofJoint3D,
  ];

  /// Brings the link maps up to date when the world's structure changed.
  void _refresh() {
    final version = world.structureVersion;
    if (version == _seenStructureVersion) return;
    _seenStructureVersion = version;

    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      Collider3D,
    ])) {
      final ids = archetype.entityIds;
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(Collider3D)!;
      final rigids = archetype.getColumn(RigidBody3D);
      for (var row = 0; row < ids.length; row++) {
        final entity = world.getEntity(ids[row]);
        if (entity == null) continue;
        final link = _bodies[entity] ??= _BodyLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..collider = colliders[row] as Collider3D
          ..rigid = rigids?[row] as RigidBody3D?
          ..version = version;
      }
    }
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      CharacterBody3D,
    ])) {
      final ids = archetype.entityIds;
      final transforms = archetype.getColumn(TransformComponent)!;
      final comps = archetype.getColumn(CharacterBody3D)!;
      for (var row = 0; row < ids.length; row++) {
        final entity = world.getEntity(ids[row]);
        if (entity == null) continue;
        final link = _characters[entity] ??= _CharacterLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..comp = comps[row] as CharacterBody3D
          ..version = version;
      }
    }
    for (final type in _jointTypes) {
      for (final archetype in world.queryArchetypes([
        TransformComponent,
        type,
      ])) {
        final ids = archetype.entityIds;
        final comps = archetype.getColumn(type)!;
        for (var row = 0; row < ids.length; row++) {
          final entity = world.getEntity(ids[row]);
          if (entity == null) continue;
          final comp = comps[row] as Joint3D;
          final link = _joints[comp] ??= _JointLink(entity, comp);
          link.version = version;
        }
      }
    }

    // Destroyed, or no longer carrying the components.
    _bodies.removeWhere((_, link) {
      if (link.version == version) return false;
      _removeBody(link);
      return true;
    });
    _characters.removeWhere((_, link) {
      if (link.version == version) return false;
      _removeCharacter(link);
      return true;
    });
    _joints.removeWhere((_, link) {
      if (link.version == version) return false;
      _removeJoint(link);
      return true;
    });
  }

  // ── Bodies ────────────────────────────────────────────────────────────

  void _syncBodies(double dt) {
    for (final link in _bodies.values) {
      if (!link.entity.isActive) {
        _removeBody(link);
        continue;
      }
      final transform = link.transform;
      final rigid = link.rigid;
      // The collider is turned into a shape again only when it, the
      // entity's scale or (matching it) the entity's shape changed — or
      // while its triangles are loading.
      final source = link.collider.shape == ColliderShape3D.matchShape
          ? _sourceOf(link.entity)
          : null;
      final solidKey = source?.solidKey;
      final colliderChanged = !link.colliderMatches(
        link.collider,
        transform.scale,
        solidKey,
      );
      final shape = colliderChanged || link.shape == null
          ? shapes.build(link.collider, transform.scale, source: source)
          : link.shape;
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
        _removeBody(link);
      }
      if (shape == null) continue; // Triangles still loading.
      if (link.body == 0) {
        // One that could not be made is tried again only once it changes.
        if (link.failed && !colliderChanged && link.matches(rigid)) continue;
        _createBody(link, shape);
        if (link.body == 0) continue;
      } else {
        _applySettings(link);
        _followTransform(link, dt);
      }
      if (rigid != null) _flushCommands(link.body, rigid);
    }
  }

  /// The shape [entity] is drawn as, for a collider matching it.
  /// [rigid]'s motion quality as the physics engine takes it: continuous
  /// collision is a linear cast.
  static MotionQuality3D _quality(RigidBody3D? rigid) =>
      (rigid?.continuousCollision ?? false) ? MotionQuality3D.linearCast : MotionQuality3D.discrete;

  static SolidShapeSource? _sourceOf(Entity entity) =>
      entity.components.whereType<SolidShapeSource>().firstOrNull;

  void _createBody(_BodyLink link, Shape3D shape) {
    final transform = link.transform;
    final rigid = link.rigid;
    transform.rotationInto(_q);
    final type = rigid?.bodyType ?? BodyType3D.static;
    final body = physics.createBody(
      shape,
      BodySettings3D(
        position: transform.position,
        rotation: _q,
        linearVelocity: link.keepVelocity ?? rigid?.initialVelocity,
        angularVelocity: link.keepSpin ?? rigid?.initialAngularVelocity,
        type: type,
        motionQuality: _quality(rigid),
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
      ..rememberPose();
    rigid?.body = body;
    _entityByBody[body] = link.entity;
    _linkByBody[body] = link;
    transform.capturePrevious();
  }

  void _applySettings(_BodyLink link) {
    final rigid = link.rigid;
    if (rigid == null) return;
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
    if (_quality(rigid) != link.motionQuality) {
      physics.setMotionQuality(body, link.motionQuality = _quality(rigid));
    }
  }

  /// A transform written by someone else since the last step: a kinematic
  /// body is moved there by the physics, anything else teleported.
  void _followTransform(_BodyLink link, double dt) {
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
    link.rememberPose();
  }

  void _flushCommands(int body, RigidBody3D rigid) {
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

  void _removeBody(_BodyLink link) {
    final body = link.body;
    if (body == 0) return;
    physics.destroyBody(body);
    _entityByBody.remove(body);
    _linkByBody.remove(body);
    link.body = 0;
    link.shape = null;
    final rigid = link.rigid;
    if (rigid != null) {
      rigid.body = 0;
      rigid.isAwake = false;
    }
  }

  // ── Joints ────────────────────────────────────────────────────────────

  void _syncJoints() {
    for (final link in _joints.values) {
      final comp = link.comp;
      final a = link.entity.isActive ? _bodies[link.entity]?.body ?? 0 : 0;
      int? b = 0;
      if (!comp.connectedBody.isNone) {
        final other = comp.connectedBody.resolve(world, link.entity);
        b = other == null ? null : _bodies[other]?.body;
        if (b == 0) b = null;
      }
      if (a == 0 || b == null) {
        _removeJoint(link);
        continue;
      }
      final signature = _JointSignature.of(comp, a, b);
      if (link.joint != 0 &&
          (signature != link.signature || !physics.isJoint(link.joint))) {
        _removeJoint(link);
      }
      if (link.joint == 0) {
        final settings = _jointSettings(link.entity, comp, b);
        final joint = physics.createJoint(a, b, settings);
        if (joint == 0) continue;
        link
          ..joint = joint
          ..signature = signature
          ..enabled = true
          ..motor = settings.motorState
          ..motorTarget = settings.motorTarget;
        comp.joint = joint;
      }
      if (comp.enabled != link.enabled) {
        physics.setJointEnabled(link.joint, link.enabled = comp.enabled);
      }
      final (motor, target) = switch (comp) {
        HingeJoint3D h => (h.motor, h.motorTarget),
        SliderJoint3D s => (s.motor, s.motorTarget),
        _ => (MotorState3D.off, 0.0),
      };
      if (motor != link.motor || target != link.motorTarget) {
        physics.setJointMotor(
          link.joint,
          link.motor = motor,
          link.motorTarget = target,
        );
      }
    }
  }

  /// [comp]'s settings, in world space as the bodies are now.
  JointSettings3D _jointSettings(Entity entity, Joint3D comp, int bodyB) {
    final transform = entity.getComponent<TransformComponent>()!;
    final pointA = _worldPoint(transform, comp.anchor);
    Vector3 axisOf(Vector3 local) {
      transform.rotationInto(_q);
      final out = Vector3.copy(local);
      _q.rotate(out);
      if (out.lengthSquared < 1e-12) out.setValues(1, 0, 0);
      out.normalize();
      return out;
    }

    switch (comp) {
      case HingeJoint3D h:
        final axis = axisOf(h.axis);
        return JointSettings3D(
          kind: JointKind3D.hinge,
          pointA: pointA,
          axis: axis,
          normal: _perpendicular(axis),
          hasLimits: h.useLimits,
          limitMin: h.minAngle,
          limitMax: h.maxAngle,
          maxFriction: h.friction,
          motorState: h.motor,
          motorTarget: h.motorTarget,
          motorMaxForce: h.motorMaxTorque,
        );
      case SliderJoint3D s:
        final axis = axisOf(s.axis);
        return JointSettings3D(
          kind: JointKind3D.slider,
          pointA: pointA,
          axis: axis,
          normal: _perpendicular(axis),
          hasLimits: s.useLimits,
          limitMin: s.minPosition,
          limitMax: s.maxPosition,
          maxFriction: s.friction,
          motorState: s.motor,
          motorTarget: s.motorTarget,
          motorMaxForce: s.motorMaxForce,
        );
      case DistanceJoint3D d:
        final other = d.connectedBody.isNone
            ? null
            : d.connectedBody.resolve(world, entity);
        final otherTransform = other?.getComponent<TransformComponent>();
        final pointB = otherTransform == null
            ? Vector3.copy(d.connectedAnchor)
            : _worldPoint(otherTransform, d.connectedAnchor);
        return JointSettings3D(
          kind: JointKind3D.distance,
          pointA: pointA,
          pointB: pointB,
          hasLimits: true,
          limitMin: d.minDistance,
          limitMax: d.maxDistance,
          springFrequency: d.springFrequency,
          springDamping: d.springDamping,
        );
      case SixDofJoint3D x:
        return JointSettings3D(
          kind: JointKind3D.sixDof,
          pointA: pointA,
          axis: axisOf(x.axis),
          normal: axisOf(x.normal),
          sixDofModes: x.modes,
          sixDofMin: [
            x.translationMin.x,
            x.translationMin.y,
            x.translationMin.z,
            x.rotationMin.x,
            x.rotationMin.y,
            x.rotationMin.z,
          ],
          sixDofMax: [
            x.translationMax.x,
            x.translationMax.y,
            x.translationMax.z,
            x.rotationMax.x,
            x.rotationMax.y,
            x.rotationMax.z,
          ],
        );
      default:
        return JointSettings3D(kind: comp.kind, pointA: pointA);
    }
  }

  Vector3 _worldPoint(TransformComponent transform, Vector3 local) {
    final out = Vector3(
      local.x * transform.scale.x,
      local.y * transform.scale.y,
      local.z * transform.scale.z,
    );
    transform.rotationInto(_q);
    _q.rotate(out);
    out.add(transform.position);
    return out;
  }

  static Vector3 _perpendicular(Vector3 axis) {
    final helper = axis.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
    final out = axis.cross(helper);
    out.normalize();
    return out;
  }

  void _removeJoint(_JointLink link) {
    if (link.joint == 0) return;
    physics.destroyJoint(link.joint);
    link
      ..joint = 0
      ..signature = null;
    link.comp.joint = 0;
  }

  // ── Characters ────────────────────────────────────────────────────────

  void _moveCharacters(double dt) {
    final gravity = physics.gravity;
    for (final link in _characters.values) {
      final comp = link.comp;
      if (!link.entity.isActive) {
        _removeCharacter(link);
        continue;
      }
      final transform = link.transform;
      if (link.character != 0 && !link.matches(comp)) _removeCharacter(link);
      if (link.character == 0) {
        _up.setFrom(gravity);
        if (_up.normalize() == 0) _up.setValues(0, 1, 0);
        _up.negate();
        final character = physics.createCharacter(
          CharacterSettings3D(
            radius: comp.radius,
            halfHeight: math.max(comp.height / 2 - comp.radius, 0.0),
            up: Vector3.copy(_up),
            maxSlopeAngle: comp.maxSlopeAngle,
            mass: comp.mass,
            maxStrength: comp.pushStrength,
            layer: comp.layer,
            innerBody: comp.detectable,
          ),
          transform.position,
        );
        if (character == 0) continue;
        link
          ..character = character
          ..innerBody = physics.characterBody(character)
          ..remember(comp)
          ..rememberPosition(transform.position);
        comp.character = character;
        if (link.innerBody != 0) _entityByBody[link.innerBody] = link.entity;
        transform.capturePrevious();
      } else if (!link.isAt(transform.position)) {
        // Teleported by gameplay (a respawn).
        physics.setCharacterPosition(link.character, transform.position);
        transform.capturePrevious();
      }

      _up.setFrom(gravity);
      final g = _up.normalize();
      if (g == 0) _up.setValues(0, 1, 0);
      _up.negate(); // Against gravity.
      final v = _v;
      if (comp.useGravity) {
        // Jolt's own recipe: on the ground, move with it (a platform carries
        // the character) unless moving away from it; in the air, keep the
        // vertical speed. Then gravity, then the requested movement.
        final vertical = comp.velocity.dot(_up);
        final groundVertical = comp.groundVelocity.dot(_up);
        final towardsGround = vertical - groundVertical < 0.1;
        if (comp.isGrounded && towardsGround) {
          v.setFrom(comp.groundVelocity);
          final jump = comp.pendingJump;
          if (jump != null) v.addScaled(_up, jump);
        } else {
          v
            ..setFrom(_up)
            ..scale(vertical);
        }
        v.addScaled(gravity, comp.gravityScale * dt);
        v.add(comp.moveVelocity);
        v.addScaled(_up, -comp.moveVelocity.dot(_up));
      } else {
        v.setFrom(comp.moveVelocity);
      }
      comp.pendingJump = null;
      _down
        ..setFrom(_up)
        ..scale(-comp.stickToFloor);
      _stepUp
        ..setFrom(_up)
        ..scale(comp.stepHeight);

      final state = _state;
      physics.moveCharacter(
        link.character,
        dt,
        v,
        state,
        stepDown: _down,
        stepUp: _stepUp,
      );
      // Gameplay turned it before the step (a controller facing where it
      // runs): it is drawn turning from where the last step left it.
      if (link.turned) {
        transform.capturePreviousWithRotation(link.turn);
      } else {
        transform.capturePrevious();
      }
      transform.position.setFrom(state.position);
      transform.rotationInto(link.turn);
      link.turned = true;
      link.rememberPosition(transform.position);
      comp.velocity.setFrom(state.velocity);
      comp.groundState = state.groundState;
      comp.groundNormal.setFrom(state.groundNormal);
      comp.groundVelocity.setFrom(state.groundVelocity);
      comp.groundEntity = state.groundBody == 0
          ? null
          : _entityByBody[state.groundBody];
    }
  }

  void _removeCharacter(_CharacterLink link) {
    if (link.character == 0) return;
    physics.destroyCharacter(link.character);
    if (link.innerBody != 0) _entityByBody.remove(link.innerBody);
    link
      ..character = 0
      ..innerBody = 0;
    final comp = link.comp;
    comp
      ..character = 0
      ..groundState = GroundState3D.inAir
      ..groundEntity = null;
  }

  // ── After the step ────────────────────────────────────────────────────

  void _readBack() {
    physics.readMovedBodies(_moved);
    final moved = _moved;
    for (var i = 0; i < moved.count; i++) {
      final link = _linkByBody[moved.bodies[i]];
      if (link == null) continue;
      final transform = link.transform;
      if (link.prevFromLast) {
        // Moved by gameplay this step: drawn from where it was.
        link.capturePreviousFromLast();
      } else {
        transform.capturePrevious();
      }
      moved.positionInto(i, transform.position);
      moved.rotationInto(i, _q);
      transform.setRotation(_q);
      link
        ..rememberPose()
        ..movedAt = _stepIndex
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
      if (link.body == 0 || link.movedAt == _stepIndex) continue;
      if (link.prevFromLast) {
        link
          ..capturePreviousFromLast()
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
    for (final link in _joints.values) {
      if (link.joint == 0) continue;
      switch (link.comp) {
        case HingeJoint3D h:
          h.angle = physics.jointValue(link.joint);
        case SliderJoint3D s:
          s.position = physics.jointValue(link.joint);
        default:
      }
    }
  }

  void _dispatchEvents() {
    final events = physics.drainEvents();
    if (events.isEmpty) return;
    final bus = world.events;
    for (final e in events) {
      final a = _entityByBody[e.bodyA];
      final b = _entityByBody[e.bodyB];
      if (a == null || b == null) continue; // A body this system did not make.
      switch (e.type) {
        case PhysicsEventType3D.contactBegin:
          bus.fire(
            CollisionEnter3DEvent(
              entityA: a,
              entityB: b,
              point: e.point,
              normal: e.normal,
              depth: e.depth,
            ),
          );
        case PhysicsEventType3D.contactStay:
          bus.fire(
            CollisionStay3DEvent(
              entityA: a,
              entityB: b,
              point: e.point,
              normal: e.normal,
              depth: e.depth,
            ),
          );
        case PhysicsEventType3D.contactEnd:
          bus.fire(CollisionExit3DEvent(entityA: a, entityB: b));
        case PhysicsEventType3D.sensorBegin:
          final (sensor, other) = _sensorFirst(a, b);
          bus.fire(SensorEnter3DEvent(sensor: sensor, other: other));
        case PhysicsEventType3D.sensorEnd:
          final (sensor, other) = _sensorFirst(a, b);
          bus.fire(SensorExit3DEvent(sensor: sensor, other: other));
        case PhysicsEventType3D.bodyActivated ||
            PhysicsEventType3D.bodyDeactivated:
          break;
      }
    }
  }

  (Entity, Entity) _sensorFirst(Entity a, Entity b) =>
      _bodies[b]?.rigid?.isSensor == true && _bodies[a]?.rigid?.isSensor != true
      ? (b, a)
      : (a, b);

  void _removeAll() {
    final world = _physics;
    if (world == null || world.isDisposed) {
      _bodies.clear();
      _characters.clear();
      _joints.clear();
      _entityByBody.clear();
      _linkByBody.clear();
      return;
    }
    for (final link in _joints.values) {
      _removeJoint(link);
    }
    for (final link in _characters.values) {
      _removeCharacter(link);
    }
    for (final link in _bodies.values) {
      _removeBody(link);
    }
    _joints.clear();
    _characters.clear();
    _bodies.clear();
    _seenStructureVersion = -1;
  }
}

/// An entity with a collider, and the body made for it.
final class _BodyLink {
  _BodyLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late Collider3D collider;
  RigidBody3D? rigid;
  int version = -1;

  int body = 0;
  Shape3D? shape;
  bool failed = false;
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
  ColliderShape3D? _kind;
  Object? _solid;
  double _sx = 0, _sy = 0, _sz = 0, _cx = 0, _cy = 0, _cz = 0;
  double _radius = 0, _height = 0, _cell = 0;
  double _ox = 0, _oy = 0, _oz = 0, _rx = 0, _ry = 0, _rz = 0;
  double _esx = 0, _esy = 0, _esz = 0;
  String _model = '', _mesh = '';
  List<double>? _heights;
  int _heightCount = 0, _fieldSize = 0;

  void rememberCollider(Collider3D c, Vector3 scale, Object? solid) {
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

  bool colliderMatches(Collider3D c, Vector3 scale, Object? solid) =>
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
      _esx == scale.x &&
      _esy == scale.y &&
      _esz == scale.z &&
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

  void remember(RigidBody3D? r) {
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
    motionQuality = PhysicsSystem3D._quality(r);
  }

  bool matches(RigidBody3D? r) =>
      _hasRigid == (r != null) &&
      _type == (r?.bodyType ?? BodyType3D.static) &&
      _sensor == (r?.isSensor ?? false) &&
      _canSleep == (r?.canSleep ?? true) &&
      _lockRotation == (r?.lockRotation ?? false) &&
      _mass == (r?.mass ?? 0) &&
      _linearDamping == (r?.linearDamping ?? 0.05) &&
      _angularDamping == (r?.angularDamping ?? 0.05);

  static final Quaternion _scratch = Quaternion.identity();

  void rememberPose() {
    final p = transform.position;
    transform.rotationInto(_scratch);
    _x = p.x;
    _y = p.y;
    _z = p.z;
    _qx = _scratch.x;
    _qy = _scratch.y;
    _qz = _scratch.z;
    _qw = _scratch.w;
  }

  bool isAt(Vector3 p, Quaternion q) {
    const e = PhysicsSystem3D.moveEpsilon;
    if ((p.x - _x).abs() > e || (p.y - _y).abs() > e || (p.z - _z).abs() > e) {
      return false;
    }
    final dot = q.x * _qx + q.y * _qy + q.z * _qz + q.w * _qw;
    return dot.abs() > 1 - 1e-10;
  }

  /// Sets the transform's previous pose to the one saved before a gameplay
  /// move ([savePrevious]).
  void capturePreviousFromLast() {
    final t = transform;
    final p = t.position;
    final nx = p.x, ny = p.y, nz = p.z;
    t.rotationInto(_scratch);
    final nqx = _scratch.x,
        nqy = _scratch.y,
        nqz = _scratch.z,
        nqw = _scratch.w;
    p.setValues(_px, _py, _pz);
    t.setRotation(_scratch..setValues(_pqx, _pqy, _pqz, _pqw));
    t.capturePrevious();
    p.setValues(nx, ny, nz);
    t.setRotation(_scratch..setValues(nqx, nqy, nqz, nqw));
  }
}

/// An entity with a character, and the physics engine's character.
final class _CharacterLink {
  _CharacterLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late CharacterBody3D comp;
  int version = -1;
  int character = 0;
  int innerBody = 0;

  /// Its rotation at the end of the last move, once [turned].
  final Quaternion turn = Quaternion.identity();
  bool turned = false;

  double _radius = 0, _height = 0, _slope = 0, _mass = 0, _push = 0;
  int _layer = 0;
  bool _detectable = true;
  double _x = 0, _y = 0, _z = 0;

  void remember(CharacterBody3D c) {
    _radius = c.radius;
    _height = c.height;
    _slope = c.maxSlopeAngle;
    _mass = c.mass;
    _push = c.pushStrength;
    _layer = c.layer;
    _detectable = c.detectable;
  }

  bool matches(CharacterBody3D c) =>
      _radius == c.radius &&
      _height == c.height &&
      _slope == c.maxSlopeAngle &&
      _mass == c.mass &&
      _push == c.pushStrength &&
      _layer == c.layer &&
      _detectable == c.detectable;

  void rememberPosition(Vector3 p) {
    _x = p.x;
    _y = p.y;
    _z = p.z;
  }

  bool isAt(Vector3 p) {
    const e = PhysicsSystem3D.moveEpsilon;
    return (p.x - _x).abs() <= e &&
        (p.y - _y).abs() <= e &&
        (p.z - _z).abs() <= e;
  }
}

/// A joint component, and the physics engine's joint.
final class _JointLink {
  _JointLink(this.entity, this.comp);

  final Entity entity;
  final Joint3D comp;
  int version = -1;
  int joint = 0;
  _JointSignature? signature;
  bool enabled = true;
  MotorState3D motor = MotorState3D.off;
  double motorTarget = 0;
}

/// What a joint was made from, but its motor and on/off switch (those are
/// changed on the live joint).
final class _JointSignature {
  _JointSignature(this.bodyA, this.bodyB, this.values);

  factory _JointSignature.of(Joint3D c, int a, int b) => _JointSignature(a, b, [
    c.kind,
    c.connectedBody,
    c.anchor.x,
    c.anchor.y,
    c.anchor.z,
    ...switch (c) {
      HingeJoint3D h => [
        h.axis.x,
        h.axis.y,
        h.axis.z,
        h.useLimits,
        h.minAngle,
        h.maxAngle,
        h.friction,
        h.motorMaxTorque,
      ],
      SliderJoint3D s => [
        s.axis.x,
        s.axis.y,
        s.axis.z,
        s.useLimits,
        s.minPosition,
        s.maxPosition,
        s.friction,
        s.motorMaxForce,
      ],
      DistanceJoint3D d => [
        d.connectedAnchor.x,
        d.connectedAnchor.y,
        d.connectedAnchor.z,
        d.minDistance,
        d.maxDistance,
        d.springFrequency,
        d.springDamping,
      ],
      SixDofJoint3D x => [
        x.axis.x,
        x.axis.y,
        x.axis.z,
        x.normal.x,
        x.normal.y,
        x.normal.z,
        ...x.modes,
        x.translationMin.x,
        x.translationMin.y,
        x.translationMin.z,
        x.translationMax.x,
        x.translationMax.y,
        x.translationMax.z,
        x.rotationMin.x,
        x.rotationMin.y,
        x.rotationMin.z,
        x.rotationMax.x,
        x.rotationMax.y,
        x.rotationMax.z,
      ],
      _ => const <Object>[],
    },
  ]);

  final int bodyA, bodyB;
  final List<Object> values;

  @override
  bool operator ==(Object other) {
    if (other is! _JointSignature ||
        other.bodyA != bodyA ||
        other.bodyB != bodyB) {
      return false;
    }
    if (other.values.length != values.length) return false;
    for (var i = 0; i < values.length; i++) {
      if (other.values[i] != values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(bodyA, bodyB, values.length);
}
