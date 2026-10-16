/// The systems that feed the camera brain: group centres and trigger zones.
library;

import 'package:flutter/painting.dart' show Offset, Rect;

import 'camera_targets.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../../base/system_priorities.dart';

/// Moves each target group's entity to the weighted centre of its members.
///
/// A member that names a tag is every entity with that tag — so one member,
/// tag `player`, frames all the players however many have joined.
///
/// Runs before the brain, so a camera following the group frames where the
/// group *is* this frame.
class CameraTargetGroupSystem extends System {
  final CameraTargetResolver _targets = CameraTargetResolver();

  @override
  int get priority => SystemPriorities.camera + 2;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    CameraTargetGroupComponent,
  ];

  @override
  void update(double deltaTime) {
    _targets.beginFrame(world);
    for (final entity in world.query(requiredComponents)) {
      if (!entity.isActive) continue;
      final group = entity.getComponent<CameraTargetGroupComponent>()!;
      var sum = Offset.zero;
      var weights = 0.0;
      Rect? box;
      var found = 0;
      for (final member in group.members) {
        for (final target in _targets.resolveTargetAll(
          member.target,
          owner: entity,
        )) {
          if (identical(target, entity)) continue;
          final at = CameraTargetResolver.positionOf(target);
          if (at == null) continue;
          found++;
          sum += at * member.weight;
          weights += member.weight;
          final room = Rect.fromCircle(center: at, radius: member.radius);
          box = box == null ? room : box.expandToInclude(room);
        }
      }
      group
        ..resolved = found
        ..bounds = box ?? Rect.zero;
      if (box == null) continue;
      // All-zero weights still deserve a centre: the middle of the box.
      final centre = weights > 0 ? sum / weights : box.center;
      entity.getComponent<TransformComponent>()!.setPositionXY(
        centre.dx,
        centre.dy,
      );
    }
  }
}

/// Switches virtual cameras by whether a target is inside a trigger.
///
/// It only ever touches a camera's `enabled` and `priority`; the brain does
/// the rest, blends included. Runs before the brain, so a switch takes effect
/// the frame the target crosses the line.
///
/// Several triggers may drive one camera. In
/// [CameraTriggerMode.enableWhileInside] the camera is enabled while the
/// target is inside *any* of them — and switched off once none of them
/// asks for it, even when the last one was switched off, destroyed or
/// pointed at another camera while it held the camera on. In [CameraTriggerMode.boostPriority] each
/// trigger adds its own boost, and takes back exactly what it added: when
/// the target leaves, when its `amount` is edited (the new amount replaces
/// the old), and when the trigger is switched off, destroyed or loses its
/// component while the boost is in force.
class CameraTriggerSystem extends System {
  final CameraTargetResolver _targets = CameraTargetResolver();

  /// The boosts in force, by the trigger that applied them.
  final Map<CameraTriggerComponent, _AppliedBoost> _boosts = Map.identity();

  // This frame's workings, kept to be reused: every enable-while-inside
  // camera's vote (inside any of its triggers), and the triggers boosting.
  final Map<VirtualCameraComponent, bool> _enable = Map.identity();
  final Set<CameraTriggerComponent> _boosting = Set.identity();

  // The cameras triggers held on after the last frame, and this frame's.
  Set<VirtualCameraComponent> _heldOn = Set.identity();
  Set<VirtualCameraComponent> _holding = Set.identity();

  @override
  int get priority => SystemPriorities.camera + 1;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    CameraTriggerComponent,
  ];

  @override
  void update(double deltaTime) {
    _targets.beginFrame(world);
    final enable = _enable..clear();
    final boosting = _boosting..clear();
    for (final entity in world.query(requiredComponents)) {
      if (!entity.isActive) continue;
      final trigger = entity.getComponent<CameraTriggerComponent>()!;
      final camera = trigger.cameraName.isEmpty
          ? entity
          : _targets.resolve(name: trigger.cameraName);
      final vcam = camera?.getComponent<VirtualCameraComponent>();
      if (vcam == null) continue;

      final inside = trigger.hasFired || _isInside(entity, trigger);
      if (inside && trigger.oneShot) trigger.hasFired = true;
      trigger.isInside = inside;

      switch (trigger.mode) {
        case CameraTriggerMode.enableWhileInside:
          enable[vcam] = (enable[vcam] ?? false) || inside;
        case CameraTriggerMode.boostPriority:
          if (inside) {
            boosting.add(trigger);
            _boost(trigger, vcam);
          }
      }
    }
    final holding = _holding..clear();
    for (final MapEntry(key: vcam, value: on) in enable.entries) {
      vcam.enabled = on;
      if (on) holding.add(vcam);
    }
    // A camera a trigger held on that no trigger votes for now — its
    // trigger went away — is let go.
    for (final vcam in _heldOn) {
      if (!enable.containsKey(vcam)) vcam.enabled = false;
    }
    _holding = _heldOn;
    _heldOn = holding;
    // A boost whose trigger no longer asks for it — the target left, the
    // trigger went away, or it now drives another camera — is taken back.
    if (_boosts.length > boosting.length) {
      _boosts.removeWhere((trigger, applied) {
        if (boosting.contains(trigger)) return false;
        applied.vcam.priority -= applied.amount;
        trigger.isBoosted = false;
        return true;
      });
    }
  }

  /// Keeps [trigger]'s boost on [vcam] at the trigger's current amount.
  void _boost(CameraTriggerComponent trigger, VirtualCameraComponent vcam) {
    final applied = _boosts[trigger];
    if (applied != null &&
        identical(applied.vcam, vcam) &&
        applied.amount == trigger.amount) {
      return;
    }
    if (applied != null) applied.vcam.priority -= applied.amount;
    vcam.priority += trigger.amount;
    _boosts[trigger] = _AppliedBoost(vcam, trigger.amount);
    trigger.isBoosted = true;
  }

  /// Whether the target — or, for a tag, any entity with it — is inside.
  bool _isInside(Entity entity, CameraTriggerComponent trigger) {
    final centre = CameraTargetResolver.positionOf(entity);
    if (centre == null) return false;
    final region = trigger.regionAt(centre);
    for (final target in _targets.resolveTargetAll(
      trigger.target,
      owner: entity,
    )) {
      final at = CameraTargetResolver.positionOf(target);
      if (at != null && region.contains(at)) return true;
    }
    return false;
  }
}

/// A priority boost in force: which camera got it, and how much.
class _AppliedBoost {
  _AppliedBoost(this.vcam, this.amount);
  final VirtualCameraComponent vcam;
  final int amount;
}
