library;

// ── Easing ────────────────────────────────────────────────────────────────────

enum KeyframeEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut;

  double apply(double t) => switch (this) {
    linear => t,
    easeIn => t * t,
    easeOut => t * (2 - t),
    easeInOut => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t,
  };
}

// ── TransformKeyframe ─────────────────────────────────────────────────────────

/// A single time-stamped snapshot of transform properties on a clip.
///
/// Only properties that are non-null participate in interpolation for their
/// respective timeline tracks. Time is in seconds from the start of the clip.
class TransformKeyframe {
  const TransformKeyframe({
    required this.time,
    this.posX,
    this.posY,
    this.rotation,
    this.scaleX,
    this.scaleY,
    this.easing = KeyframeEasing.linear,
  });

  final double time;
  final double? posX;
  final double? posY;
  final double? rotation;
  final double? scaleX;
  final double? scaleY;
  final KeyframeEasing easing;

  factory TransformKeyframe.fromJson(Map<String, dynamic> json) =>
      TransformKeyframe(
        time: (json['time'] as num).toDouble(),
        posX: (json['posX'] as num?)?.toDouble(),
        posY: (json['posY'] as num?)?.toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble(),
        scaleX: (json['scaleX'] as num?)?.toDouble(),
        scaleY: (json['scaleY'] as num?)?.toDouble(),
        easing: KeyframeEasing.values.firstWhere(
          (e) => e.name == (json['easing'] as String? ?? 'linear'),
          orElse: () => KeyframeEasing.linear,
        ),
      );

  Map<String, dynamic> toJson() => {
    'time': time,
    if (posX != null) 'posX': posX,
    if (posY != null) 'posY': posY,
    if (rotation != null) 'rotation': rotation,
    if (scaleX != null) 'scaleX': scaleX,
    if (scaleY != null) 'scaleY': scaleY,
    if (easing != KeyframeEasing.linear) 'easing': easing.name,
  };

  TransformKeyframe copyWith({
    double? time,
    Object? posX = _sentinel,
    Object? posY = _sentinel,
    Object? rotation = _sentinel,
    Object? scaleX = _sentinel,
    Object? scaleY = _sentinel,
    KeyframeEasing? easing,
  }) => TransformKeyframe(
    time: time ?? this.time,
    posX: posX == _sentinel ? this.posX : posX as double?,
    posY: posY == _sentinel ? this.posY : posY as double?,
    rotation: rotation == _sentinel ? this.rotation : rotation as double?,
    scaleX: scaleX == _sentinel ? this.scaleX : scaleX as double?,
    scaleY: scaleY == _sentinel ? this.scaleY : scaleY as double?,
    easing: easing ?? this.easing,
  );
}

const _sentinel = Object();
