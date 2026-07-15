library;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
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

  /// Optional gate — while this returns `true` (e.g. the level editor is
  /// open and authoring, not the player actually playing), a camera entity
  /// in the world is ignored and this system drives [cameraSystem]'s
  /// mainCamera directly instead, exactly like when no camera entity exists.
  bool Function()? isAuthoringActive;

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

  // Used only when a [CameraComponent] entity is present in the world:
  // behaviors run against this shadow camera instead of [cameraSystem]'s
  // mainCamera, and the result is written onto the camera entity's
  // [TransformComponent]/[CameraComponent.zoom] so
  // [CameraTransformSyncSystem] can mirror it onto the real camera.
  Camera? _shadowCamera;
  bool? _lastModeUsedCameraEntity;

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
            ? (velocities[i] as VelocityComponent).velocity.toOffset()
            : Offset.zero;

        byPriority
            .putIfAbsent(follow.priority, () => [])
            .add(
              _FollowEntry(
                position: transform.position.toOffset(),
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
      _lastModeUsedCameraEntity = null;
      return;
    }

    // Find the lowest (most important) priority level.
    final lowestPriority = byPriority.keys.reduce((a, b) => a < b ? a : b);
    final targets = byPriority[lowestPriority]!;

    final authoring = isAuthoringActive?.call() ?? false;
    final cameraEntities = authoring
        ? const <Entity>[]
        : world.query([TransformComponent, CameraComponent]);
    final camEntity = cameraEntities.isEmpty ? null : cameraEntities.first;

    // If the presence of a camera entity changed since last frame, drop any
    // cached behaviors so they get recreated cleanly for the new mode
    // instead of being driven against the wrong output.
    final usingCameraEntity = camEntity != null;
    if (_lastModeUsedCameraEntity != null &&
        _lastModeUsedCameraEntity != usingCameraEntity) {
      _clearBehaviors();
    }
    _lastModeUsedCameraEntity = usingCameraEntity;

    if (targets.length == 1) {
      _applySingleTarget(targets.first, camEntity, deltaTime);
    } else {
      _applyMultiTarget(targets, camEntity, deltaTime);
    }
  }

  void _applySingleTarget(
    _FollowEntry entry,
    Entity? camEntity,
    double deltaTime,
  ) {
    // Remove multi-target if it was active.
    if (_multiTarget != null) {
      cameraSystem.removeBehavior(_multiTarget!);
      _multiTarget = null;
    }

    final hasVelocity = entry.velocity != Offset.zero;
    final CameraBehavior active;

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
        if (camEntity == null) cameraSystem.addBehavior(_lookahead!);
      } else {
        _lookahead!.updateTarget(entry.position, entry.velocity);
      }
      active = _lookahead!;
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
        if (camEntity == null) cameraSystem.addBehavior(_springFollow!);
      } else {
        _springFollow!.updateTarget(entry.position);
      }
      active = _springFollow!;
    }

    if (camEntity != null) {
      _driveCameraEntity(camEntity, active, deltaTime);
    }
  }

  void _applyMultiTarget(
    List<_FollowEntry> entries,
    Entity? camEntity,
    double deltaTime,
  ) {
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
      if (camEntity == null) cameraSystem.addBehavior(_multiTarget!);
    } else {
      // Update live target list in-place.
      _multiTarget!.targets
        ..clear()
        ..addAll(positions);
    }

    if (camEntity != null) {
      _driveCameraEntity(camEntity, _multiTarget!, deltaTime);
    }
  }

  /// Runs [behavior] against a private shadow camera (never registered with
  /// [cameraSystem]) and writes the result onto [camEntity]'s transform/zoom.
  void _driveCameraEntity(
    Entity camEntity,
    CameraBehavior behavior,
    double deltaTime,
  ) {
    final transform = camEntity.getComponent<TransformComponent>();
    final camComponent = camEntity.getComponent<CameraComponent>();
    if (transform == null || camComponent == null) return;

    final shadow = _shadowCamera ??= Camera(
      position: transform.position.toOffset(),
      zoom: camComponent.zoom,
    );
    // Mirror live camera settings so spring feel / zoom limits / viewport
    // match what mainCamera would otherwise use.
    shadow.viewportSize = cameraSystem.mainCamera.viewportSize;
    shadow.minZoom = cameraSystem.mainCamera.minZoom;
    shadow.maxZoom = cameraSystem.mainCamera.maxZoom;
    shadow.useSpring = cameraSystem.mainCamera.useSpring;
    shadow.springStiffness = cameraSystem.mainCamera.springStiffness;
    shadow.springDamping = cameraSystem.mainCamera.springDamping;
    shadow.worldBounds = camComponent.bounds;

    behavior.update(shadow, deltaTime);
    shadow.update(deltaTime);

    transform.setPositionXY(shadow.position.dx, shadow.position.dy);
    camComponent.zoom = shadow.zoom;
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
