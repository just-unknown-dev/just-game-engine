import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../base/system_priorities.dart';
import 'physics_system.dart';

/// Binds editor joint components to runtime physics-engine joint constraints.
///
/// This system expects entities to have [PhysicsBodyRefComponent] so that
/// joint descriptors can resolve concrete [PhysicsBody] instances.
///
/// A joint is made once and kept until its component changes, either body
/// is replaced, or either entity goes; the entities carrying joints are
/// found again only when the world's structure changes, and a joint's
/// target is looked up by name only when the one it had no longer answers
/// to that name.
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

  /// Named entities, built at most once a frame and only when a target has
  /// to be looked up. Null until then.
  Map<String, Entity>? _named;

  @override
  int get priority => SystemPriorities.physics - 2;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    _frame++;
    _named = null;
    final structureChanged = world.structureVersion != _seenStructureVersion;
    if (structureChanged) _refreshOwners();

    var wanted = 0;
    for (final owner in _owners) {
      final entity = owner.entity;
      if (!entity.isActive) continue;
      final bodyA = owner.ref.body;
      final comp = owner.joint;
      final binding = _bindings[comp];

      final targetName = switch (comp) {
        DistanceJointComponent(:final targetEntityName) => targetEntityName,
        WeldJointComponent(:final targetEntityName) => targetEntityName,
        PrismaticJointComponent(:final targetEntityName) => targetEntityName,
        WheelJointComponent(:final targetEntityName) => targetEntityName,
        _ => '',
      };
      var target = binding?.target;
      if (structureChanged ||
          target == null ||
          !target.isActive ||
          target.name != targetName) {
        target = _lookUp(targetName);
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
  /// checking an entity's joints in the order distance, weld, prismatic,
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
          _owners.add(_JointOwner(entity, ref, column[row]));
        }
      }
    }
  }

  static const List<Type> _jointTypes = [
    DistanceJointComponent,
    WeldJointComponent,
    PrismaticJointComponent,
    WheelJointComponent,
  ];

  /// The switched-on entity with a transform named [name]; the last such in
  /// world order when several share it.
  Entity? _lookUp(String name) {
    if (name.isEmpty) return null;
    final named = _named ??= {
      for (final entity in world.query([TransformComponent]))
        if (entity.isActive && (entity.name?.isNotEmpty ?? false))
          entity.name!: entity,
    };
    return named[name];
  }

  _JointBinding? _create(
    Entity a,
    PhysicsBody bodyA,
    PhysicsBody bodyB,
    Component comp,
  ) {
    switch (comp) {
      case DistanceJointComponent():
        // TODO(just_physics_engine): on the native Box2D backend the spring
        // is never switched on (b2w_setDistanceSpring sets its hertz and
        // damping but never calls b2DistanceJoint_EnableSpring), so the
        // joint holds its length rigidly; anchors and collideConnected have
        // no parameter to pass them through yet.
        final joint = physics.addDistanceJoint(
          bodyA,
          bodyB,
          length: comp.length,
          stiffness: comp.stiffness,
          damping: comp.damping,
        );
        return _DistanceBinding(bodyA, bodyB, [joint], comp);

      case WeldJointComponent():
        final joint = physics.addWeldJoint(bodyA, bodyB);
        return _WeldBinding(bodyA, bodyB, [joint], comp);

      case PrismaticJointComponent():
        // TODO(just_physics_engine): Box2DPhysicsEngine does not override
        // addPrismaticJoint, so with native Box2D running this makes a Dart
        // joint its native step never applies (createPrismaticJoint exists
        // natively but not on the web stub, so it cannot be called here).
        _warnIfPrismaticIsInert();
        final joint = physics.addPrismaticJoint(
          bodyA,
          bodyB,
          _normalizeAxis(comp.axis),
        );
        _configurePrismaticJoint(
          joint,
          enableLimit: comp.enableLimit,
          lower: comp.lowerTranslation,
          upper: comp.upperTranslation,
          enableMotor: comp.enableMotor,
          motorSpeed: comp.motorSpeed,
          maxMotorForce: comp.maxMotorForce,
        );
        return _PrismaticBinding(bodyA, bodyB, [joint], comp);

      case WheelJointComponent():
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
    WheelJointComponent comp,
  ) {
    final axis = _normalizeAxis(comp.suspensionAxis);
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
          comp.maxMotorTorque,
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
          comp.maxMotorTorque,
          enable: comp.enableMotor,
        );
    } else if (wheel is Box2DJoint) {
      wheel
        ..setWheelSpring(comp.stiffness, comp.damping)
        ..setWheelMotor(
          comp.motorSpeed,
          comp.maxMotorTorque,
          enable: comp.enableMotor,
        );
    }
    return [wheel];
  }

  bool _warnedPrismatic = false;

  /// Says once, in debug builds, that a prismatic joint will not act: the
  /// native Box2D backend is running, and it cannot make one yet.
  void _warnIfPrismaticIsInert() {
    if (!kDebugMode || _warnedPrismatic) return;
    final physics = this.physics;
    if (physics is! Box2DPhysicsEngine) return;
    if (physics.stats['backend'] != 'box2d_v3') return;
    _warnedPrismatic = true;
    debugPrint(
      'PhysicsJointBindingSystem: prismatic joints do not act on the native '
      'Box2D backend yet (just_physics_engine has no native addPrismaticJoint); '
      'the bodies slide freely.',
    );
  }

  /// Destroys [binding]'s joints — natively only while both bodies are still
  /// in the simulation. Removing a body destroys its joints with it on the
  /// Box2D backend, and destroying one of those again freed memory twice.
  ///
  /// The physics system that made the bodies is the one asked — also after
  /// it has left the world, when it keeps no bodies at all.
  void _destroyBinding(_JointBinding binding) {
    final owner = binding.owner;
    final bodiesAlive =
        owner == null ||
        (owner.entityForBody(binding.bodyA) != null &&
            owner.entityForBody(binding.bodyB) != null);
    for (final joint in binding.joints) {
      if (bodiesAlive && joint is Box2DJoint) joint.destroy();
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
  final Component joint;
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
    DistanceJointComponent c,
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
      comp is DistanceJointComponent &&
      _same(comp.length, length) &&
      _same(comp.stiffness, stiffness) &&
      _same(comp.damping, damping) &&
      comp.collideConnected == collideConnected;
}

/// Compared by its local anchors: the world anchor it used to be compared
/// by moves with the body, so a weld on anything moving was made again
/// every frame.
final class _WeldBinding extends _JointBinding {
  _WeldBinding(super.bodyA, super.bodyB, super.joints, WeldJointComponent c)
    : localAnchorA = c.localAnchorA,
      localAnchorB = c.localAnchorB,
      collideConnected = c.collideConnected;

  final Offset localAnchorA;
  final Offset localAnchorB;
  final bool collideConnected;

  @override
  bool matches(Component comp) =>
      comp is WeldJointComponent &&
      comp.localAnchorA == localAnchorA &&
      comp.localAnchorB == localAnchorB &&
      comp.collideConnected == collideConnected;
}

final class _PrismaticBinding extends _JointBinding {
  _PrismaticBinding(
    super.bodyA,
    super.bodyB,
    super.joints,
    PrismaticJointComponent c,
  ) : axis = c.axis,
      enableLimit = c.enableLimit,
      lowerTranslation = c.lowerTranslation,
      upperTranslation = c.upperTranslation,
      enableMotor = c.enableMotor,
      motorSpeed = c.motorSpeed,
      maxMotorForce = c.maxMotorForce,
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
      comp is PrismaticJointComponent &&
      comp.axis == axis &&
      comp.enableLimit == enableLimit &&
      _same(comp.lowerTranslation, lowerTranslation) &&
      _same(comp.upperTranslation, upperTranslation) &&
      comp.enableMotor == enableMotor &&
      _same(comp.motorSpeed, motorSpeed) &&
      _same(comp.maxMotorForce, maxMotorForce) &&
      comp.collideConnected == collideConnected;
}

final class _WheelBinding extends _JointBinding {
  _WheelBinding(super.bodyA, super.bodyB, super.joints, WheelJointComponent c)
    : suspensionAxis = c.suspensionAxis,
      stiffness = c.stiffness,
      damping = c.damping,
      enableMotor = c.enableMotor,
      motorSpeed = c.motorSpeed,
      maxMotorTorque = c.maxMotorTorque,
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
      comp is WheelJointComponent &&
      comp.suspensionAxis == suspensionAxis &&
      _same(comp.stiffness, stiffness) &&
      _same(comp.damping, damping) &&
      comp.enableMotor == enableMotor &&
      _same(comp.motorSpeed, motorSpeed) &&
      _same(comp.maxMotorTorque, maxMotorTorque) &&
      comp.collideConnected == collideConnected;
}
