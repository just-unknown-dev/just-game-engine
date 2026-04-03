library;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../components/camera/camera_follow_component.dart';
import '../system_priorities.dart';
import '../../../subsystems/camera/camera_system.dart';
import '../../../subsystems/camera/camera_behaviors.dart';

/// ECS system that drives the camera based on entities carrying a
/// [CameraFollowComponent].
///
/// ### Single-target mode
/// When exactly one enabled entity has the lowest [CameraFollowComponent.priority]
/// value, the system follows that entity using [LookaheadBehavior] (or plain
/// spring follow when no [VelocityComponent] is present).
///
/// ### Multi-target mode
/// When two or more entities share the same lowest priority, the system switches
/// to a [MultiTargetBehavior] that auto-zooms to keep all targets in view.
///
/// ### Setup
/// ```dart
/// world.addSystem(CameraFollowSystem(cameraSystem: engine.cameraSystem));
/// world.addComponent(player, CameraFollowComponent());
/// ```
class CameraFollowSystem extends System {
  final CameraSystem cameraSystem;

  CameraFollowSystem({required this.cameraSystem});

  @override
  int get priority => SystemPriorities.camera;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    CameraFollowComponent,
  ];

  // Cached behavior references to avoid re-adding every frame.
  LookaheadBehavior? _lookahead;
  SpringFollowBehavior? _springFollow;
  MultiTargetBehavior? _multiTarget;

  @override
  void update(double deltaTime) {
    // Collect enabled follow entities grouped by priority.
    final byPriority = <int, List<_FollowEntry>>{};

    for (final archetype in world.queryArchetypes(requiredComponents)) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final follows = archetype.getColumn(CameraFollowComponent)!;
      // Optional velocity column (may be null if archetype has no velocity).
      final velocities = archetype.getColumn(VelocityComponent);

      for (int i = 0; i < transforms.length; i++) {
        final follow = follows[i] as CameraFollowComponent;
        if (!follow.enabled) continue;

        final transform = transforms[i] as TransformComponent;
        final vel = velocities != null
            ? (velocities[i] as VelocityComponent).velocity
            : Offset.zero;

        byPriority
            .putIfAbsent(follow.priority, () => [])
            .add(
              _FollowEntry(
                position: transform.position,
                velocity: vel,
                lookaheadDistance: follow.lookaheadDistance,
                deadZoneWidth: follow.deadZoneWidth,
                deadZoneHeight: follow.deadZoneHeight,
              ),
            );
      }
    }

    if (byPriority.isEmpty) {
      _clearBehaviors();
      return;
    }

    // Find the lowest (most important) priority level.
    final lowestPriority = byPriority.keys.reduce((a, b) => a < b ? a : b);
    final targets = byPriority[lowestPriority]!;

    if (targets.length == 1) {
      _applySingleTarget(targets.first);
    } else {
      _applyMultiTarget(targets);
    }
  }

  void _applySingleTarget(_FollowEntry entry) {
    // Remove multi-target if it was active.
    if (_multiTarget != null) {
      cameraSystem.removeBehavior(_multiTarget!);
      _multiTarget = null;
    }

    final hasVelocity = entry.velocity != Offset.zero;

    if (hasVelocity) {
      // Use lookahead behavior.
      if (_springFollow != null) {
        cameraSystem.removeBehavior(_springFollow!);
        _springFollow = null;
      }
      if (_lookahead == null) {
        _lookahead = LookaheadBehavior(
          targetPosition: entry.position,
          targetVelocity: entry.velocity,
          lookaheadDistance: entry.lookaheadDistance,
        );
        cameraSystem.addBehavior(_lookahead!);
      } else {
        _lookahead!.updateTarget(entry.position, entry.velocity);
      }
    } else {
      // Use spring follow (no velocity data available).
      if (_lookahead != null) {
        cameraSystem.removeBehavior(_lookahead!);
        _lookahead = null;
      }
      if (_springFollow == null) {
        _springFollow = SpringFollowBehavior(
          target: entry.position,
          deadZoneWidth: entry.deadZoneWidth,
          deadZoneHeight: entry.deadZoneHeight,
        );
        cameraSystem.addBehavior(_springFollow!);
      } else {
        _springFollow!.updateTarget(entry.position);
      }
    }
  }

  void _applyMultiTarget(List<_FollowEntry> entries) {
    // Remove single-target behaviors if they were active.
    if (_lookahead != null) {
      cameraSystem.removeBehavior(_lookahead!);
      _lookahead = null;
    }
    if (_springFollow != null) {
      cameraSystem.removeBehavior(_springFollow!);
      _springFollow = null;
    }

    final positions = entries.map((e) => e.position).toList();

    if (_multiTarget == null) {
      _multiTarget = MultiTargetBehavior(targets: positions);
      cameraSystem.addBehavior(_multiTarget!);
    } else {
      // Update live target list in-place.
      _multiTarget!.targets
        ..clear()
        ..addAll(positions);
    }
  }

  void _clearBehaviors() {
    if (_lookahead != null) {
      cameraSystem.removeBehavior(_lookahead!);
      _lookahead = null;
    }
    if (_springFollow != null) {
      cameraSystem.removeBehavior(_springFollow!);
      _springFollow = null;
    }
    if (_multiTarget != null) {
      cameraSystem.removeBehavior(_multiTarget!);
      _multiTarget = null;
    }
  }
}

/// Internal data transfer record for a follow entity.
class _FollowEntry {
  final Offset position;
  final Offset velocity;
  final double lookaheadDistance;
  final double deadZoneWidth;
  final double deadZoneHeight;

  const _FollowEntry({
    required this.position,
    required this.velocity,
    required this.lookaheadDistance,
    required this.deadZoneWidth,
    required this.deadZoneHeight,
  });
}
