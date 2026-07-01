library;

import '../../ecs.dart';
import '../rendering/animated_sprite_component.dart' show TransformKeyframe;
import 'animation_event.dart';

/// Drives transform animations on an entity via a flat keyframe timeline.
///
/// Unlike [AnimatedSpriteComponent] (which uses named clips), this component
/// has a single timeline of [duration] seconds. It interpolates
/// [TransformKeyframe]s onto the entity's [TransformComponent] and fires
/// [AnimationEvent]s as the playhead advances.
class AnimationControllerComponent extends Component {
  AnimationControllerComponent({
    this.duration = 1.0,
    this.loop = false,
    this.playOnStart = false,
    List<TransformKeyframe>? keyframes,
    List<AnimationEvent>? events,
  }) : keyframes =
           keyframes == null
               ? <TransformKeyframe>[]
               : List<TransformKeyframe>.from(keyframes),
       events =
           events == null
               ? <AnimationEvent>[]
               : List<AnimationEvent>.from(events);

  // ── Configuration ─────────────────────────────────────────────────────────

  /// Total length of the animation in seconds.
  double duration;

  /// Whether the animation restarts after reaching [duration].
  bool loop;

  /// Start playing automatically on the first system update.
  bool playOnStart;

  // ── Runtime state ─────────────────────────────────────────────────────────

  bool isPlaying = false;
  bool initialized = false;

  /// Playback position in seconds.
  double elapsed = 0.0;

  // ── Data ──────────────────────────────────────────────────────────────────

  /// Transform keyframes sorted by time.
  final List<TransformKeyframe> keyframes;

  /// Named event markers sorted by time.
  final List<AnimationEvent> events;

  // ── Playback control ──────────────────────────────────────────────────────

  void play() => isPlaying = true;
  void pause() => isPlaying = false;

  void stop() {
    isPlaying = false;
    elapsed = 0.0;
  }

  // ── Keyframe mutation ─────────────────────────────────────────────────────

  void addOrUpdateKeyframe(TransformKeyframe kf) {
    const eps = 0.05;
    final idx = keyframes.indexWhere((k) => (k.time - kf.time).abs() < eps);
    if (idx >= 0) {
      keyframes[idx] = keyframes[idx].copyWith(
        posX: kf.posX ?? keyframes[idx].posX,
        posY: kf.posY ?? keyframes[idx].posY,
        rotation: kf.rotation ?? keyframes[idx].rotation,
        scaleX: kf.scaleX ?? keyframes[idx].scaleX,
        scaleY: kf.scaleY ?? keyframes[idx].scaleY,
        easing: kf.easing,
      );
    } else {
      keyframes
        ..add(kf)
        ..sort((a, b) => a.time.compareTo(b.time));
    }
  }

  void removeKeyframe(int index) => keyframes.removeAt(index);

  void moveKeyframe(int index, double newTime) {
    final kf = keyframes.removeAt(index).copyWith(time: newTime);
    keyframes
      ..add(kf)
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  // ── Event mutation ────────────────────────────────────────────────────────

  void addEvent(AnimationEvent event) {
    events
      ..add(event)
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  void removeEvent(int index) => events.removeAt(index);

  void moveEvent(int index, double newTime) {
    final ev = events.removeAt(index);
    events
      ..add(AnimationEvent(time: newTime, name: ev.name))
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'duration': duration,
    'loop': loop,
    'playOnStart': playOnStart,
    if (keyframes.isNotEmpty)
      'keyframes': keyframes.map((k) => k.toJson()).toList(),
    if (events.isNotEmpty) 'events': events.map((e) => e.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    duration = (json['duration'] as num?)?.toDouble() ?? duration;
    loop = json['loop'] as bool? ?? loop;
    playOnStart = json['playOnStart'] as bool? ?? playOnStart;

    keyframes.clear();
    final kfsJson = json['keyframes'] as List?;
    if (kfsJson != null) {
      keyframes.addAll(
        kfsJson.map((k) => TransformKeyframe.fromJson(k as Map<String, dynamic>)),
      );
    }

    events.clear();
    final evJson = json['events'] as List?;
    if (evJson != null) {
      events.addAll(
        evJson.map((e) => AnimationEvent.fromJson(e as Map<String, dynamic>)),
      );
    }
  }
}
