/// Physics — Movement, gravity, collision detection, and ray casting.
library;

export 'package:just_physics_engine/just_physics_engine.dart'
    show
        PhysicsEngine,
        PhysicsBody,
        RigidBody,
        CollisionDetector,
        ForceManager,
        CollisionShape,
        CircleShape,
        PolygonShape,
        RectangleShape,
        CollisionManifold,
        SpatialGrid,
        BodyPair,
        Vector2Extension,
        PhysicsEngine3D,
        PhysicsBody3D,
        SphereShape3D,
        BoxShape3D;
export 'impl/ray_casting.dart';
