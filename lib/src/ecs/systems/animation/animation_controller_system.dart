library;

import 'dart:async';

import '../../components/components.dart';
import '../../ecs.dart';
import 'package:just_dart/just_dart.dart';

import '../system_priorities.dart';

/// Drives [AnimationControllerComponent]: the entity's transform timeline.
///
/// Each frame this system:
///  1. Seeds [playOnStart] the first time the component is seen.
///  2. Advances [elapsed] according to [duration], looping or stopping.
///  3. Interpolates [TransformKeyframe]s onto the entity's [TransformComponent].
///  4. Fires [AnimationEvent]s as the playhead crosses their timestamps.
///
/// Position keyframes are applied as authored — moving the entity is what
/// this timeline is for.
class AnimationControllerSystem extends System {
  /// Tracks which event keys have already fired in the current playback pass.
  final Map<Entity, Set<String>> _firedEvents = {};

  /// Broadcasts the event name whenever an [AnimationEvent] fires.
  final StreamController<String> eventStream =
      StreamController<String>.broadcast();

  @override
  int get priority => SystemPriorities.animation - 1;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    AnimationControllerComponent,
  ];

  @override
  void update(double deltaTime) {
    // _firedEvents is never revisited for a destroyed entity (forEach only
    // walks currently-matching entities), so without this prune it grows for
    // the lifetime of the process across a long edit session of repeatedly
    // placing/deleting animation-controller entities.
    final live = entities.toSet();
    _firedEvents.removeWhere((entity, _) => !live.contains(entity));

    forEach((entity) {
      final acc = entity.getComponent<AnimationControllerComponent>()!;

      _initPlayOnStart(acc);

      if (acc.isPlaying) {
        final prev = acc.elapsed;
        _advance(acc, deltaTime);
        _fireEvents(entity, acc, prev);
      }

      _applyKeyframes(entity, acc);
    });
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  void _initPlayOnStart(AnimationControllerComponent acc) {
    if (acc.initialized) return;
    acc.initialized = true;
    if (!acc.playOnStart) return;
    acc.isPlaying = true;
  }

  // ── Advancement ────────────────────────────────────────────────────────────

  void _advance(AnimationControllerComponent acc, double dt) {
    acc.elapsed += dt;
    if (acc.elapsed >= acc.duration) {
      if (acc.loop) {
        acc.elapsed = acc.elapsed % acc.duration;
        // Fired-events reset on loop-wrap is handled per-entity in
        // _fireEvents (it clears `fired` when elapsed wraps).
      } else {
        acc.elapsed = acc.duration;
        acc.isPlaying = false;
      }
    }
  }

  // ── Event dispatch ─────────────────────────────────────────────────────────

  void _fireEvents(
    Entity entity,
    AnimationControllerComponent acc,
    double prevElapsed,
  ) {
    if (acc.events.isEmpty) return;

    final fired = _firedEvents.putIfAbsent(entity, () => {});

    // On loop: clear fired set when elapsed wrapped (prev > current)
    if (acc.elapsed < prevElapsed) fired.clear();

    for (final ev in acc.events) {
      final key = '${ev.time}_${ev.name}';
      if (fired.contains(key)) continue;
      if (ev.time > prevElapsed && ev.time <= acc.elapsed) {
        fired.add(key);
        eventStream.add(ev.name);
      }
    }
  }

  void resetFiredEvents(Entity entity) => _firedEvents.remove(entity);

  // ── Keyframe interpolation ─────────────────────────────────────────────────

  void _applyKeyframes(Entity entity, AnimationControllerComponent acc) {
    if (acc.keyframes.isEmpty) return;
    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;
    _interpolateAtTime(transform, acc.keyframes, acc.elapsed);
  }

  void _interpolateAtTime(
    TransformComponent transform,
    List<TransformKeyframe> keyframes,
    double t,
  ) {
    TransformKeyframe? prev;
    TransformKeyframe? next;

    for (final kf in keyframes) {
      if (kf.time <= t) {
        prev = kf;
      } else {
        next ??= kf;
      }
    }

    if (prev == null && next == null) return;

    if (prev == null) {
      _applyValues(transform, next!, 1.0, next);
      return;
    }
    if (next == null) {
      _applyValues(transform, prev, 1.0, prev);
      return;
    }

    final span = next.time - prev.time;
    final localT = span > 0 ? ((t - prev.time) / span).clamp(0.0, 1.0) : 1.0;
    final easedT = prev.easing.apply(localT);
    _applyValues(transform, prev, easedT, next);
  }

  void _applyValues(
    TransformComponent transform,
    TransformKeyframe from,
    double t,
    TransformKeyframe to,
  ) {
    double lerp(double? a, double? b, double fallback) {
      if (a == null && b == null) return fallback;
      final fa = a ?? fallback;
      final fb = b ?? fallback;
      return fa + (fb - fa) * t;
    }

    final newX = lerp(from.posX, to.posX, transform.position.x);
    final newY = lerp(from.posY, to.posY, transform.position.y);
    final newRot = lerp(from.rotation, to.rotation, transform.rotation);
    final newSX = lerp(from.scaleX, to.scaleX, transform.scale.x);
    final newSY = lerp(from.scaleY, to.scaleY, transform.scale.y);

    if (from.posX != null ||
        to.posX != null ||
        from.posY != null ||
        to.posY != null) {
      transform.position = Vector3(newX, newY, transform.position.z);
    }
    if (from.rotation != null || to.rotation != null) {
      transform.rotation = newRot;
    }
    if (from.scaleX != null ||
        to.scaleX != null ||
        from.scaleY != null ||
        to.scaleY != null) {
      transform.scale = Vector3(newSX, newSY, transform.scale.z);
    }
  }
}
