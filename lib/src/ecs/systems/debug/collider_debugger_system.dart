/// Draws physics bodies and ray-cast colliders as outlines, for debugging.
library;

import 'dart:ui';

import 'package:just_physics_engine/just_physics_engine.dart' show PhysicsBody;

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../subsystems/camera/camera_system.dart' show Camera;
import '../../base/system_priorities.dart';
import '../physics/collider_geometry.dart';

/// Outlines every physics body ([PhysicsBodyRefComponent]) and every
/// [RaycastColliderComponent] in [color], above everything else
/// ([SystemPriorities.debug]).
///
/// Pass [camera] so the outlines follow the world view; see
/// `RenderSystem.cameraAppliedExternally` for why a system draws in screen
/// space otherwise.
class ColliderDebuggerSystem extends System {
  /// A debugger drawing everything in 1.5-pixel red outlines unless told
  /// otherwise.
  ColliderDebuggerSystem({
    this.camera,
    this.color = const Color(0xFFFF4D4D),
    this.strokeWidth = 1.5,
    this.includeStaticBodies = true,
    this.includeDynamicBodies = true,
    this.includeRaycastColliders = true,
  });

  /// The camera whose transform the outlines are drawn through; each
  /// render also sets its `viewportSize` to the canvas size. Null draws
  /// world positions as they are, through whatever transform the canvas
  /// already has.
  final Camera? camera;

  /// Colour of every outline.
  final Color color;

  /// Outline thickness, in the canvas's units — with a [camera], world
  /// units, so it scales with the zoom.
  final double strokeWidth;

  /// Whether to outline static bodies — those with a mass of zero or less.
  /// Only the body's outline is left out: a ray-cast collider on the same
  /// entity follows [includeRaycastColliders].
  final bool includeStaticBodies;

  /// Whether to outline dynamic bodies — those with a positive mass. Only
  /// the body's outline is left out: a ray-cast collider on the same
  /// entity follows [includeRaycastColliders].
  final bool includeDynamicBodies;

  /// Whether to outline [RaycastColliderComponent]s as `RaycastSystem`
  /// tests them: a circle of its radius when it has no width or height,
  /// otherwise an upright box (a missing side its radius either way of the
  /// centre); nothing for one with no size, which no ray hits.
  final bool includeRaycastColliders;

  @override
  int get priority => SystemPriorities.debug;

  @override
  List<Type> get requiredComponents => const [TransformComponent];

  @override
  void render(Canvas canvas, Size size) {
    if (camera != null) {
      camera!.viewportSize = size;
      canvas.save();
      camera!.applyTransform(canvas, size);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final physicsRef = entity.getComponent<PhysicsBodyRefComponent>();

      if (physicsRef != null) {
        final body = physicsRef.body;
        final isStatic = body.mass <= 0;
        if (isStatic ? includeStaticBodies : includeDynamicBodies) {
          _drawPhysicsBody(canvas, paint, body);
        }
      }

      if (includeRaycastColliders) {
        final raycast = entity.getComponent<RaycastColliderComponent>();
        if (raycast != null) {
          _drawRaycastCollider(canvas, paint, transform, raycast);
        }
      }
    });

    if (camera != null) {
      canvas.restore();
    }
  }

  /// [body]'s shapes where it is, as the simulation has them: a circle
  /// round its own centre, capsules, segments and chains too.
  void _drawPhysicsBody(Canvas canvas, Paint paint, PhysicsBody body) {
    canvas
      ..save()
      ..translate(body.position.x, body.position.y)
      ..rotate(body.angle);
    ColliderGeometry.paint(canvas, body.shape, paint);
    for (final shape in body.additionalShapes) {
      ColliderGeometry.paint(canvas, shape, paint);
    }
    canvas.restore();
  }

  void _drawRaycastCollider(
    Canvas canvas,
    Paint paint,
    TransformComponent transform,
    RaycastColliderComponent collider,
  ) {
    final center = Offset(transform.position.x, transform.position.y);
    final w = collider.width, h = collider.height, r = collider.radius;
    if (r <= 0 && w <= 0 && h <= 0) return;
    if (r > 0 && w == 0 && h == 0) {
      canvas.drawCircle(center, r, paint);
      return;
    }
    // Axis-aligned, as the ray test has it: the entity's angle plays no part.
    canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: w > 0 ? w : 2 * r,
        height: h > 0 ? h : 2 * r,
      ),
      paint,
    );
  }
}
