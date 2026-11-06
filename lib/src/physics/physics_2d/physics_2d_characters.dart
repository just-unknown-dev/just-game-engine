library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:just_dart/just_dart.dart' show Vector2;
import 'package:just_physics_engine/just_physics_engine.dart';

import '../physics_layers.dart';
import '../../ecs/ecs.dart';
import '../../rendering/culling/cull_state_component.dart';
import 'physics_2d_components.dart';
import '../physics_context.dart';

/// The [CharacterBody2DComponent] side of `Physics2DSystem`, which owns one and runs
/// it each update before stepping — as the 3-D `Physics3DSystem`
/// moves its characters.
///
/// Each character is moved by [CharacterMover2D] through the world as it was
/// after the last step. While [CharacterBody2DComponent.detectable], it also keeps a
/// kinematic body where it is, so sensors detect it, rays hit it and dynamic
/// bodies bump into it: that body's contacts are the character's collision
/// events, as in 3-D (a kinematic body touches dynamic bodies and sensors,
/// never static ones — read [CharacterBody2DComponent.groundEntity] for those).
final class Physics2DCharacters {
  /// Characters in [physics]'s world. [onBody] and [onBodyGone] tell the
  /// system about each character's own body, so events and queries name
  /// the character.
  Physics2DCharacters(
    this.physics, {
    required this.onBody,
    required this.onBodyGone,
  });

  /// The world the characters move through.
  final Physics2DEngine physics;

  /// A character's body was made.
  final void Function(Physics2DBody body, Entity entity) onBody;

  /// A character's body is gone: `rebuilt` when a new one takes its place
  /// at once (what it is made of changed), not when the character is.
  final void Function(Physics2DBody body, {required bool rebuilt}) onBodyGone;

  late final CharacterMover2D _mover = CharacterMover2D(physics);
  final Map<Entity, _CharacterLink> _links = {};
  final List<_CharacterLink> _active = [];
  int _seenVersion = -1;

  /// Each character's body by entity, while it has one.
  Physics2DBody? bodyOf(Entity entity) => _links[entity]?.body;

  /// Moves every character in [world] by [dt] seconds. [entityOf]
  /// names the entity of a body it stands on.
  void move(
    World world,
    double dt,
    Entity? Function(Physics2DBody body) entityOf,
  ) {
    _refresh(world);
    if (_active.isEmpty) return;

    final gx = physics.gravity.x, gy = physics.gravity.y;
    final g = math.sqrt(gx * gx + gy * gy);
    final up = g == 0 ? const Offset(0, -1) : Offset(-gx / g, -gy / g);
    final layers = world.context.physicsLayers;

    for (final link in _active) {
      final entity = link.entity, comp = link.comp, transform = link.transform;
      if (!entity.isActiveInHierarchy) {
        _removeBody(link);
        continue;
      }
      final category = 1 << PhysicsLayers.clampLayer(comp.layer);
      final mask =
          (comp.collidesWith ?? layers.maskOf(comp.layer)) & PhysicsLayers.all;
      final shape = comp.moverShape;
      final at = Offset(
        transform.position.x + comp.offset.dx,
        transform.position.y + comp.offset.dy,
      );

      // Its own body, made again when what it is made of changes.
      if (link.body != null && !link.matches(comp, category, mask)) {
        _removeBody(link, rebuilt: comp.detectable);
      }
      if (link.body == null && comp.detectable) {
        final body = Physics2DBody(
          position: Vector2(at.dx, at.dy),
          shape: _shapeOf(shape),
          bodyType: Body2DType.kinematic,
          useGravity: false,
          fixedRotation: true,
          canSleep: false,
          drag: 0,
          categoryBits: category,
          maskBits: mask,
        );
        physics.addBody(body);
        link
          ..body = body
          ..culled = false;
        onBody(body, entity);
      }
      link.remember(comp, category, mask);

      // Culled (opt-in view culling): held where it is, as a body is, its
      // body out of the simulation on both backends until it is back.
      final culled = link.cull?.isActive == false;
      final body = link.body;
      if (culled != link.culled) {
        link.culled = culled;
        if (body != null) physics.setBodyActive(body, !culled);
      }
      if (culled) continue;

      // A transform written since the last move (a respawn) is a teleport.
      if (link.moved &&
          (link.lastX != transform.position.x ||
              link.lastY != transform.position.y)) {
        transform.capturePrevious();
        comp
          ..velocity = Offset.zero
          ..groundState = Ground2DState.inAir
          ..groundEntity = null;
      }

      // Jolt's recipe, as in 3-D: on the ground, move with it (a platform
      // carries the character) unless moving away from it; in the air, keep
      // the vertical speed. Then gravity, then the requested movement.
      Offset v;
      if (comp.useGravity) {
        final vertical = _dot(comp.velocity, up);
        final groundVertical = _dot(comp.groundVelocity, up);
        final towardsGround = vertical - groundVertical < 10;
        if (comp.isGrounded && towardsGround) {
          v = comp.groundVelocity;
          final jump = comp.pendingJump;
          if (jump != null) v += up * jump;
        } else {
          v = up * vertical;
        }
        v += Offset(gx, gy) * (comp.effectiveGravityScale * dt);
        v += comp.moveVelocity - up * _dot(comp.moveVelocity, up);
      } else {
        v = comp.moveVelocity;
      }
      comp.pendingJump = null;

      final result = _mover.move(
        shape: shape,
        position: at,
        velocity: v,
        dt: dt,
        up: up,
        maxSlopeAngle: comp.maxSlopeAngle,
        stepHeight: comp.stepHeight,
        stickToFloor: comp.stickToFloor,
        wasGrounded: comp.isGrounded,
        filter: Mover2DFilter(
          categoryBits: category,
          maskBits: mask,
          ignore: link.body,
        ),
        mass: comp.mass,
        pushStrength: comp.pushStrength,
      );

      transform
        ..capturePrevious()
        ..setPlanarPose(
          result.position.dx - comp.offset.dx,
          result.position.dy - comp.offset.dy,
          transform.angle,
        );
      link
        ..lastX = transform.position.x
        ..lastY = transform.position.y
        ..moved = true;

      // What reads velocity — an animator, a facing flip — reads it here.
      link.velocity?.setVelocityXY(result.velocity.dx, result.velocity.dy);

      final ground = result.groundBody;
      comp
        ..velocity = result.velocity
        ..groundState = result.groundState
        ..groundNormal = result.groundNormal
        ..groundVelocity = ground == null || ground.isStatic
            ? Offset.zero
            : Offset(ground.velocity.x, ground.velocity.y)
        ..groundEntity = ground == null ? null : entityOf(ground);

      if (body != null) {
        physics.setBodyTransform(body, result.position.dx, result.position.dy);
        body.velocity.setZero();
      }
    }
  }

  /// Takes every character's body out of the world.
  void removeAll() {
    for (final link in [..._links.values]) {
      _removeBody(link);
    }
    _links.clear();
    _active.clear();
    _seenVersion = -1;
  }

  void _refresh(World world) {
    final version = world.queryVersion(const [
      TransformComponent,
      CharacterBody2DComponent,
    ]);
    if (version == _seenVersion) return;
    _seenVersion = version;
    _active.clear();
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      CharacterBody2DComponent,
    ])) {
      final ids = archetype.entityIds;
      final transforms = archetype.getColumn(TransformComponent)!;
      final comps = archetype.getColumn(CharacterBody2DComponent)!;
      final velocities = archetype.getColumn(VelocityComponent);
      final culls = archetype.getColumn(CullStateComponent);
      for (var row = 0; row < ids.length; row++) {
        final entity = archetype.entityAt(row);
        final link = _links[entity] ??= _CharacterLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..comp = comps[row] as CharacterBody2DComponent
          ..velocity = velocities?[row] as VelocityComponent?
          ..cull = culls?[row] as CullStateComponent?
          ..version = version;
        _active.add(link);
      }
    }
    _links.removeWhere((entity, link) {
      if (link.version == version) return false;
      _removeBody(link);
      return true;
    });
  }

  void _removeBody(_CharacterLink link, {bool rebuilt = false}) {
    final body = link.body;
    if (body == null) return;
    link
      ..body = null
      ..culled = false;
    physics.removeBody(body);
    onBodyGone(body, rebuilt: rebuilt);
  }

  /// The body shape of a mover [shape]: the same capsule or rounded box.
  static Shape2D _shapeOf(Mover2DShape shape) {
    final p = shape.points;
    if (p.length == 1) return Circle2DShape(shape.radius);
    if (p.length == 2) {
      return Capsule2DShape(center1: p[0], center2: p[1], radius: shape.radius);
    }
    return RoundedPolygon2DShape(p, shape.radius);
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
}

/// What [Physics2DCharacters] keeps per character.
final class _CharacterLink {
  _CharacterLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late CharacterBody2DComponent comp;

  /// Its velocity component, if it has one: written, never read.
  VelocityComponent? velocity;

  /// Its view-culling state, if it opted into culling.
  CullStateComponent? cull;

  /// Culled at the last move: frozen.
  bool culled = false;
  int version = -1;

  /// Its own body, while it is detectable.
  Physics2DBody? body;

  /// Where the last move left its transform.
  double lastX = 0, lastY = 0;

  /// Whether it has been moved at all.
  bool moved = false;

  // What its body was made from.
  CharacterBody2DShape? _shape;
  double _radius = 0, _width = 0, _height = 0;
  int _category = 0, _mask = 0;
  bool _detectable = true;

  void remember(CharacterBody2DComponent c, int category, int mask) {
    _shape = c.shape;
    _radius = c.radius;
    _width = c.width;
    _height = c.height;
    _category = category;
    _mask = mask;
    _detectable = c.detectable;
  }

  bool matches(CharacterBody2DComponent c, int category, int mask) =>
      _shape == c.shape &&
      _radius == c.radius &&
      _width == c.width &&
      _height == c.height &&
      _category == category &&
      _mask == mask &&
      _detectable == c.detectable;
}
