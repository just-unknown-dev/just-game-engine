library;

/// A named time marker within an animation.
///
/// Used by both [AnimationClip] (sprite timeline) and
/// [AnimationControllerComponent] (entity timeline).
class AnimationEvent {
  const AnimationEvent({required this.time, required this.name});

  /// Seconds from the start of the clip/controller at which the event fires.
  final double time;

  /// Name dispatched to listeners when the playhead crosses [time].
  final String name;

  factory AnimationEvent.fromJson(Map<String, dynamic> json) => AnimationEvent(
    time: (json['time'] as num).toDouble(),
    name: json['name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'time': time, 'name': name};
}
