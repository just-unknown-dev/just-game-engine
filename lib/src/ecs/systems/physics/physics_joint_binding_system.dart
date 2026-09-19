import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Binds editor joint components to runtime physics-engine joint constraints.
///
/// This system expects entities to have [PhysicsBodyRefComponent] so that
/// joint descriptors can resolve concrete [PhysicsBody] instances.
class PhysicsJointBindingSystem extends System {
  PhysicsJointBindingSystem(this.physics);

  final PhysicsEngine physics;

  final Map<String, (_RuntimeJointBinding, String)> _bindings =
      <String, (_RuntimeJointBinding, String)>{};

  @override
  int get priority => SystemPriorities.physics - 2;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    final named = <String, Entity>{};
    for (final entity in world.query([TransformComponent])) {
      if (!entity.isActive) continue;
      final name = entity.name;
      if (name == null || name.isEmpty) continue;
      named[name] = entity;
    }

    final activeKeys = <String>{};

    for (final entity in world.query([PhysicsBodyRefComponent])) {
      if (!entity.isActive) continue;
      final aRef = entity.getComponent<PhysicsBodyRefComponent>();
      if (aRef == null) continue;

      final distance = entity.getComponent<DistanceJointComponent>();
      if (distance != null) {
        _bindDistance(entity, aRef.body, distance, named, activeKeys);
      }

      final weld = entity.getComponent<WeldJointComponent>();
      if (weld != null) {
        _bindWeld(entity, aRef.body, weld, named, activeKeys);
      }

      final prismatic = entity.getComponent<PrismaticJointComponent>();
      if (prismatic != null) {
        _bindPrismatic(entity, aRef.body, prismatic, named, activeKeys);
      }

      final wheel = entity.getComponent<WheelJointComponent>();
      if (wheel != null) {
        _bindWheel(entity, aRef.body, wheel, named, activeKeys);
      }
    }

    final staleKeys = _bindings.keys
        .where((key) => !activeKeys.contains(key))
        .toList();
    for (final key in staleKeys) {
      _removeBinding(key);
    }
  }

  @override
  void onRemovedFromWorld() {
    for (final key in _bindings.keys.toList()) {
      _removeBinding(key);
    }
    _bindings.clear();
  }

  void _bindDistance(
    Entity a,
    PhysicsBody bodyA,
    DistanceJointComponent comp,
    Map<String, Entity> named,
    Set<String> activeKeys,
  ) {
    final target = named[comp.targetEntityName];
    final bRef = target?.getComponent<PhysicsBodyRefComponent>();
    if (target == null || bRef == null || target.id == a.id) return;

    final key = 'distance:${a.id}:${target.id}';
    activeKeys.add(key);

    final fingerprint = [
      comp.length,
      comp.stiffness,
      comp.damping,
      comp.collideConnected,
    ].join('|');

    _ensureBinding(key, fingerprint, () {
      final joint = physics.addDistanceJoint(
        bodyA,
        bRef.body,
        length: comp.length,
        stiffness: comp.stiffness,
        damping: comp.damping,
      );
      return _RuntimeJointBinding.single(joint);
    });
  }

  void _bindWeld(
    Entity a,
    PhysicsBody bodyA,
    WeldJointComponent comp,
    Map<String, Entity> named,
    Set<String> activeKeys,
  ) {
    final target = named[comp.targetEntityName];
    final bRef = target?.getComponent<PhysicsBodyRefComponent>();
    if (target == null || bRef == null || target.id == a.id) return;

    final key = 'weld:${a.id}:${target.id}';
    activeKeys.add(key);

    final anchorA = _worldAnchor(a, comp.localAnchorA);
    final fingerprint = [
      anchorA.dx,
      anchorA.dy,
      comp.collideConnected,
    ].join('|');

    _ensureBinding(key, fingerprint, () {
      final joint = physics.addWeldJoint(bodyA, bRef.body);
      return _RuntimeJointBinding.single(joint);
    });
  }

  void _bindPrismatic(
    Entity a,
    PhysicsBody bodyA,
    PrismaticJointComponent comp,
    Map<String, Entity> named,
    Set<String> activeKeys,
  ) {
    final target = named[comp.targetEntityName];
    final bRef = target?.getComponent<PhysicsBodyRefComponent>();
    if (target == null || bRef == null || target.id == a.id) return;

    final key = 'prismatic:${a.id}:${target.id}';
    activeKeys.add(key);

    final axis = _normalizeAxis(comp.axis);
    final fingerprint = [
      axis.dx,
      axis.dy,
      comp.enableLimit,
      comp.lowerTranslation,
      comp.upperTranslation,
      comp.enableMotor,
      comp.motorSpeed,
      comp.maxMotorForce,
      comp.collideConnected,
    ].join('|');

    _ensureBinding(key, fingerprint, () {
      final joint = physics.addPrismaticJoint(bodyA, bRef.body, axis);
      _configurePrismaticJoint(
        joint,
        enableLimit: comp.enableLimit,
        lower: comp.lowerTranslation,
        upper: comp.upperTranslation,
        enableMotor: comp.enableMotor,
        motorSpeed: comp.motorSpeed,
        maxMotorForce: comp.maxMotorForce,
      );
      return _RuntimeJointBinding.single(joint);
    });
  }

  void _bindWheel(
    Entity a,
    PhysicsBody bodyA,
    WheelJointComponent comp,
    Map<String, Entity> named,
    Set<String> activeKeys,
  ) {
    final target = named[comp.targetEntityName];
    final bRef = target?.getComponent<PhysicsBodyRefComponent>();
    if (target == null || bRef == null || target.id == a.id) return;

    final key = 'wheel:${a.id}:${target.id}';
    activeKeys.add(key);

    final axis = _normalizeAxis(comp.suspensionAxis);
    final anchorA = _worldAnchor(a, Offset.zero);
    final fingerprint = [
      axis.dx,
      axis.dy,
      comp.stiffness,
      comp.damping,
      comp.enableMotor,
      comp.motorSpeed,
      comp.maxMotorTorque,
      comp.collideConnected,
    ].join('|');

    _ensureBinding(key, fingerprint, () {
      if (physics is Box2DPhysicsEngine) {
        final b2 = physics as Box2DPhysicsEngine;
        final wheel = b2.createWheelJoint(bodyA, bRef.body, anchorA, axis);
        if (wheel != null) {
          wheel.setWheelSpring(comp.stiffness, comp.damping);
          wheel.setWheelMotor(
            comp.motorSpeed,
            comp.maxMotorTorque,
            enable: comp.enableMotor,
          );
          return _RuntimeJointBinding.single(wheel);
        }
      }

      // Fallback when native wheel joints are unavailable.
      final slider = physics.addPrismaticJoint(bodyA, bRef.body, axis);
      _configurePrismaticJoint(
        slider,
        enableMotor: comp.enableMotor,
        motorSpeed: comp.motorSpeed,
        maxMotorForce: comp.maxMotorTorque,
      );
      final spring = physics.addDistanceJoint(
        bodyA,
        bRef.body,
        length: (bRef.body.position - bodyA.position).length,
        stiffness: comp.stiffness,
        damping: comp.damping,
      );
      return _RuntimeJointBinding.multi([slider, spring]);
    });
  }

  void _ensureBinding(
    String key,
    String fingerprint,
    _RuntimeJointBinding Function() create,
  ) {
    final existing = _bindings[key];
    if (existing != null && existing.$2 == fingerprint) {
      return;
    }
    if (existing != null) {
      _destroyBinding(existing.$1);
    }
    final binding = create();
    _bindings[key] = (binding, fingerprint);
  }

  void _removeBinding(String key) {
    final existing = _bindings.remove(key);
    if (existing == null) return;
    _destroyBinding(existing.$1);
  }

  void _destroyBinding(_RuntimeJointBinding binding) {
    for (final joint in binding.joints) {
      _destroyJointSafely(joint);
    }
  }

  void _configurePrismaticJoint(
    JointConstraint joint, {
    bool? enableLimit,
    double? lower,
    double? upper,
    bool? enableMotor,
    double? motorSpeed,
    double? maxMotorForce,
  }) {
    if (joint is Box2DJoint) {
      if (lower != null && upper != null) {
        joint.setPrismaticLimits(lower, upper, enable: enableLimit ?? false);
      }
      if (motorSpeed != null && maxMotorForce != null) {
        joint.setPrismaticMotor(
          motorSpeed,
          maxMotorForce,
          enable: enableMotor ?? false,
        );
      }
      return;
    }

    final dyn = joint as dynamic;
    try {
      if (enableLimit != null) dyn.limitEnabled = enableLimit;
      if (lower != null) dyn.lowerLimit = lower;
      if (upper != null) dyn.upperLimit = upper;
      if (enableMotor != null) dyn.motorEnabled = enableMotor;
      if (motorSpeed != null) dyn.motorSpeed = motorSpeed;
      if (maxMotorForce != null) dyn.maxMotorForce = maxMotorForce;
    } catch (_) {
      // Joint implementation may not expose these fields on this backend.
    }
  }

  void _destroyJointSafely(JointConstraint joint) {
    if (joint is Box2DJoint) {
      final dynPhysics = physics as dynamic;
      try {
        dynPhysics.destroyJoint(joint);
        return;
      } catch (_) {
        // Fall through to per-joint destroy/remove fallback.
      }

      final dynJoint = joint as dynamic;
      try {
        dynJoint.destroy();
      } catch (_) {
        // destroy() may not exist on this backend shim.
      }
    }

    physics.removeJoint(joint);
  }

  Offset _worldAnchor(Entity entity, Offset local) {
    final t = entity.getComponent<TransformComponent>();
    if (t == null) return local;
    return Offset(t.position.x + local.dx, t.position.y + local.dy);
  }

  Offset _normalizeAxis(Offset axis) {
    if (axis.distance <= 0.00001) return const Offset(1, 0);
    return axis / axis.distance;
  }
}

class _RuntimeJointBinding {
  const _RuntimeJointBinding._(this.joints);

  final List<JointConstraint> joints;

  factory _RuntimeJointBinding.single(JointConstraint joint) {
    return _RuntimeJointBinding._(<JointConstraint>[joint]);
  }

  factory _RuntimeJointBinding.multi(List<JointConstraint> joints) {
    return _RuntimeJointBinding._(joints);
  }
}
