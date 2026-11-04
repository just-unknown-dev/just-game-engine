library;

import 'package:just_physics_engine/just_physics_engine.dart';

import '../../ecs/ecs.dart';
import '../velocity_component.dart';
import 'physics_2d_bodies.dart';
import 'physics_2d_characters.dart';
import 'physics_2d_components.dart';
import 'physics_2d_contacts.dart';
import 'physics_2d_events.dart';
import 'physics_2d_joints.dart';
import 'physics_2d_queries.dart';

/// Physics system — the ECS front end for [Physics2DEngine], in step with
/// the 3-D `Physics3DSystem`.
///
/// Owns the [Physics2DBody] lifecycle for every entity with a [Collider2DComponent]:
/// its [RigidBody2DComponent] says how it moves (a collider alone is a static body).
/// Each update it
/// 1. syncs component state into the bodies — makes, rebuilds and removes
///    them, applies the forces, impulses and velocities gameplay asked for
///    ([RigidBody2DComponent.addForce] and the rest), teleports or carries
///    what gameplay moved by its transform;
/// 2. makes, rebuilds and removes the joints between them ([Physics2DJoints]);
/// 3. moves every [CharacterBody2DComponent] ([Physics2DCharacters]): a
///    character's own body is a kinematic one, so its events are those of a
///    kinematic body;
/// 4. steps [physics];
/// 5. syncs the result back into [TransformComponent], [VelocityComponent]
///    and the rigid body's runtime fields;
/// 6. fires [CollisionEnter2DEvent], [CollisionStay2DEvent] (with
///    [reportContactStay]), [CollisionExit2DEvent], [SensorEnter2DEvent] and
///    [SensorExit2DEvent] on [World.events].
///
/// [physics] is stepped *here*, inline, rather than as a separate `Engine`
/// update task — that keeps this frame's gameplay-set velocity (e.g. from a
/// player-control system running earlier in the same ECS pass) reaching the
/// physics step the same frame it was set, instead of lagging a frame behind.
///
/// **Sleep.** A body at rest may fall asleep, as the physics engine decides,
/// and stays asleep until something disturbs it. Anything the ECS does to a
/// body wakes it: a velocity different from the one the last step left
/// (written to [VelocityComponent] or to the body), a teleport through
/// [TransformComponent], a force, impulse or torque waiting to be applied, a
/// changed [RigidBody2DComponent] or [Collider2DComponent] setting, the body coming back from
/// view culling, or a change of gravity. A player pressing a direction or
/// jump therefore always moves at once.
///
/// **Removal.** Taking the system out of its world ([World.removeSystem],
/// [World.clearSystems]) or disposing it removes every body and joint it
/// made from [physics]. The engine is shared, and bodies left behind went on
/// colliding as invisible ghosts.
///
/// Its colliders are drawn, for debugging, by a `Collider2DDebuggerSystem`.
class Physics2DSystem extends System {
  /// [physics] is the single physics implementation this system drives —
  /// pass `engine.physics`. On native platforms that's the Box2D FFI
  /// backend; on web, the pure-Dart backend. Both share the same API.
  Physics2DSystem(this.physics, {this.reportContactStay = false});

  /// The subsystem physics engine this system steps and syncs against.
  final Physics2DEngine physics;

  /// Whether [CollisionStay2DEvent] is fired, each step, for every pair of
  /// bodies still touching. Off by default: most games need only enter and
  /// exit.
  bool reportContactStay;

  @override
  int get priority => SystemPriorities.physics;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    Collider2DComponent,
  ];

  /// Rays, sweeps and overlaps against this system's bodies, answered in
  /// entities — the 2-D twin of `engine.physics3D!.queries`.
  late final Physics2DQueries queries = Physics2DQueries(this);

  /// Every body this system keeps in the simulation, characters' too, by
  /// entity: what turns a polled body back into its entity.
  final Map<Physics2DBody, Entity> _entities = {};

  late final Physics2DContacts _contacts = Physics2DContacts(
    physics,
    _entities,
  );

  late final Physics2DBodies _bodies = Physics2DBodies(
    physics,
    _entities,
    onBodyGone: (body, entity, {required rebuilt}) =>
        _contacts.forgetBody(body, entity, rebuilt: rebuilt),
  );

  /// The joints between the bodies.
  late final Physics2DJoints _joints = Physics2DJoints(
    physics,
    onQuiet: (a, b, {required joined}) => _contacts.jointedPair(
      a,
      b,
      joined: joined,
      events: joined ? world.events : null,
    ),
  );

  /// The characters this system moves.
  late final Physics2DCharacters _characters = Physics2DCharacters(
    physics,
    onBody: (body, entity) => _entities[body] = entity,
    onBodyGone: (body, {required rebuilt}) =>
        _contacts.forgetBody(body, _entities.remove(body), rebuilt: rebuilt),
  );

  /// Whether the world had no bodies at the last update.
  bool _wasEmpty = false;

  /// The entity [body] belongs to while this system keeps it in the
  /// simulation — null for a body it did not make, or one it has removed.
  Entity? entityOf(Physics2DBody body) => _entities[body];

  /// The simulated body of [entity], or null while it has none — for a
  /// character, the body sensors and rays see it by.
  Physics2DBody? bodyOf(Entity entity) =>
      _bodies.bodyOf(entity) ?? _characters.bodyOf(entity);

  @override
  void update(double deltaTime) {
    _bodies.syncIn(world, deltaTime);
    // Joints before the step, so one made or made again — a body rebuilt
    // for a new scale took its joints with it — holds from this step on.
    _joints.sync(world);
    if (deltaTime > 0) _characters.move(world, deltaTime, entityOf);
    // A world with no bodies (a 3-D scene, a menu) is not stepped; the step
    // after the last body goes still runs, so its end events get through.
    final empty = physics.bodyCount == 0;
    var stepped = false;
    if (!(empty && _wasEmpty)) {
      final alpha = physics.alpha;
      physics.update(deltaTime);
      // Whether a step ran: under a fixed step a frame may run none (a
      // 120 Hz display runs one every other frame), and a body made again
      // is only looked for by the next one.
      stepped = physics.fixedTimestep
          ? alpha + deltaTime / Physics2DEngine.fixedDeltaTime - physics.alpha >
                0.5
          : deltaTime > 0;
    }
    _wasEmpty = empty;
    _bodies.syncOut(stepped: stepped);
    _contacts.dispatch(
      world.events,
      stepped: stepped,
      reportStay: reportContactStay,
    );
  }

  @override
  void onRemovedFromWorld() => _removeAll();

  @override
  void dispose() => _removeAll();

  void _removeAll() {
    _joints.removeAll();
    _bodies.removeAll();
    _characters.removeAll();
    _entities.clear();
    _contacts.clear();
  }
}
