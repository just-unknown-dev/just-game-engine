/// The joints side of `Physics2DSystem`.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import 'joint_2d_components.dart';
import 'physics_2d_body_ref_component.dart';

/// The 2-D joints ([DistanceJoint2DComponent], [FixedJoint2DComponent],
/// [SliderJoint2DComponent], [WheelJoint2DComponent]) side of
/// `Physics2DSystem`, which owns one and keeps them each update between
/// bringing the bodies up to date and stepping — as the 3-D
/// `Physics3DSystem` keeps its joints. A joint made or made again is in
/// the very step its bodies are: never a step with a body loose.
///
/// A joint is between the body of the entity it is on and the body of its
/// [Joint2DComponent.connectedBody] — both need one, which
/// `Physics2DSystem` names with a [Physics2DBodyRefComponent]. It is made
/// once and kept until its component changes, either body is made again,
/// or either entity goes; the entities carrying joints are found again only
/// when the world's structure changes, and a joint's other entity is looked
/// up again only when the one it had no longer answers to its target. A
/// joint switched off ([Joint2DComponent.enabled]) is taken down.
///
/// Springs ([DistanceJoint2DComponent.stiffness],
/// [WheelJoint2DComponent.stiffness]) are a frequency in hertz and a
/// damping ratio, as Box2D and the 3-D joints take them, on both backends.
/// A slider's and a wheel's axis is in the joint entity's space, turned to
/// the world's as the joint is made.
///
/// **What each joint takes** (just_physics_engine 2.0.0, the same on both
/// backends). An anchor is in its entity's space, turned to the world's as
/// the joint is made; at zero it is the entity's position:
/// - a distance joint keeps [Joint2DComponent.anchor] on this body and
///   [Joint2DComponent.connectedAnchor] on the other its length apart;
/// - a fixed joint welds the two bodies as they are, at its
///   [Joint2DComponent.anchor];
/// - a slider slides the other body along its axis through its
///   [Joint2DComponent.connectedAnchor], and a wheel turns about its
///   [Joint2DComponent.connectedAnchor], its axle;
/// - [Joint2DComponent.collideConnected]: off, the two bodies pass through
///   each other, so their contacts send no events; on, they collide.
///
/// The anchor a joint does not take (a fixed joint's connected anchor, a
/// slider's and a wheel's own anchor) is saved but not offered by the
/// inspector, and changing it makes nothing again. A native joint keeps the
/// angle between its bodies as it was when made (just_box_2d 0.2.0), so a
/// weld, a slider or a wheel between bodies turned apart holds them so.
final class Physics2DJoints {
  /// Joints made in [physics].
  Physics2DJoints(this.physics);

  /// The physics engine the joints are made in and removed from — the one
  /// that holds the entities' bodies.
  final Physics2DEngine physics;

  /// Each joint component's joint, by component.
  final Map<Component, _JointBinding> _bindings = {};

  /// Every (entity, joint component) pair, in world order — the order joints
  /// are made in. Rebuilt only when the world's structure changes.
  final List<_JointOwner> _owners = [];

  int _seenStructureVersion = -1;

  /// Counts updates, to tell the bindings still wanted from the rest.
  int _frame = 0;

  /// How many joints there are.
  int get length => _bindings.length;

  /// Makes, makes again and takes down [world]'s joints to match their
  /// components and bodies.
  @internal
  void sync(World world) {
    _frame++;
    final structureChanged =
        world.queryVersion(const [Physics2DBodyRefComponent]) !=
        _seenStructureVersion;
    if (structureChanged) _refreshOwners(world);

    var wanted = 0;
    for (final owner in _owners) {
      final entity = owner.entity;
      if (!entity.isActiveInHierarchy) continue;
      final bodyA = owner.ref.body;
      final comp = owner.joint;
      if (!comp.enabled) continue;
      final binding = _bindings[comp];

      final want = comp.connectedBody;
      var target = binding?.target;
      if (structureChanged ||
          target == null ||
          !target.isActiveInHierarchy ||
          !_answers(target, want)) {
        target = want.resolve(world, entity);
      }
      final bRef = target?.getComponent<Physics2DBodyRefComponent>();
      if (target == null || bRef == null || identical(target, entity)) {
        continue;
      }
      final bodyB = bRef.body;

      if (binding != null &&
          identical(binding.bodyA, bodyA) &&
          identical(binding.bodyB, bodyB) &&
          binding.matches(comp)) {
        binding
          ..target = target
          ..frame = _frame;
        wanted++;
        continue;
      }
      // As it was, but for a body made again (a new shape or scale): a
      // weld re-forms where it held the two, not where they drifted to
      // while the old body went.
      final held = binding is _WeldBinding && binding.matches(comp)
          ? binding
          : null;
      if (binding != null) _destroyBinding(binding);
      held?.restore(physics, bodyA, bodyB);
      final created = _create(entity, target, bodyA, bodyB, comp);
      if (created == null) {
        _bindings.remove(comp);
        continue;
      }
      if (created is _WeldBinding) created.hold(held);
      _bindings[comp] = created
        ..target = target
        ..frame = _frame;
      wanted++;
    }

    // Every joint still wanted: nothing to take down.
    if (wanted == _bindings.length) return;
    final stale = [
      for (final entry in _bindings.entries)
        if (entry.value.frame != _frame) entry.key,
    ];
    for (final key in stale) {
      _destroyBinding(_bindings.remove(key)!);
    }
  }

  /// Takes every joint down.
  @internal
  void removeAll() {
    for (final binding in _bindings.values) {
      _destroyBinding(binding);
    }
    _bindings.clear();
    _owners.clear();
    _seenStructureVersion = -1;
  }

  /// Finds every entity with a body and a joint component, in world order,
  /// checking an entity's joints in the order distance, fixed, slider,
  /// wheel.
  void _refreshOwners(World world) {
    _seenStructureVersion = world.queryVersion(const [
      Physics2DBodyRefComponent,
    ]);
    _owners.clear();
    for (final archetype in world.queryArchetypes(const [
      Physics2DBodyRefComponent,
    ])) {
      final ids = archetype.entityIds;
      if (ids.isEmpty) continue;
      final columns = [
        for (final type in _jointTypes) ?archetype.getColumn(type),
      ];
      if (columns.isEmpty) continue;
      final refs = archetype.getColumn(Physics2DBodyRefComponent)!;
      for (var row = 0; row < ids.length; row++) {
        final entity = archetype.entityAt(row);
        final ref = refs[row] as Physics2DBodyRefComponent;
        for (final column in columns) {
          _owners.add(
            _JointOwner(entity, ref, column[row] as Joint2DComponent),
          );
        }
      }
    }
  }

  static const List<Type> _jointTypes = [
    DistanceJoint2DComponent,
    FixedJoint2DComponent,
    SliderJoint2DComponent,
    WheelJoint2DComponent,
  ];

  /// Whether [entity] is still what [target] means.
  static bool _answers(Entity entity, EntityTarget target) =>
      switch (target.kind) {
        EntityTargetKind.name => entity.name == target.value,
        EntityTargetKind.tag => entity.hasTag(target.value),
        EntityTargetKind.self => false,
      };

  _JointBinding? _create(
    Entity a,
    Entity b,
    Physics2DBody bodyA,
    Physics2DBody bodyB,
    Component comp,
  ) {
    final physics = this.physics;
    switch (comp) {
      case DistanceJoint2DComponent():
        final joint = physics.addDistanceJoint(
          bodyA,
          bodyB,
          anchorA: _worldAnchor(a, comp.anchor),
          anchorB: _worldAnchor(b, comp.connectedAnchor),
          length: comp.length,
          springHertz: comp.stiffness,
          dampingRatio: comp.damping,
          collideConnected: comp.collideConnected,
        );
        return _DistanceBinding(bodyA, bodyB, [joint], comp);

      case FixedJoint2DComponent():
        final joint = physics.addWeldJoint(
          bodyA,
          bodyB,
          anchor: _worldAnchor(a, comp.anchor),
          collideConnected: comp.collideConnected,
        );
        return _WeldBinding(bodyA, bodyB, [joint], comp);

      case SliderJoint2DComponent():
        final joint =
            physics.addPrismaticJoint(
                bodyA,
                bodyB,
                _worldAxis(a, comp.axis),
                anchor: _worldAnchor(b, comp.connectedAnchor),
                collideConnected: comp.collideConnected,
              )
              ..setLimits(
                comp.minPosition,
                comp.maxPosition,
                enable: comp.useLimits,
              )
              ..setMotor(
                comp.motorSpeed,
                comp.motorMaxForce,
                enable: comp.enableMotor,
              );
        return _PrismaticBinding(bodyA, bodyB, [joint], comp);

      case WheelJoint2DComponent():
        // Its axle: the wheel's own point (its centre, unless
        // connectedAnchor says otherwise), not the chassis's, which the
        // wheel would orbit. A spring of 0 Hz is no spring.
        final joint =
            physics.addWheelJoint(
                bodyA,
                bodyB,
                _worldAxis(a, comp.axis),
                anchor: _worldAnchor(b, comp.connectedAnchor),
                collideConnected: comp.collideConnected,
              )
              ..setSpring(comp.stiffness, comp.damping)
              ..setMotor(
                comp.motorSpeed,
                comp.motorMaxTorque,
                enable: comp.enableMotor,
              );
        return _WheelBinding(bodyA, bodyB, [joint], comp);
    }
    return null;
  }

  /// Removes [binding]'s joints. On the Box2D backend one that went with
  /// its body (removing a body takes its joints) is gone already, and
  /// removing it again does nothing.
  void _destroyBinding(_JointBinding binding) {
    for (final joint in binding.joints) {
      physics.removeJoint(joint);
    }
  }

  /// [local], a point in [entity]'s space, in the world's.
  static Offset _worldAnchor(Entity entity, Offset local) {
    final t = entity.getComponent<TransformComponent>();
    if (t == null) return local;
    final cos = math.cos(t.angle), sin = math.sin(t.angle);
    final x = local.dx * t.scale.x, y = local.dy * t.scale.y;
    return Offset(
      t.position.x + x * cos - y * sin,
      t.position.y + x * sin + y * cos,
    );
  }

  /// [axis], in [entity]'s space, as a unit axis in the world's: turned as
  /// the entity is.
  static Offset _worldAxis(Entity entity, Offset axis) {
    final length = axis.distance;
    if (length <= 0.00001) return const Offset(1, 0);
    final angle = entity.getComponent<TransformComponent>()?.angle ?? 0.0;
    final cos = math.cos(angle), sin = math.sin(angle);
    final x = axis.dx / length, y = axis.dy / length;
    return Offset(x * cos - y * sin, x * sin + y * cos);
  }
}

/// An entity's joint component, with the body it hangs from.
final class _JointOwner {
  _JointOwner(this.entity, this.ref, this.joint);

  final Entity entity;
  final Physics2DBodyRefComponent ref;
  final Joint2DComponent joint;
}

bool _same(double a, double b) => a == b || (a.isNaN && b.isNaN);

/// A live joint and the settings it was made with. Settings are compared
/// field by field each frame — no string is built — and a change makes the
/// joint again; an anchor the joint does not take (see [Physics2DJoints]) is
/// not compared, so changing it makes nothing again.
sealed class _JointBinding {
  _JointBinding(this.bodyA, this.bodyB, this.joints);

  final Physics2DBody bodyA;
  final Physics2DBody bodyB;
  final List<Joint2D> joints;

  /// The entity [bodyB] belongs to, as last looked up.
  Entity? target;

  /// The update that last wanted this joint.
  int frame = 0;

  /// Whether [comp] still asks for exactly this joint.
  bool matches(Component comp);
}

final class _DistanceBinding extends _JointBinding {
  _DistanceBinding(
    super.bodyA,
    super.bodyB,
    super.joints,
    DistanceJoint2DComponent c,
  ) : anchor = c.anchor,
      connectedAnchor = c.connectedAnchor,
      length = c.length,
      stiffness = c.stiffness,
      damping = c.damping,
      collideConnected = c.collideConnected;

  final Offset anchor;
  final Offset connectedAnchor;
  final double length;
  final double stiffness;
  final double damping;
  final bool collideConnected;

  @override
  bool matches(Component comp) =>
      comp is DistanceJoint2DComponent &&
      comp.anchor == anchor &&
      comp.connectedAnchor == connectedAnchor &&
      _same(comp.length, length) &&
      _same(comp.stiffness, stiffness) &&
      _same(comp.damping, damping) &&
      comp.collideConnected == collideConnected;
}

/// Compared by its anchor in its entity's space, never by where it is in
/// the world: a world anchor moves with the body, so a weld on anything
/// moving would be made again every frame.
final class _WeldBinding extends _JointBinding {
  _WeldBinding(super.bodyA, super.bodyB, super.joints, FixedJoint2DComponent c)
    : anchor = c.anchor,
      collideConnected = c.collideConnected;

  final Offset anchor;
  final bool collideConnected;

  // Where it holds bodyB, in bodyA's frame: as when it was first made.
  double _x = 0, _y = 0, _angle = 0;

  /// Holds the bodies as [before] did — the same joint made again — or, for
  /// a new one, as they are now.
  void hold(_WeldBinding? before) {
    if (before != null) {
      _x = before._x;
      _y = before._y;
      _angle = before._angle;
      return;
    }
    final a = bodyA, b = bodyB;
    final cos = math.cos(-a.angle), sin = math.sin(-a.angle);
    final dx = b.position.x - a.position.x, dy = b.position.y - a.position.y;
    _x = dx * cos - dy * sin;
    _y = dx * sin + dy * cos;
    _angle = b.angle - a.angle;
  }

  /// Puts [b] back where this weld held it against [a] (or [a] against
  /// [b], when [b] cannot be moved) before the weld is made again with
  /// them.
  void restore(Physics2DEngine physics, Physics2DBody a, Physics2DBody b) {
    if (!b.isStatic) {
      final cos = math.cos(a.angle), sin = math.sin(a.angle);
      physics.setBodyTransform(
        b,
        a.position.x + _x * cos - _y * sin,
        a.position.y + _x * sin + _y * cos,
        angle: a.angle + _angle,
      );
    } else if (!a.isStatic) {
      final angle = b.angle - _angle;
      final cos = math.cos(angle), sin = math.sin(angle);
      physics.setBodyTransform(
        a,
        b.position.x - (_x * cos - _y * sin),
        b.position.y - (_x * sin + _y * cos),
        angle: angle,
      );
    }
  }

  @override
  bool matches(Component comp) =>
      comp is FixedJoint2DComponent &&
      comp.anchor == anchor &&
      comp.collideConnected == collideConnected;
}

final class _PrismaticBinding extends _JointBinding {
  _PrismaticBinding(
    super.bodyA,
    super.bodyB,
    super.joints,
    SliderJoint2DComponent c,
  ) : connectedAnchor = c.connectedAnchor,
      axis = c.axis,
      enableLimit = c.useLimits,
      lowerTranslation = c.minPosition,
      upperTranslation = c.maxPosition,
      enableMotor = c.enableMotor,
      motorSpeed = c.motorSpeed,
      maxMotorForce = c.motorMaxForce,
      collideConnected = c.collideConnected;

  final Offset connectedAnchor;
  final Offset axis;
  final bool enableLimit;
  final double lowerTranslation;
  final double upperTranslation;
  final bool enableMotor;
  final double motorSpeed;
  final double maxMotorForce;
  final bool collideConnected;

  @override
  bool matches(Component comp) =>
      comp is SliderJoint2DComponent &&
      comp.connectedAnchor == connectedAnchor &&
      comp.axis == axis &&
      comp.useLimits == enableLimit &&
      _same(comp.minPosition, lowerTranslation) &&
      _same(comp.maxPosition, upperTranslation) &&
      comp.enableMotor == enableMotor &&
      _same(comp.motorSpeed, motorSpeed) &&
      _same(comp.motorMaxForce, maxMotorForce) &&
      comp.collideConnected == collideConnected;
}

final class _WheelBinding extends _JointBinding {
  _WheelBinding(super.bodyA, super.bodyB, super.joints, WheelJoint2DComponent c)
    : connectedAnchor = c.connectedAnchor,
      suspensionAxis = c.axis,
      stiffness = c.stiffness,
      damping = c.damping,
      enableMotor = c.enableMotor,
      motorSpeed = c.motorSpeed,
      maxMotorTorque = c.motorMaxTorque,
      collideConnected = c.collideConnected;

  final Offset connectedAnchor;
  final Offset suspensionAxis;
  final double stiffness;
  final double damping;
  final bool enableMotor;
  final double motorSpeed;
  final double maxMotorTorque;
  final bool collideConnected;

  @override
  bool matches(Component comp) =>
      comp is WheelJoint2DComponent &&
      comp.connectedAnchor == connectedAnchor &&
      comp.axis == suspensionAxis &&
      _same(comp.stiffness, stiffness) &&
      _same(comp.damping, damping) &&
      comp.enableMotor == enableMotor &&
      _same(comp.motorSpeed, motorSpeed) &&
      _same(comp.motorMaxTorque, maxMotorTorque) &&
      comp.collideConnected == collideConnected;
}
