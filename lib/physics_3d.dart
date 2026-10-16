/// 3-D physics for just_game_engine.
///
/// - [Physics3D]: give one to the engine (`EngineConfig(physics3D:
///   Physics3D())`) and it saves, loads and simulates the components below
///   on Jolt Physics. A game without one is 2-D only and carries none of
///   this.
/// - Components: [RigidBody3D], [Collider3D], [CharacterBody3D], and the
///   joints [FixedJoint3D], [PointJoint3D], [HingeJoint3D],
///   [SliderJoint3D], [DistanceJoint3D], [SixDofJoint3D].
/// - [PhysicsSystem3D], which steps the world.
/// - Events on the world's bus: [CollisionEnter3DEvent],
///   [CollisionStay3DEvent], [CollisionExit3DEvent], [SensorEnter3DEvent],
///   [SensorExit3DEvent].
/// - [Physics3DQueries]: rays, sweeps and overlaps answered in entities.
/// - just_physics_engine's 3-D side: [PhysicsEngine3D], [PhysicsWorld3D],
///   shapes, settings and results.
///
/// Units are metres; +Y is down, so gravity is (0, +9.81, 0).
library;

export 'package:just_physics_engine/physics_3d.dart' hide Quaternion, Vector3;

export 'src/physics_3d/camera_collision_3d.dart';
export 'src/physics_3d/collider_shapes_3d.dart';
export 'src/physics_3d/physics_3d.dart';
export 'src/physics_3d/physics_components_3d.dart';
export 'src/physics_3d/physics_definitions_3d.dart';
export 'src/physics_3d/physics_events_3d.dart';
export 'src/physics_3d/physics_queries_3d.dart';
export 'src/physics_3d/physics_system_3d.dart';
