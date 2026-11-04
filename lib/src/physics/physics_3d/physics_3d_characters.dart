/// The characters side of `Physics3DSystem`.
library;

import 'dart:math' as math;

import 'package:just_physics_engine/physics_3d.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import 'physics_3d_bodies.dart' show moveEpsilon3D;
import 'physics_3d_components.dart';

/// The [CharacterBody3DComponent] side of `Physics3DSystem`, which owns one
/// and moves them each update before stepping — the 3-D twin of the 2-D
/// system's characters.
///
/// Each character is moved with Jolt's own recipe: on the ground it moves
/// with the ground (a platform carries it) unless moving away from it; in
/// the air it keeps its vertical speed; then gravity, then the movement
/// gameplay asked for. A transform written by gameplay since the last move
/// is a teleport (a respawn): the character starts again from rest there,
/// in the air, as a 2-D one does.
@internal
final class Physics3DCharacters {
  /// Characters in the world [physics] gives; [entities] gets each
  /// detectable character's inner body's entity. [onBodyGone] hears of each
  /// inner body destroyed — `rebuilt` when a new one takes its place at once.
  Physics3DCharacters(this._physics, this.entities, {required this.onBodyGone});

  final Physics3DWorld Function() _physics;

  /// Each body's entity — shared with the bodies.
  final Map<int, Entity> entities;

  /// [body], [entity]'s inner body, was destroyed.
  final void Function(int body, Entity entity, {required bool rebuilt})
  onBodyGone;

  final Map<Entity, _CharacterLink> _characters = {};
  final Character3DState _state = Character3DState();
  final Vector3 _v = Vector3.zero();
  final Vector3 _up = Vector3.zero();
  final Vector3 _down = Vector3.zero();
  final Vector3 _stepUp = Vector3.zero();

  /// Whether there are no characters.
  bool get isEmpty => _characters.isEmpty;

  /// [entity]'s character, or 0.
  int characterOf(Entity entity) => _characters[entity]?.character ?? 0;

  /// Brings the links up to date with [world] at structure [version]: new
  /// characters are linked, and those of entities destroyed or without
  /// their component go.
  void refresh(World world, int version) {
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      CharacterBody3DComponent,
    ])) {
      final ids = archetype.entityIds;
      final transforms = archetype.getColumn(TransformComponent)!;
      final comps = archetype.getColumn(CharacterBody3DComponent)!;
      for (var row = 0; row < ids.length; row++) {
        final entity = archetype.entityAt(row);
        final link = _characters[entity] ??= _CharacterLink(entity);
        link
          ..transform = transforms[row] as TransformComponent
          ..comp = comps[row] as CharacterBody3DComponent
          ..version = version;
      }
    }
    // Destroyed, or no longer carrying the components.
    _characters.removeWhere((_, link) {
      if (link.version == version) return false;
      _removeCharacter(link);
      return true;
    });
  }

  /// Moves every character by [dt] seconds.
  void move(double dt) {
    if (_characters.isEmpty) return;
    final physics = _physics();
    final gravity = physics.gravity;
    for (final link in _characters.values) {
      final comp = link.comp;
      if (!link.entity.isActiveInHierarchy) {
        _removeCharacter(link);
        continue;
      }
      final transform = link.transform;
      if (link.character != 0 && !link.matches(comp)) {
        _removeCharacter(link, rebuilt: comp.detectable);
      }
      if (link.character == 0) {
        _up.setFrom(gravity);
        if (_up.normalize() == 0) _up.setValues(0, 1, 0);
        _up.negate();
        final character = physics.createCharacter(
          Character3DSettings(
            radius: comp.radius,
            halfHeight: math.max(comp.height / 2 - comp.radius, 0.0),
            up: Vector3.copy(_up),
            maxSlopeAngle: comp.maxSlopeAngle,
            mass: comp.mass,
            maxStrength: comp.pushStrength,
            layer: comp.layer,
            innerBody: comp.detectable,
          ),
          transform.position,
        );
        if (character == 0) continue;
        link
          ..character = character
          ..innerBody = physics.characterBody(character)
          ..remember(comp)
          ..rememberPosition(transform.position);
        comp.character = character;
        if (link.innerBody != 0) entities[link.innerBody] = link.entity;
        transform.capturePrevious();
      } else if (!link.isAt(transform.position)) {
        // Teleported by gameplay (a respawn): it starts again from rest,
        // in the air — not falling as fast as it was, or riding a platform
        // it is no longer on.
        physics.setCharacterPosition(link.character, transform.position);
        transform.capturePrevious();
        comp
          ..velocity.setZero()
          ..groundState = Ground3DState.inAir
          ..groundVelocity.setZero()
          ..groundEntity = null;
      }

      _up.setFrom(gravity);
      final g = _up.normalize();
      if (g == 0) _up.setValues(0, 1, 0);
      _up.negate(); // Against gravity.
      final v = _v;
      if (comp.useGravity) {
        // Jolt's own recipe: on the ground, move with it (a platform carries
        // the character) unless moving away from it; in the air, keep the
        // vertical speed. Then gravity, then the requested movement.
        final vertical = comp.velocity.dot(_up);
        final groundVertical = comp.groundVelocity.dot(_up);
        final towardsGround = vertical - groundVertical < 0.1;
        if (comp.isGrounded && towardsGround) {
          v.setFrom(comp.groundVelocity);
          final jump = comp.pendingJump;
          if (jump != null) v.addScaled(_up, jump);
        } else {
          v
            ..setFrom(_up)
            ..scale(vertical);
        }
        v.addScaled(gravity, comp.gravityScale * dt);
        v.add(comp.moveVelocity);
        v.addScaled(_up, -comp.moveVelocity.dot(_up));
      } else {
        v.setFrom(comp.moveVelocity);
      }
      comp.pendingJump = null;
      _down
        ..setFrom(_up)
        ..scale(-comp.stickToFloor);
      _stepUp
        ..setFrom(_up)
        ..scale(comp.stepHeight);

      final state = _state;
      physics.moveCharacter(
        link.character,
        dt,
        v,
        state,
        stepDown: _down,
        stepUp: _stepUp,
      );
      // Gameplay turned it before the step (a controller facing where it
      // runs): it is drawn turning from where the last step left it.
      if (link.turned) {
        transform.capturePreviousWithRotation(link.turn);
      } else {
        transform.capturePrevious();
      }
      transform.position.setFrom(state.position);
      transform.rotationInto(link.turn);
      link.turned = true;
      link.rememberPosition(transform.position);
      comp.velocity.setFrom(state.velocity);
      comp.groundState = state.groundState;
      comp.groundNormal.setFrom(state.groundNormal);
      comp.groundVelocity.setFrom(state.groundVelocity);
      comp.groundEntity = state.groundBody == 0
          ? null
          : entities[state.groundBody];
    }
  }

  void _removeCharacter(_CharacterLink link, {bool rebuilt = false}) {
    if (link.character == 0) return;
    _physics().destroyCharacter(link.character);
    if (link.innerBody != 0) {
      onBodyGone(link.innerBody, link.entity, rebuilt: rebuilt);
      entities.remove(link.innerBody);
    }
    link
      ..character = 0
      ..innerBody = 0;
    final comp = link.comp;
    comp
      ..character = 0
      ..groundState = Ground3DState.inAir
      ..groundEntity = null;
  }

  /// Destroys every character — unless the world is gone already
  /// ([worldGone]) — and forgets every entity.
  void removeAll({required bool worldGone}) {
    if (!worldGone) {
      for (final link in _characters.values) {
        _removeCharacter(link);
      }
    }
    _characters.clear();
  }
}

/// An entity with a character, and the physics engine's character.
final class _CharacterLink {
  _CharacterLink(this.entity);

  final Entity entity;
  late TransformComponent transform;
  late CharacterBody3DComponent comp;
  int version = -1;
  int character = 0;
  int innerBody = 0;

  /// Its rotation at the end of the last move, once [turned].
  final Quaternion turn = Quaternion.identity();
  bool turned = false;

  double _radius = 0, _height = 0, _slope = 0, _mass = 0, _push = 0;
  int _layer = 0;
  bool _detectable = true;
  double _x = 0, _y = 0, _z = 0;

  void remember(CharacterBody3DComponent c) {
    _radius = c.radius;
    _height = c.height;
    _slope = c.maxSlopeAngle;
    _mass = c.mass;
    _push = c.pushStrength;
    _layer = c.layer;
    _detectable = c.detectable;
  }

  bool matches(CharacterBody3DComponent c) =>
      _radius == c.radius &&
      _height == c.height &&
      _slope == c.maxSlopeAngle &&
      _mass == c.mass &&
      _push == c.pushStrength &&
      _layer == c.layer &&
      _detectable == c.detectable;

  void rememberPosition(Vector3 p) {
    _x = p.x;
    _y = p.y;
    _z = p.z;
  }

  bool isAt(Vector3 p) {
    const e = moveEpsilon3D;
    return (p.x - _x).abs() <= e &&
        (p.y - _y).abs() <= e &&
        (p.z - _z).abs() <= e;
  }
}
