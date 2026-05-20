import 'dart:math' as math;
import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart';

class ColliderDebuggerSystem extends System {
  ColliderDebuggerSystem({
    this.camera,
    this.color = const Color(0xFFFF4D4D),
    this.strokeWidth = 1.5,
    this.includeStaticBodies = true,
    this.includeDynamicBodies = true,
    this.includeRaycastColliders = true,
  });

  final Camera? camera;
  final Color color;
  final double strokeWidth;
  final bool includeStaticBodies;
  final bool includeDynamicBodies;
  final bool includeRaycastColliders;

  @override
  List<Type> get requiredComponents => [TransformComponent];

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
        if ((isStatic && !includeStaticBodies) ||
            (!isStatic && !includeDynamicBodies)) {
          return;
        }
        _drawPhysicsBody(canvas, paint, body);
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

  void _drawPhysicsBody(Canvas canvas, Paint paint, PhysicsBody body) {
    if (body.shape is CircleShape) {
      final circle = body.shape as CircleShape;
      canvas.drawCircle(
        Offset(body.position.x, body.position.y),
        circle.radius,
        paint,
      );
      return;
    }

    if (body.shape is RectangleShape) {
      final rect = body.shape as RectangleShape;
      canvas.save();
      canvas.translate(body.position.x, body.position.y);
      canvas.rotate(body.angle);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: rect.width,
          height: rect.height,
        ),
        paint,
      );
      canvas.restore();
      return;
    }

    if (body.shape is PolygonShape) {
      final polygon = body.shape as PolygonShape;
      final c = math.cos(body.angle);
      final s = math.sin(body.angle);
      final path = Path();
      final vertices = polygon.vertices.map((v) {
        final rx = v.dx * c - v.dy * s;
        final ry = v.dx * s + v.dy * c;
        return Offset(body.position.x + rx, body.position.y + ry);
      });
      path.addPolygon(vertices.toList(), true);
      canvas.drawPath(path, paint);
    }
  }

  void _drawRaycastCollider(
    Canvas canvas,
    Paint paint,
    TransformComponent transform,
    RaycastColliderComponent collider,
  ) {
    final center = Offset(transform.position.x, transform.position.y);
    if (collider.width > 0 && collider.height > 0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(transform.rotation);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: collider.width,
          height: collider.height,
        ),
        paint,
      );
      canvas.restore();
      return;
    }

    final radius = collider.radius > 0 ? collider.radius : 8.0;
    canvas.drawCircle(center, radius, paint);
  }
}
