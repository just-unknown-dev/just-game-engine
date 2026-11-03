/// Physics — Movement, gravity, collision detection, and ray casting.
library;

export 'physics_layers.dart';

export 'package:just_physics_engine/just_physics_engine.dart'
    show
        PhysicsEngine,
        Box2DPhysicsEngine,
        PhysicsBody,
        RigidBody,
        CollisionDetector,
        ForceManager,
        CollisionShape,
        CircleShape,
        PolygonShape,
        RectangleShape,
        CapsuleShape,
        SegmentShape,
        ChainShape,
        RoundedPolygonShape,
        CollisionManifold,
        SpatialGrid,
        BodyPair,
        Ray,
        RayBodyHit,
        ShapeCastResult,
        JointConstraint,
        JointType,
        DistanceJoint,
        MouseJoint,
        WeldJoint,
        RevoluteJoint,
        Box2DJoint,
        // Added in just_physics_engine 1.3.0. Without these in the show list a
        // game cannot name a kinematic body or a one-way direction through the
        // engine's own barrel, even though RigidBody2DComponent and Collider2DComponent expose both.
        BodyType,
        OneWayDirection,
        // What a CharacterBody2DComponent reads and is moved as.
        GroundState2D,
        MoverShape;
export 'physics_context.dart' show ContextPhysics;
export 'velocity_component.dart';
export 'physics_definitions.dart';
