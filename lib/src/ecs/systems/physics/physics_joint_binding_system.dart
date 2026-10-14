import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../base/system_priorities.dart';
import 'physics_system.dart';

/// Makes the 2-D joints ([DistanceJoint2D], [FixedJoint2D], [SliderJoint2D],
/// [WheelJoint2D]) in the physics engine, between the body of the entity a
/// joint is on and the body of its [Joint2D.connectedBody].
///
/// Both entities need a body — `PhysicsSystem` gives each a
/// [PhysicsBodyRefComponent]. A joint is made once and kept until its
/// component changes, either body is replaced, or either entity goes; the
/// entities carrying joints are found again only when the world's structure
/// changes, and a joint's other entity is looked up again only when the one
/// it had no longer answers to its target. A joint switched off
/// ([Joint2D.enabled]) is taken down.
class PhysicsJointBindingSystem extends System {
  /// A system making its joints in [physics].
  PhysicsJointBindingSystem(this.physics);

  /// The physics engine the joints are made in and removed from — the one
  /// that holds the entities' bodies.
  final PhysicsEngine physics;

  /// Each joint component's joint, by component.
  final Map<Component, _JointBinding> _bindings = {};

  /// Every (entity, joint component) pair, in world order — the order joints
  /// are made in. Rebuilt only when the world's structure changes.
  final List<_JointOwner> _owners = [];

  int _seenStructureVersion = -1;

  /// Counts updates, to tell the bindings still wanted from the rest.
  int _frame = 0;

  @override
  int get priority => SystemPriorities.physics - 2;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    _frame++;
    final structureChanged = world.structureVersion != _seenStructureVersion;
    if (structureChanged) _refreshOwners();

    var wanted = 0;
    for (final owner in _owners) {
      final entity = owner.entity;
      if (!entity.isActive) continue;
      final bodyA = owner.ref.body;
      final comp = owner.joint;
      if (!comp.enabled) continue;
      final binding = _bindings[comp];

      final want = comp.connectedBody;
      var target = binding?.target;
      if (structureChanged ||
          target == null ||
          !target.isActive ||
          !_answers(target, want)) {
        target = want.resolve(world, entity);
      }
      final bRef = target?.getComponent<PhysicsBodyRefComponent>();
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
      if (binding != null) _destroyBinding(binding);
      final created = _create(entity, bodyA, bodyB, comp);
      if (created == null) {
        _bindings.remove(comp);
        continue;
      }
      _bindings[comp] = created
        ..target = target
        ..owner = world.getSystem<PhysicsSystem>()
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

  @override
  void onRemovedFromWorld() => _removeAll();

  @override
  void dispose() => _removeAll();

  void _removeAll() {
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
  void _refreshOwners() {
    _seenStructureVersion = world.structureVersion;
    _owners.clear();
    for (final archetype in world.queryArchetypes(const [
      PhysicsBodyRefComponent,
    ])) {
      final ids = archetype.entityIds;
      if (ids.isEmpty) continue;
      final columns = [
        for (final type in _jointTypes) ?archetype.getColumn(type),
      ];
      if (columns.isEmpty) continue;
      final refs = archetype.getColumn(PhysicsBodyRefComponent)!;
      for (var row = 0; row < ids.length; row++) {
        final entity = world.getEntity(ids[row]);
        if (entity == null) continue;
        final ref = refs[row] as PhysicsBodyRefComponent;
        for (final column in columns) {
          _owners.add(_JointOwner(entity, ref, column[row] as Joint2D));
        }
      }
    }
  }

  static const List<Type> _jointTypes = [
    DistanceJoint2D,
    FixedJoint2D,
    SliderJoint2D,
    WheelJoint2D,
  ];

  /// Whether [entity] is still what [target] means.
  static bool _answers(Entity entity, EntityTarget target) => switch (target.kind) {
    EntityTargetKind.name => entity.name == target.value,
    EntityTargetKind.tag => entity.hasTag(target.value),
    EntityTargetKind.self => false,
  };

  _JointBinding? _create(
    Entity a,
    PhysicsBody bodyA,
    PhysicsBody bodyB,
    Component comp,
  ) {
    switch (comp) {
      case DistanceJoint2D():
        // TODO(just_physics_engine): anchors and collideConnected have no
        // parameter to pass them through yet.
        final joint = physics.addDistanceJoint(
          bodyA,
          bodyB,
          length: comp.length,
          stiffness: comp.stiffness,
          damping: comp.damping,
        );
        return _DistanceBinding(bodyA, bodyB, [joint], comp);

      case FixedJoint2D():
        final joint = physics.addWeldJoint(bodyA, bodyB);
        return _WeldBinding(bodyA, bodyB, [joint], comp);

      case SliderJoint2D():
        final joint = physics.addPrismaticJoint(
          bodyA,
          bodyB,
          _normalizeAxis(comp.axis),
        );
        _configurePrismaticJoint(
          joint,
          enableLimit: comp.useLimits,
          lower: comp.minPosition,
          upper: comp.maxPosition,
          enableMotor: comp.enableMotor,
          motorSpeed: comp.motorSpeed,
          maxMotorForce: comp.motorMaxForce,
        );
        return _PrismaticBinding(bodyA, bodyB, [joint], comp);

      case WheelJoint2D():
        return _WheelBinding(
          bodyA,
          bodyB,
          _createWheel(a, bodyA, bodyB, comp),
          comp,
        );
    }
    return null;
  }

  List<JointConstraint> _createWheel(
    Entity a,
    PhysicsBody bodyA,
    PhysicsBody bodyB,
    WheelJoint2D comp,
  ) {
    final axis = _normalizeAxis(comp.axis);
    final physics = this.physics;
    if (physics is Box2DPhysicsEngine) {
      final wheel = physics.createWheelJoint(
        bodyA,
        bodyB,
        _worldAnchor(a, Offset.zero),
        axis,
      );
      if (wheel != null) {
        wheel.setWheelSpring(comp.stiffness, comp.damping);
        wheel.setWheelMotor(
          comp.motorSpeed,
          comp.motorMaxTorque,
          enable: comp.enableMotor,
        );
        return [wheel];
      }
    }

    // Without native wheel joints: the physics engine's own wheel joint —
    // the Dart one — sprung along the axis, its motor spinning the wheel.
    final wheel = physics.addWheelJoint(bodyA, bodyB, axis);
    if (wheel is WheelJoint) {
      wheel
        ..setWheelSpring(comp.stiffness, comp.damping)
        ..setWheelMotor(
          comp.motorSpeed,
          comp.motorMaxTorque,
          enable: comp.enableMotor,
        );
    } else if (wheel is Box2DJoint) {
      wheel
        ..setWheelSpring(comp.stiffness, comp.damping)
        ..setWheelMotor(
          comp.motorSpeed,
          comp.motorMaxTorque,
          enable: comp.enableMotor,
        );
    }
    return [wheel];
  }

  /// Destroys [binding]'s joints. On the Box2D backend one that went with
  /// its body (removing a body takes its joints) is gone already, and
  /// destroying it again does nothing: just_box_2d checks every handle.
  void _destroyBinding(_JointBinding binding) {
    for (final joint in binding.joints) {
      if (joint is Box2DJoint) joint.destroy();
      physics.removeJoint(joint);
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

    if (joint is PrismaticJoint) {
      if (enableLimit != null) joint.limitEnabled = enableLimit;
      if (lower != null) joint.lowerLimit = lower;
      if (upper != null) joint.upperLimit = upper;
      if (enableMotor != null) joint.motorEnabled = enableMotor;
      if (motorSpeed != null) joint.motorSpeed = motorSpeed;
      if (maxMotorForce != null) joint.maxMotorForce = maxMotorForce;
    }
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

/// An entity's joint component, with the body it hangs from.
final class _JointOwner {
  _JointOwner(this.entity, this.ref, this.joint);

  final Entity entity;
  final PhysicsBodyRefComponent ref;
  final Joint2D joint;
}

bool _same(double a, double b) => a == b || (a.isNaN && b.isNaN);

/// A live joint and the settings it was made with. Settings are compared
/// field by field each frame — no string is built — and a change makes the
/// joint again.
sealed class _JointBinding {
  _JointBinding(this.bodyA, this.bodyB, this.joints);

  final PhysicsBody bodyA;
  final PhysicsBody bodyB;
  final List<JointConstraint> joints;

  /// The entity [bodyB] belongs to, as last looked up.
  Entity? target;

  /// The physics system whose bodies these are, if one was in the world.
  PhysicsSystem? owner;

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
    DistanceJoint2D c,
  ) : length = c.length,
      stiffness = c.stiffness,
      damping = c.damping,
      collideConnected = c.collideConnected;

  final double length;
  final double stiffness;
  final double damping;
  final bool collideConnected;

  @override
  bool matches(Component comp) =>
      comp is DistanceJoint2D &&
      _same(comp.length, length) &&
      _same(comp.stiffness, stiffness) &&
      _same(comp.damping, damping) &&
      comp.collideConnected == collideConnected;
}

/// Compared by its local anchors: the world anchor it used to be compared
/// by moves with the body, so a weld on anything moving was made again
/// every frame.
final class _WeldBinding extends _JointBinding {
  _WeldBinding(super.bodyA, super.bodyB, super.joints, FixedJoint2D c)
    : anchor = c.anchor,
      connectedAnchor = c.connectedAnchor,
      collideConnected = c.collideConnected;

  final Offset anchor;
  final Offset connectedAnchor;
  final bool collideConnected;

  @override
  bool matches(Component comp) =>
      comp is FixedJoint2D &&
      comp.anchor == anchor &&
      comp.connectedAnchor == connectedAnchor &&
      comp.collideConnected == collideConnected;
}

final class _PrismaticBinding extends _JointBinding {
  _PrismaticBinding(
    super.bodyA,
    super.bodyB,
    super.joints,
    SliderJoint2D c,
  ) : axis = c.axis,
      enableLimit = c.useLimits,
      lowerTranslation = c.minPosition,
      upperTranslation = c.maxPosition,
      enableMotor = c.enableMotor,
      motorSpeed = c.motorSpeed,
      maxMotorForce = c.motorMaxForce,
      collideConnected = c.collideConnected;

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
      comp is SliderJoint2D &&
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
  _WheelBinding(super.bodyA, super.bodyB, super.joints, WheelJoint2D c)
    : suspensionAxis = c.axis,
      stiffness = c.stiffness,
      damping = c.damping,
      enableMotor = c.enableMotor,
      motorSpeed = c.motorSpeed,
      maxMotorTorque = c.motorMaxTorque,
      collideConnected = c.collideConnected;

  final Offset suspensionAxis;
  final double stiffness;
  final double damping;
  final bool enableMotor;
  final double motorSpeed;
  final double maxMotorTorque;
  final bool collideConnected;

  @override
  bool matches(Component comp) =>
      comp is WheelJoint2D &&
      comp.axis == suspensionAxis &&
      _same(comp.stiffness, stiffness) &&
      _same(comp.damping, damping) &&
      comp.enableMotor == enableMotor &&
      _same(comp.motorSpeed, motorSpeed) &&
      _same(comp.motorMaxTorque, maxMotorTorque) &&
      comp.collideConnected == collideConnected;
}
