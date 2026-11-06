/// Draws the 2-D colliders and characters as outlines, for debugging.
library;

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import '../../ecs/ecs.dart';
import '../../interfaces/game_camera.dart';
import 'collider_2d_geometry.dart';
import 'physics_2d_components.dart';
import 'physics_2d_body_ref_component.dart';

/// The engine's one collider drawer: outlines every [Collider2DComponent]
/// as the simulation has it — offset, scaled and turned with its body —
/// coloured by what kind of body it is ([paintFor]), every
/// [CharacterBody2DComponent]'s shape and every body made outside the ECS
/// (a [Physics2DBodyRefComponent] with no collider), above everything else
/// ([SystemPriorities.debug]).
///
/// `GameWidget(showDebug: true)` adds one, and an editor adds one while it
/// shows colliders: the same scene is outlined the same way in both. A
/// collider that has no body yet — one just added, a scene not yet played —
/// is drawn from its component. A collider's own
/// [Collider2DComponent.showDebugOutline] has the last word, after
/// [outlineFilter].
///
/// Pass [camera] so the outlines follow the world view; see
/// `RenderSystem.cameraAppliedExternally` for why a system draws in screen
/// space otherwise.
class Collider2DDebuggerSystem extends System {
  /// A debugger outlining everything, [strokeWidth] wide.
  Collider2DDebuggerSystem({
    this.camera,
    this.strokeWidth = 2.0,
    this.includeStaticBodies = true,
    this.includeDynamicBodies = true,
    this.includeCharacters = true,
    this.outlineFilter,
  });

  /// The camera whose transform the outlines are drawn through; each
  /// render also sets its `viewportSize` to the canvas size. Null draws
  /// world positions as they are, through whatever transform the canvas
  /// already has.
  final GameCamera? camera;

  /// Outline thickness, in the canvas's units — with a [camera], world
  /// units, so it scales with the zoom. A sensor's is three quarters of it.
  final double strokeWidth;

  /// Whether to outline static bodies (and colliders with no rigid body,
  /// which are static).
  final bool includeStaticBodies;

  /// Whether to outline bodies that move — dynamic and kinematic ones.
  final bool includeDynamicBodies;

  /// Whether to outline each [CharacterBody2DComponent]'s shape where it is:
  /// solid on the ground, faded in the air.
  final bool includeCharacters;

  /// Which entities are outlined: all of them when null. An editor leaves
  /// out what it hides.
  bool Function(Entity entity)? outlineFilter;

  @override
  int get priority => SystemPriorities.debug;

  @override
  List<Type> get requiredComponents => const [TransformComponent];

  // One outline per shape, kept while the shape lives: a body's shape never
  // changes (a new one is made), so the outlines of bodies drawn every
  // frame are listed into native paths once.
  final Expando<Path> _paths = Expando('collider outlines');

  Paint _stroke(Color color, [double scale = 1]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth * scale;

  late final Paint _staticPaint = _stroke(Colors.blue);
  late final Paint _kinematicPaint = _stroke(Colors.orange);
  late final Paint _dynamicPaint = _stroke(Colors.green);
  late final Paint _sleepingPaint = _stroke(
    Colors.green.withValues(alpha: 0.4),
  );
  late final Paint _sensorPaint = _stroke(Colors.yellow, 0.75);
  late final Paint _characterPaint = _stroke(Colors.lightBlueAccent);
  late final Paint _characterAirPaint = _stroke(
    Colors.lightBlueAccent.withValues(alpha: 0.5),
  );

  /// How a collider of [rigid] (none: a static body) is outlined: a sensor
  /// yellow, a static body blue, a kinematic one orange, a dynamic one
  /// green — faded while its [body] sleeps.
  Paint paintFor(RigidBody2DComponent? rigid, [Physics2DBody? body]) {
    if (rigid == null) return _staticPaint;
    if (rigid.isSensor) return _sensorPaint;
    return switch (rigid.bodyType) {
      Body2DType.static => _staticPaint,
      Body2DType.kinematic => _kinematicPaint,
      Body2DType.dynamic =>
        body != null && !body.isAwake ? _sleepingPaint : _dynamicPaint,
    };
  }

  /// [paintFor] a body with no rigid body component, by the body itself.
  Paint _paintForBody(Physics2DBody body) {
    if (body.isSensor) return _sensorPaint;
    return switch (body.effectiveBodyType) {
      Body2DType.static => _staticPaint,
      Body2DType.kinematic => _kinematicPaint,
      Body2DType.dynamic => body.isAwake ? _dynamicPaint : _sleepingPaint,
    };
  }

  /// Whether a body that [isStatic] (or not) is outlined at all.
  bool _includes(bool isStatic) =>
      isStatic ? includeStaticBodies : includeDynamicBodies;

  @override
  void render(Canvas canvas, Size size) {
    final camera = this.camera;
    if (camera != null) {
      camera.viewportSize = size;
      canvas.save();
      camera.applyTransform(canvas, size);
    }
    _drawColliders(canvas);
    _drawBodies(canvas);
    if (includeCharacters) _drawCharacters(canvas);
    if (camera != null) canvas.restore();
  }

  /// Each collider as the simulation has it, at its entity: its body's
  /// shape once it has one, its component's until then.
  void _drawColliders(Canvas canvas) {
    final filter = outlineFilter;
    final definitions = world.context.definitions;
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      Collider2DComponent,
    ])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(Collider2DComponent)!;
      final rigids = archetype.getColumn(RigidBody2DComponent);
      final refs = archetype.getColumn(Physics2DBodyRefComponent);
      for (var row = 0; row < transforms.length; row++) {
        final collider = colliders[row] as Collider2DComponent;
        if (!collider.showDebugOutline) continue;
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        if (filter != null && !filter(entity)) continue;
        final rigid = rigids?[row] as RigidBody2DComponent?;
        final body = (refs?[row] as Physics2DBodyRefComponent?)?.body;
        if (!_includes(body?.isStatic ?? (rigid?.isStatic ?? true))) continue;
        final transform = transforms[row] as TransformComponent;
        final shape =
            body?.shape ??
            Collider2DGeometry.of(collider, transform, entity, definitions);
        if (shape == null) continue;
        canvas
          ..save()
          ..translate(transform.position.x, transform.position.y)
          ..rotate(transform.angle);
        final paint = paintFor(rigid, body);
        Collider2DGeometry.paint(canvas, shape, paint, paths: _paths);
        if (body != null) {
          for (final extra in body.additionalShapes) {
            Collider2DGeometry.paint(canvas, extra, paint, paths: _paths);
          }
        }
        canvas.restore();
      }
    }
  }

  /// Bodies made outside the ECS, named on an entity with no collider: as
  /// the simulation has them, where they are.
  void _drawBodies(Canvas canvas) {
    final filter = outlineFilter;
    for (final archetype in world.queryArchetypes(const [
      Physics2DBodyRefComponent,
    ])) {
      if (archetype.types.contains(Collider2DComponent)) continue;
      final refs = archetype.getColumn(Physics2DBodyRefComponent)!;
      for (var row = 0; row < refs.length; row++) {
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        final body = (refs[row] as Physics2DBodyRefComponent).body;
        if (!_includes(body.isStatic)) continue;
        if (filter != null && !filter(entity)) continue;
        final paint = _paintForBody(body);
        canvas
          ..save()
          ..translate(body.position.x, body.position.y)
          ..rotate(body.angle);
        Collider2DGeometry.paint(canvas, body.shape, paint, paths: _paths);
        for (final extra in body.additionalShapes) {
          Collider2DGeometry.paint(canvas, extra, paint, paths: _paths);
        }
        canvas.restore();
      }
    }
  }

  /// Each character's shape where it is, moved yet or not.
  void _drawCharacters(Canvas canvas) {
    final filter = outlineFilter;
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      CharacterBody2DComponent,
    ])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final characters = archetype.getColumn(CharacterBody2DComponent)!;
      for (var row = 0; row < transforms.length; row++) {
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        if (filter != null && !filter(entity)) continue;
        final transform = transforms[row] as TransformComponent;
        final character = characters[row] as CharacterBody2DComponent;
        final shape = character.moverShape;
        final p = shape.points;
        final outline = p.length == 1
            ? Circle2DShape(shape.radius)
            : p.length == 2
            ? Capsule2DShape(center1: p[0], center2: p[1], radius: shape.radius)
            : RoundedPolygon2DShape(p, shape.radius);
        canvas
          ..save()
          ..translate(
            transform.position.x + character.offset.dx,
            transform.position.y + character.offset.dy,
          );
        Collider2DGeometry.paint(
          canvas,
          outline,
          character.isGrounded ? _characterPaint : _characterAirPaint,
        );
        canvas.restore();
      }
    }
  }
}
