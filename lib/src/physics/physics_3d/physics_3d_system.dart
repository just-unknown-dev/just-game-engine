import 'dart:math' as math;

import 'package:just_physics_engine/physics_3d.dart';

import '../../ecs/ecs.dart';
import 'collider_3d_shapes.dart';
import 'physics_3d_bodies.dart';
import 'physics_3d_characters.dart';
import 'physics_3d_components.dart';
import 'physics_3d_contacts.dart';
import 'physics_3d_events.dart';
import 'physics_3d_joints.dart';

/// Steps a [PhysicsWorld3D] and keeps it in step with the ECS: the 3-D
/// counterpart of the engine's 2-D `Physics2DSystem` (a 3-D game leaves that
/// one out), split the same way into bodies, joints, characters and
/// contacts.
///
/// Each update it
/// 1. makes, rebuilds and removes bodies for entities with a [Collider3DComponent]
///    (a [RigidBody3DComponent] says how they move; without one they are static),
///    and sends what gameplay did: forces, impulses and velocities queued on a
///    [RigidBody3DComponent], and transforms written by hand — a teleport, or for a
///    kinematic body a move the physics carries what it touches along;
/// 2. makes, rebuilds and removes the joints for [Joint3DComponent]s;
/// 3. moves each [CharacterBody3DComponent], then steps the world;
/// 4. writes the moved bodies' poses back into their [TransformComponent]s,
///    after `capturePrevious()` so the renderer interpolates between steps;
/// 5. fires [CollisionEnter3DEvent], [CollisionExit3DEvent],
///    [SensorEnter3DEvent] and the rest on the world's event bus.
///
/// It runs at [SystemPriorities.physics] (90), after input and player
/// control. Taking it out of its world or disposing it removes everything
/// it made from [physics]; the world itself belongs to whoever made it.
///
/// The collision layers a world keeps apart are fixed when it is made
/// ([PhysicsWorldSettings3D.layerMasks]): just_physics_engine 1.4.1's
/// [PhysicsWorld3D] cannot change them later, so a grid edited while a 3-D
/// scene plays (`EngineContext.physicsLayers`) reaches the next world made,
/// not this one. A body's own layer can change at any time.
class Physics3DSystem extends System {
  /// A system stepping [physics]; mesh and hull colliders take their
  /// triangles from [geometry].
  Physics3DSystem(PhysicsWorld3D physics, {Collider3DGeometry? geometry})
    : _physics = physics,
      _create = null,
      shapes = Collider3DShapes(geometry: geometry) {
    priority = SystemPriorities.physics;
  }

  /// A system that makes its world with [create] only when the first 3-D
  /// body or character appears. Until then an update costs a structure
  /// check and nothing else, and there is no world at all — no worker
  /// threads, no tables sized for thousands of bodies — so a game whose 3-D
  /// scenes come later (a 2-D menu first) pays nothing for them.
  Physics3DSystem.lazy(
    PhysicsWorld3D Function() create, {
    Collider3DGeometry? geometry,
  }) : _physics = null,
       _create = create,
       shapes = Collider3DShapes(geometry: geometry) {
    priority = SystemPriorities.physics;
  }

  PhysicsWorld3D? _physics;
  final PhysicsWorld3D Function()? _create;

  /// The world it steps; a [Physics3DSystem.lazy] system makes it now if it
  /// has not yet.
  PhysicsWorld3D get physics => _physics ??= _create!();

  /// Whether the world exists (always, unless made with
  /// [Physics3DSystem.lazy] and still waiting for its first body).
  bool get hasWorld => _physics != null;

  /// Turns colliders into shapes.
  final Collider3DShapes shapes;

  /// One collision pass per this much of a step; a longer step gets more.
  static const double collisionStep = 1 / 60;

  /// Below this a transform is where the system left it (metres).
  static const double moveEpsilon = moveEpsilon3D;

  @override
  List<Type> get requiredComponents => const [TransformComponent];

  /// Every body this system made, characters' inner bodies too, by handle:
  /// what turns an event's body back into its entity.
  final Map<int, Entity> _entityByBody = {};

  late final Physics3DContacts _contacts = Physics3DContacts(
    () => physics,
    _entityByBody,
    isSensor: (entity) => _bodies.isSensor(entity),
  );

  late final Physics3DBodies _bodies = Physics3DBodies(
    () => physics,
    shapes,
    _entityByBody,
    onBodyGone: _forgetBody,
  );

  late final Physics3DJoints _joints = Physics3DJoints(
    () => physics,
    _bodies.bodyOf,
  );

  late final Physics3DCharacters _characters = Physics3DCharacters(
    () => physics,
    _entityByBody,
    onBodyGone: _forgetBody,
  );

  void _forgetBody(int body, Entity entity, {required bool rebuilt}) =>
      _contacts.forgetBody(body, entity, rebuilt: rebuilt);

  int _seenStructureVersion = -1;
  int _stepIndex = 0;

  /// The entity whose body, or character's body, [body] is; null for one
  /// this system did not make.
  Entity? entityOf(int body) => _entityByBody[body];

  /// [entity]'s body, or 0.
  int bodyOf(Entity entity) => _bodies.bodyOf(entity);

  /// [entity]'s character, or 0.
  int characterOf(Entity entity) => _characters.characterOf(entity);

  /// [model] was loaded again: its mesh and hull colliders take its new
  /// triangles. Call once they are there — the `ModelAsset` at that path
  /// answers with them — and each such body is made again, with no enter
  /// or exit for what it touches; until the new triangles arrive, a body
  /// keeps its old shape.
  void reloadModel(String model) => _bodies.reloadModel(model);

  @override
  void update(double deltaTime) {
    if (_physics?.isDisposed ?? false) return;
    _refresh();
    // Nothing 3-D yet: no world to make, step or read.
    if (_physics == null && _bodies.isEmpty && _characters.isEmpty) return;
    _bodies.sync(deltaTime);
    _joints.sync(world);
    if (deltaTime > 0) _characters.move(deltaTime);
    if (deltaTime > 0) {
      physics.step(
        deltaTime,
        collisionSteps: math.max(1, (deltaTime / collisionStep - 1e-6).ceil()),
      );
      _stepIndex++;
    }
    _bodies.readBack(_stepIndex);
    _joints.readBack();
    _contacts.dispatch(world.events, stepped: deltaTime > 0);
  }

  @override
  void onRemovedFromWorld() => _removeAll();

  @override
  void dispose() => _removeAll();

  /// What [_refresh] reads: a change to what any of them matches is a
  /// change to the links.
  static const List<List<Type>> _linkQueries = [
    [TransformComponent, Collider3DComponent],
    [TransformComponent, CharacterBody3DComponent],
    [TransformComponent, FixedJoint3DComponent],
    [TransformComponent, PointJoint3DComponent],
    [TransformComponent, HingeJoint3DComponent],
    [TransformComponent, SliderJoint3DComponent],
    [TransformComponent, DistanceJoint3DComponent],
    [TransformComponent, SixDofJoint3DComponent],
  ];

  /// The largest of [_linkQueries]' versions ([World.queryVersion]).
  int _linksVersion() {
    var version = -1;
    for (final query in _linkQueries) {
      final v = world.queryVersion(query);
      if (v > version) version = v;
    }
    return version;
  }

  /// Brings the links up to date when what they are made from changed.
  void _refresh() {
    final version = _linksVersion();
    if (version == _seenStructureVersion) return;
    _seenStructureVersion = version;
    _bodies.refresh(world, version);
    _characters.refresh(world, version);
    _joints.refresh(world, version);
  }

  void _removeAll() {
    final physics = _physics;
    final worldGone = physics == null || physics.isDisposed;
    _joints.removeAll(worldGone: worldGone);
    _characters.removeAll(worldGone: worldGone);
    _bodies.removeAll(worldGone: worldGone);
    _entityByBody.clear();
    _contacts.clear();
    _seenStructureVersion = -1;
  }
}
