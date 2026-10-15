import 'package:just_physics_engine/physics_3d.dart';

import '../core/engine.dart';
import '../core/engine_service.dart';
import '../ecs/base/engine_context.dart';
import '../ecs/systems/camera/camera_brain.dart';
import 'camera_collision_3d.dart';
import 'collider_shapes_3d.dart';
import 'physics_components_3d.dart';
import 'physics_definitions_3d.dart';
import 'physics_queries_3d.dart';
import 'physics_system_3d.dart';

/// 3-D physics for an engine. Give one to the engine and its 3-D physics
/// components — [RigidBody3D], [Collider3D], [CharacterBody3D] and the
/// joints — are saved, loaded, offered in the editor's 3-D scenes and
/// simulated:
///
/// ```dart
/// Engine(config: EngineConfig(physics3D: Physics3D()));
/// ```
///
/// with Jolt built into the app, in its pubspec:
///
/// ```yaml
/// hooks:
///   user_defines:
///     just_jolt:
///       build: true
/// ```
///
/// A game without one is 2-D only, and its release build carries none of
/// the 3-D code: all of it is reached through this object.
///
/// As the engine is made it registers the components and the camera's
/// collision stage ([CameraCollisionStage]); as the engine initializes it
/// starts the physics engine — [PhysicsEngineFactory.create3D] (Jolt)
/// unless [engine] was given — and adds [system]. The world itself is made
/// only when the first 3-D body or character appears, so a game whose 3-D
/// scenes come later holds no world, worker threads or tables until then.
///
/// Where 3-D physics cannot run — the web, a 32-bit Android ABI, an app
/// whose pubspec did not ask for Jolt — initializing the engine fails with an
/// [EngineInitException] whose stage is `service:Physics3D` and whose
/// [EngineInitException.cause] is a [Physics3DUnsupportedError] naming the
/// reason. [isSupported] asks first.
///
/// The collision layers are the project's (`assets/project/physics.json`,
/// read into `EngineContext.physicsLayers`); mesh and hull colliders take
/// their triangles from the engine's loaded models.
final class Physics3D implements RefreshableExtension, EngineService {
  /// 3-D physics on [engine], or on the platform's physics engine when that
  /// is null, with [workerThreads] threads in its job system (below 0:
  /// cores minus one). [gravity] is (0, 9.81, 0) — down — unless given.
  /// [addSystem] false leaves adding [system] to a world to the game.
  Physics3D({
    PhysicsEngine3D? engine,
    Vector3? gravity,
    this.workerThreads = -1,
    this.maxBodies = 10240,
    this.reportContactStay = false,
    this.reportActivation = false,
    this.addSystem = true,
  }) : _given = engine,
       gravity =
           gravity ?? Vector3(0, PhysicsWorldSettings3D.standardGravity, 0);

  /// Registers the 3-D physics components into [context], so scenes holding
  /// them load and save — for tools that read and write 3-D scenes without
  /// simulating them. Giving the engine a [Physics3D] does this already.
  static void registerSchemas(EngineContext context) =>
      context.definitions.registerAll(Physics3DSchemas.all, ifAbsent: true);

  /// Whether 3-D physics can run here, so a game can show something else
  /// instead of failing to start.
  static bool get isSupported => PhysicsEngineFactory.supports3D;

  /// Why 3-D physics cannot run here, or null when it can.
  static String? get unsupportedReason =>
      PhysicsEngineFactory.unavailable3DReason;

  final PhysicsEngine3D? _given;

  /// Gravity the world starts with.
  final Vector3 gravity;

  /// Threads in the physics engine's job system, when it is the platform's.
  final int workerThreads;

  /// The most bodies the world holds.
  final int maxBodies;

  /// Whether touching pairs fire `CollisionStay3DEvent` every step.
  final bool reportContactStay;

  /// Whether bodies report falling asleep and waking.
  final bool reportActivation;

  /// Whether starting adds [system] to the engine's world.
  final bool addSystem;

  Engine? _game;
  PhysicsEngine3D? _engine;
  PhysicsSystem3D? _system;
  Physics3DQueries? _queries;

  /// Whether the engine started it.
  bool get isStarted => _system != null;

  /// The physics engine it simulates on; throws before it starts.
  PhysicsEngine3D get engine => _engine ?? (throw StateError(_notStarted));

  /// The system stepping the world; throws before it starts.
  PhysicsSystem3D get system => _system ?? (throw StateError(_notStarted));

  /// Rays, sweeps and overlaps, answered in entities; throws before it
  /// starts. They find nothing while there is no world yet.
  Physics3DQueries get queries => _queries ?? (throw StateError(_notStarted));

  /// Whether the world exists yet (it is made with the first 3-D body).
  bool get hasWorld => _system?.hasWorld ?? false;

  /// The world, made now if it was still waiting for its first body; throws
  /// before it starts.
  PhysicsWorld3D get world => system.physics;

  /// The model at [model] was loaded again (its file changed): its mesh and
  /// hull colliders take its new triangles ([PhysicsSystem3D.reloadModel]).
  /// Call once the engine's `ModelAsset` at that path answers with them — a
  /// renderer does, when it reloads a model. Does nothing before it starts.
  void reloadModel(String model) => _system?.reloadModel(model);

  static const String _notStarted =
      'Physics3D has not started: give it to the engine '
      '(EngineConfig(physics3D: ...)) and initialize the engine.';

  // ── ContextExtension ──────────────────────────────────────────────────

  @override
  String get id => 'physics_3d';

  @override
  void install(EngineContext context) {
    registerSchemas(context);
    // Every brain of the engine keeps its cameras out of walls.
    CameraRegistries.of(
      context,
    ).stages.register(const CameraCollisionStage(), override: true);
  }

  @override
  void refresh(EngineContext context) {
    context.definitions.refresh(Physics3DSchemas.all);
    CameraRegistries.of(
      context,
    ).stages.register(const CameraCollisionStage(), override: true);
  }

  // ── EngineService ─────────────────────────────────────────────────────

  @override
  Future<void> start(ServiceContext context) async {
    final physics =
        _given ?? PhysicsEngineFactory.create3D(workerThreads: workerThreads);
    final reason = physics.unavailableReason;
    if (reason != null) throw Physics3DUnsupportedError(reason);
    final game = context.engine;
    final engineContext = context.context;
    final system = PhysicsSystem3D.lazy(() {
      final layers = engineContext.physicsLayers;
      return physics.createWorld(
        PhysicsWorldSettings3D(
          gravity: gravity,
          layerMasks: [for (var i = 0; i < 16; i++) layers.maskOf(i)],
          maxBodies: maxBodies,
          reportContactStay: reportContactStay,
          reportActivation: reportActivation,
        ),
      );
    }, geometry: AssetColliderGeometry3D(game.assets));
    _game = game;
    _engine = physics;
    _system = system;
    _queries = Physics3DQueries(system);
    if (addSystem) game.world.addSystem(system);
  }

  @override
  Future<void> stop() async {
    final game = _game;
    final system = _system;
    if (game != null && system != null && addSystem) {
      // Takes out everything it made while the world still exists.
      game.world.removeSystem(system);
    }
    if (system != null && system.hasWorld) system.physics.dispose();
    _game = null;
    _engine = null;
    _system = null;
    _queries = null;
  }
}
