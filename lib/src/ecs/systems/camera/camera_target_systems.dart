/// The systems that feed the camera brain: group centres and trigger zones.
library;

import 'package:flutter/painting.dart' show Offset, Rect;

import '../../../subsystems/camera/camera_targets.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

/// Moves each target group's entity to the weighted centre of its members.
///
/// A member named by tag alone is every entity with that tag — so one
/// member, tag `player`, frames all the players however many have joined.
///
/// Runs before the brain, so a camera following the group frames where the
/// group *is* this frame.
class CameraTargetGroupSystem extends System {
  final CameraTargetResolver _targets = CameraTargetResolver();

  @override
  int get priority => SystemPriorities.camera + 2;

  @override
  List<Type> get requiredComponents => [
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
        for (final target in _targets.resolveMembers(
          name: member.name,
          tag: member.tag,
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
class CameraTriggerSystem extends System {
  final CameraTargetResolver _targets = CameraTargetResolver();

  @override
  int get priority => SystemPriorities.camera + 1;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    CameraTriggerComponent,
  ];

  @override
  void update(double deltaTime) {
    _targets.beginFrame(world);
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
          vcam.enabled = inside;
        case CameraTriggerMode.boostPriority:
          if (inside != trigger.isBoosted) {
            vcam.priority += inside ? trigger.amount : -trigger.amount;
            trigger.isBoosted = inside;
          }
      }
    }
  }

  /// Whether the target — or, for a tag, any entity with it — is inside.
  bool _isInside(Entity entity, CameraTriggerComponent trigger) {
    final centre = CameraTargetResolver.positionOf(entity);
    if (centre == null) return false;
    final region = trigger.regionAt(centre);
    for (final target in _targets.resolveMembers(
      name: trigger.targetName,
      tag: trigger.targetTag,
    )) {
      final at = CameraTargetResolver.positionOf(target);
      if (at != null && region.contains(at)) return true;
    }
    return false;
  }
}
