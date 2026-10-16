library;

/// A named time marker within an animation.
///
/// Used by sprite clips (frame events in an atlas). A timeline's events are
/// `TimelineEvent`s on an `EventTrack`.
class AnimationEvent {
  /// An event called [name], [time] seconds into the clip.
  const AnimationEvent({required this.time, required this.name});

  /// Seconds from the start of the clip/controller at which the event fires.
  final double time;

  /// Name dispatched to listeners when the playhead crosses [time].
  final String name;

  /// Reads [toJson]'s shape. A missing or unreadable `time` is 0 — the
  /// start of the clip — and a missing `name` is empty, so one bad entry in
  /// an atlas does not stop the rest from playing.
  factory AnimationEvent.fromJson(Map<String, dynamic> json) {
    final time = json['time'];
    final name = json['name'];
    return AnimationEvent(
      time: time is num && time.isFinite ? time.toDouble() : 0.0,
      name: name is String ? name : '',
    );
  }

  /// This event as a JSON map with `time` (seconds) and `name`, the shape
  /// [AnimationEvent.fromJson] reads.
  Map<String, dynamic> toJson() => {'time': time, 'name': name};
}
