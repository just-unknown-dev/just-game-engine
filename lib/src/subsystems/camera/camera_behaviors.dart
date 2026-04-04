/// Camera Behaviors
///
/// Pluggable movement and control behaviors driven each frame by [CameraSystem].
///
/// Add to [CameraSystem] via [CameraSystem.addBehavior]:
/// ```dart
/// cameraSystem.addBehavior(SpringFollowBehavior(target: player.position));
/// ```
library;

import 'package:flutter/material.dart';

import 'camera_system.dart';

// ─── SpringFollowBehavior ─────────────────────────────────────────────────────

/// Continuously follows a target position using the camera's spring smoothing.
///
/// Update the live target each frame by calling [updateTarget].
///
/// ```dart
/// final follow = SpringFollowBehavior(target: player.position);
/// cameraSystem.addBehavior(follow);
///
/// // In game update:
/// follow.updateTarget(player.position);
/// ```
class SpringFollowBehavior extends CameraBehavior {
  Offset _target;

  /// Dead zone half-extents. Camera only starts moving when the target drifts
  /// more than [deadZoneWidth] px (horizontal) or [deadZoneHeight] px (vertical)
  /// from the current camera position.
  final double deadZoneWidth;
  final double deadZoneHeight;

  SpringFollowBehavior({
    required Offset target,
    this.deadZoneWidth = 0.0,
    this.deadZoneHeight = 0.0,
  }) : _target = target;

  /// Update the follow target (call every frame from an ECS system or game screen).
  void updateTarget(Offset target) => _target = target;

  @override
  void update(Camera camera, double dt) {
    if (deadZoneWidth > 0 || deadZoneHeight > 0) {
      final diff = _target - camera.position;
      if (diff.dx.abs() <= deadZoneWidth && diff.dy.abs() <= deadZoneHeight) {
        return;
      }
    }
    camera.lookAt(_target, smooth: true);
  }

  @override
  bool get isComplete => false;
}

// ─── LookaheadBehavior ────────────────────────────────────────────────────────

/// Follow behavior that anticipates movement by offsetting the target in the
/// direction of travel.
///
/// The lookahead offset scales with speed: at [maxSpeed] the full
/// [lookaheadDistance] is applied; below [maxSpeed] it scales linearly.
///
/// ```dart
/// final la = LookaheadBehavior(
///   targetPosition: player.position,
///   targetVelocity: player.velocity,
/// );
/// cameraSystem.addBehavior(la);
///
/// // In game update:
/// la.updateTarget(player.position, player.velocity);
/// ```
class LookaheadBehavior extends CameraBehavior {
  Offset _position;
  Offset _velocity;

  /// Maximum lookahead offset in world units.
  final double lookaheadDistance;

  /// Speed (world px/s) at which the full [lookaheadDistance] is applied.
  final double maxSpeed;

  LookaheadBehavior({
    required Offset targetPosition,
    required Offset targetVelocity,
    this.lookaheadDistance = 100.0,
    this.maxSpeed = 300.0,
  }) : _position = targetPosition,
       _velocity = targetVelocity;

  void updateTarget(Offset position, Offset velocity) {
    _position = position;
    _velocity = velocity;
  }

  @override
  void update(Camera camera, double dt) {
    final speed = _velocity.distance;
    if (speed < 1.0) {
      camera.lookAt(_position, smooth: true);
      return;
    }
    final speedFactor = (speed / maxSpeed).clamp(0.0, 1.0);
    final lookahead = (_velocity / speed) * lookaheadDistance * speedFactor;
    camera.lookAt(_position + lookahead, smooth: true);
  }

  @override
  bool get isComplete => false;
}

// ─── MultiTargetBehavior ──────────────────────────────────────────────────────

/// Keeps multiple world-space positions simultaneously visible by computing
/// their bounding box and auto-adjusting camera position and zoom.
///
/// ```dart
/// final mt = MultiTargetBehavior(
///   targets: [player1.position, player2.position],
///   padding: 120.0,
/// );
/// cameraSystem.addBehavior(mt);
///
/// // Update targets live:
/// mt.targets
///   ..[0] = player1.position
///   ..[1] = player2.position;
/// ```
class MultiTargetBehavior extends CameraBehavior {
  /// Live list of world-space target positions.  Mutate directly each frame.
  List<Offset> targets;

  /// Extra padding (world units) around the bounding box.
  final double padding;

  /// Minimum zoom level when zooming to fit.
  final double minZoom;

  /// Maximum zoom level when zooming to fit.
  final double maxZoom;

  MultiTargetBehavior({
    required List<Offset> targets,
    this.padding = 100.0,
    this.minZoom = 0.3,
    this.maxZoom = 2.0,
  }) : targets = List.of(targets);

  @override
  void update(Camera camera, double dt) {
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      camera.lookAt(targets.first, smooth: true);
      return;
    }

    double left = targets.first.dx;
    double right = targets.first.dx;
    double top = targets.first.dy;
    double bottom = targets.first.dy;
    for (final t in targets) {
      if (t.dx < left) left = t.dx;
      if (t.dx > right) right = t.dx;
      if (t.dy < top) top = t.dy;
      if (t.dy > bottom) bottom = t.dy;
    }

    final center = Offset((left + right) / 2, (top + bottom) / 2);
    final aabbW = (right - left) + padding * 2;
    final aabbH = (bottom - top) + padding * 2;

    double targetZoom = camera.zoom;
    if (camera.viewportSize != Size.zero) {
      final zoomX = camera.viewportSize.width / aabbW;
      final zoomY = camera.viewportSize.height / aabbH;
      targetZoom = (zoomX < zoomY ? zoomX : zoomY).clamp(minZoom, maxZoom);
    }

    camera.lookAt(center, smooth: true);
    camera.setZoom(targetZoom, smooth: true);
  }

  @override
  bool get isComplete => false;
}

// ─── PathBehavior ─────────────────────────────────────────────────────────────

/// A single keyframe on a [CameraPath].
class CameraKeyframe {
  /// World-space camera position at this keyframe.
  final Offset position;

  /// Zoom level at this keyframe.
  final double zoom;

  /// Rotation in radians at this keyframe.
  final double rotation;

  /// Arrival time in seconds from the start of the path.
  final double time;

  /// Easing applied to the segment that leads INTO this keyframe.
  final Curve easing;

  const CameraKeyframe({
    required this.position,
    this.zoom = 1.0,
    this.rotation = 0.0,
    required this.time,
    this.easing = Curves.linear,
  });
}

/// An ordered sequence of [CameraKeyframe] values.
class CameraPath {
  final List<CameraKeyframe> keyframes;

  CameraPath(this.keyframes)
    : assert(keyframes.isNotEmpty, 'CameraPath needs at least one keyframe.');

  double get duration => keyframes.last.time;
}

/// Drives the camera along a [CameraPath] over time.
///
/// Position, zoom and rotation are set **directly** (bypasses spring) so the
/// motion exactly matches the authored keyframes.
///
/// ```dart
/// cameraSystem.addBehavior(PathBehavior(
///   path: CameraPath([
///     CameraKeyframe(position: Offset.zero, time: 0),
///     CameraKeyframe(position: Offset(400, 0), zoom: 1.5, time: 2.0,
///                    easing: Curves.easeInOut),
///   ]),
///   onComplete: () => print('path done'),
/// ));
/// ```
class PathBehavior extends CameraBehavior {
  final CameraPath path;
  final bool loop;
  final VoidCallback? onComplete;

  double _elapsed = 0.0;
  bool _done = false;

  PathBehavior({required this.path, this.loop = false, this.onComplete});

  @override
  void update(Camera camera, double dt) {
    if (_done) return;
    _elapsed += dt;

    if (_elapsed >= path.duration) {
      if (loop) {
        _elapsed = _elapsed % path.duration;
      } else {
        _elapsed = path.duration;
        _applyAtTime(camera, _elapsed);
        _done = true;
        onComplete?.call();
        return;
      }
    }
    _applyAtTime(camera, _elapsed);
  }

  void _applyAtTime(Camera camera, double t) {
    final kf = path.keyframes;
    if (kf.length == 1) {
      camera.setPosition(kf[0].position);
      camera.setZoom(kf[0].zoom);
      camera.rotation = kf[0].rotation;
      return;
    }

    int next = kf.length - 1;
    for (int i = 1; i < kf.length; i++) {
      if (kf[i].time >= t) {
        next = i;
        break;
      }
    }
    final prev = next - 1;
    final prevKf = kf[prev];
    final nextKf = kf[next];
    final segDur = nextKf.time - prevKf.time;
    final rawT = segDur > 0
        ? ((t - prevKf.time) / segDur).clamp(0.0, 1.0)
        : 1.0;
    final easedT = nextKf.easing.transform(rawT);

    // setPosition/setZoom with smooth=false bypass the spring so values are exact.
    camera.setPosition(
      Offset(
        prevKf.position.dx + (nextKf.position.dx - prevKf.position.dx) * easedT,
        prevKf.position.dy + (nextKf.position.dy - prevKf.position.dy) * easedT,
      ),
    );
    camera.setZoom(prevKf.zoom + (nextKf.zoom - prevKf.zoom) * easedT);
    camera.rotation =
        prevKf.rotation + (nextKf.rotation - prevKf.rotation) * easedT;
  }

  @override
  bool get isComplete => _done;
}

// ─── RoomBehavior ─────────────────────────────────────────────────────────────

/// A bounded rectangular room definition for [RoomBehavior].
class CameraRoom {
  final String id;
  final Rect bounds;

  const CameraRoom({required this.id, required this.bounds});

  Offset get center => bounds.center;
}

/// Snaps and transitions the camera between defined rooms, then clamps
/// camera movement within the active room's bounds.
///
/// ```dart
/// final rooms = RoomBehavior()
///   ..addRoom(CameraRoom(id: 'start', bounds: Rect.fromLTWH(0, 0, 800, 600)))
///   ..addRoom(CameraRoom(id: 'cave',  bounds: Rect.fromLTWH(800, 0, 800, 600)));
/// cameraSystem.addBehavior(rooms);
/// rooms.activateRoom('start');
///
/// // Later:
/// rooms.activateRoom('cave', transitionDuration: 0.6);
/// ```
class RoomBehavior extends CameraBehavior {
  final Map<String, CameraRoom> _rooms = {};
  CameraRoom? _activeRoom;
  CameraRoom? _transitionTarget;
  Offset _transitionStart = Offset.zero;
  double _transitionDuration = 0.0;
  double _transitionElapsed = 0.0;

  void addRoom(CameraRoom room) => _rooms[room.id] = room;
  void removeRoom(String id) => _rooms.remove(id);

  CameraRoom? get activeRoom => _activeRoom;

  /// Switch to room [id], optionally animating over [transitionDuration] seconds.
  void activateRoom(String id, {double transitionDuration = 0.5}) {
    final target = _rooms[id];
    if (target == null) return;

    if (_activeRoom == null) {
      // First activation — snap immediately.
      _activeRoom = target;
      return;
    }

    _transitionTarget = target;
    _transitionStart = _activeRoom!.center;
    _transitionDuration = transitionDuration;
    _transitionElapsed = 0.0;
  }

  @override
  void update(Camera camera, double dt) {
    if (_transitionTarget != null) {
      _transitionElapsed += dt;
      final t = _transitionDuration > 0
          ? (_transitionElapsed / _transitionDuration).clamp(0.0, 1.0)
          : 1.0;
      camera.setPosition(
        Offset(
          _transitionStart.dx +
              (_transitionTarget!.center.dx - _transitionStart.dx) * t,
          _transitionStart.dy +
              (_transitionTarget!.center.dy - _transitionStart.dy) * t,
        ),
      );
      if (t >= 1.0) {
        _activeRoom = _transitionTarget;
        _transitionTarget = null;
      }
    }

    // Clamp camera within the active room by setting worldBounds each frame.
    if (_activeRoom != null) {
      camera.worldBounds = _activeRoom!.bounds;
    }
  }

  @override
  bool get isComplete => false;
}

// ─── CinematicBehavior ────────────────────────────────────────────────────────

/// A keyframe in a [CinematicSequence].
class CinematicKeyframe {
  /// Arrival time in seconds from the start of the sequence.
  final double time;
  final Offset position;
  final double zoom;
  final double rotation;

  /// Easing applied to the segment leading INTO this keyframe.
  final Curve easing;

  /// Fires exactly once when the playhead reaches [time].
  final VoidCallback? onArrive;

  const CinematicKeyframe({
    required this.time,
    required this.position,
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.easing = Curves.easeInOut,
    this.onArrive,
  });
}

/// An ordered sequence of [CinematicKeyframe] values.
class CinematicSequence {
  final List<CinematicKeyframe> keyframes;

  CinematicSequence(this.keyframes)
    : assert(
        keyframes.isNotEmpty,
        'CinematicSequence needs at least one keyframe.',
      );

  double get totalDuration => keyframes.last.time;
}

/// Plays back a [CinematicSequence], interpolating camera values between
/// keyframes and firing [CinematicKeyframe.onArrive] callbacks exactly once.
///
/// The camera values are set **directly** (bypasses spring) for exact authoring.
///
/// ```dart
/// cameraSystem.addBehavior(CinematicBehavior(
///   sequence: CinematicSequence([
///     CinematicKeyframe(time: 0, position: Offset.zero),
///     CinematicKeyframe(time: 3, position: Offset(200, 100),
///         easing: Curves.easeIn, onArrive: () => print('arrived')),
///   ]),
///   onComplete: resumeGame,
/// ));
/// ```
class CinematicBehavior extends CameraBehavior {
  final CinematicSequence sequence;
  final VoidCallback? onComplete;

  double _elapsed = 0.0;
  bool _done = false;
  final Set<int> _firedCallbacks = {};

  CinematicBehavior({required this.sequence, this.onComplete});

  @override
  void update(Camera camera, double dt) {
    if (_done) return;
    _elapsed += dt;

    // Fire onArrive callbacks for keyframes the playhead has passed.
    final kf = sequence.keyframes;
    for (int i = 0; i < kf.length; i++) {
      if (!_firedCallbacks.contains(i) && _elapsed >= kf[i].time) {
        _firedCallbacks.add(i);
        kf[i].onArrive?.call();
      }
    }

    if (_elapsed >= sequence.totalDuration) {
      _elapsed = sequence.totalDuration;
      _applyAtTime(camera, _elapsed);
      _done = true;
      onComplete?.call();
      return;
    }
    _applyAtTime(camera, _elapsed);
  }

  void _applyAtTime(Camera camera, double t) {
    final kf = sequence.keyframes;
    if (kf.length == 1) {
      camera.setPosition(kf[0].position);
      camera.setZoom(kf[0].zoom);
      camera.rotation = kf[0].rotation;
      return;
    }

    int next = kf.length - 1;
    for (int i = 1; i < kf.length; i++) {
      if (kf[i].time >= t) {
        next = i;
        break;
      }
    }
    final prev = next - 1;
    final prevKf = kf[prev];
    final nextKf = kf[next];
    final segDur = nextKf.time - prevKf.time;
    final rawT = segDur > 0
        ? ((t - prevKf.time) / segDur).clamp(0.0, 1.0)
        : 1.0;
    final easedT = nextKf.easing.transform(rawT);

    camera.setPosition(
      Offset(
        prevKf.position.dx + (nextKf.position.dx - prevKf.position.dx) * easedT,
        prevKf.position.dy + (nextKf.position.dy - prevKf.position.dy) * easedT,
      ),
    );
    camera.setZoom(prevKf.zoom + (nextKf.zoom - prevKf.zoom) * easedT);
    camera.rotation =
        prevKf.rotation + (nextKf.rotation - prevKf.rotation) * easedT;
  }

  @override
  bool get isComplete => _done;
}
