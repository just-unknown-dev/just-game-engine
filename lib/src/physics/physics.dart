/// Physics — Movement, gravity, collision detection, and ray casting.
library;

export 'physics_layers.dart';

export 'package:just_physics_engine/just_physics_engine.dart'
    show
        Physics2DEngine,
        Box2DPhysicsEngine,
        Physics2DBody,
        Shape2D,
        Circle2DShape,
        Polygon2DShape,
        Rectangle2DShape,
        Capsule2DShape,
        Segment2DShape,
        Chain2DShape,
        RoundedPolygon2DShape,
        Ray2D,
        Ray2DHit,
        CircleCast2DHit,
        Joint2D,
        Joint2DKind,
        DistanceJoint2D,
        MouseJoint2D,
        WeldJoint2D,
        RevoluteJoint2D,
        Box2DJoint,
        // Added in just_physics_engine 1.3.0. Without these in the show list a
        // game cannot name a kinematic body or a one-way direction through the
        // engine's own barrel, even though RigidBody2DComponent and Collider2DComponent expose both.
        Body2DType,
        OneWayDirection,
        // What a CharacterBody2DComponent reads and is moved as.
        Ground2DState,
        Mover2DShape;
export 'physics_context.dart' show ContextPhysics;
export 'velocity_component.dart';
export 'physics_definitions.dart';
export 'physics_field_types.dart';
export 'body_rebuild.dart';

// 2-D physics: bodies, colliders, joints, queries and the system that
// steps them. 3-D physics (physics_3d/) is in package:just_game_engine/just_game_engine_3d.dart.
export 'physics_2d/physics_2d_components.dart';
export 'physics_2d/physics_2d_body_ref_component.dart';
export 'physics_2d/joint_2d_components.dart';
export 'physics_2d/collider_2d_geometry.dart';
export 'physics_2d/physics_2d_system.dart';
export 'physics_2d/physics_2d_joints.dart';
export 'physics_2d/physics_2d_characters.dart';
export 'physics_2d/physics_2d_events.dart';
export 'physics_2d/physics_2d_queries.dart';
export 'physics_2d/ray_tracer_2d.dart';
export 'physics_2d/collider_2d_debugger_system.dart';
export 'physics_2d/physics_2d_definitions.dart';
