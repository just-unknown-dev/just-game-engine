/// Blend Tree Motions
///
/// What a [BlendState] plays: either a single clip with no blending, or a
/// parametric blend tree over several clips. These are pure data — see
/// `AnimationBlendTreeSystem` (`lib/src/ecs/systems/animation/`) for the
/// per-frame evaluation logic that turns a [BlendMotion] plus live
/// parameter values into weighted clip contributions.
library;

import 'package:flutter/painting.dart' show Offset;

import '../../../subsystems/animation/blend/blend.dart';

/// What a [BlendState] plays. `sealed` so `AnimationBlendTreeSystem` can
/// switch over the concrete variants exhaustively.
sealed class BlendMotion {
  const BlendMotion();

  factory BlendMotion.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'clip';
    return switch (type) {
      'blendTree1D' => BlendTree1DMotion.fromJson(json),
      'blendTree2D' => BlendTree2DMotion.fromJson(json),
      _ => ClipMotion.fromJson(json),
    };
  }

  Map<String, dynamic> toJson();
}

/// Plays a single named clip with no blending.
class ClipMotion extends BlendMotion {
  const ClipMotion(this.clip);

  final String clip;

  factory ClipMotion.fromJson(Map<String, dynamic> json) =>
      ClipMotion(json['clip'] as String);

  @override
  Map<String, dynamic> toJson() => {'type': 'clip', 'clip': clip};
}

/// One (threshold, clip) sample in a [BlendTree1DMotion].
class BlendTree1DChild {
  const BlendTree1DChild({required this.threshold, required this.clip});

  final double threshold;
  final String clip;

  factory BlendTree1DChild.fromJson(Map<String, dynamic> json) =>
      BlendTree1DChild(
        threshold: (json['threshold'] as num).toDouble(),
        clip: json['clip'] as String,
      );

  Map<String, dynamic> toJson() => {'threshold': threshold, 'clip': clip};
}

/// Blends several clips along a single float [parameter] using
/// [BlendSpace1D].
class BlendTree1DMotion extends BlendMotion {
  factory BlendTree1DMotion({
    required String parameter,
    required List<BlendTree1DChild> children,
  }) {
    final sorted = [...children]
      ..sort((a, b) => a.threshold.compareTo(b.threshold));
    return BlendTree1DMotion._(parameter, sorted);
  }

  BlendTree1DMotion._(this.parameter, List<BlendTree1DChild> sortedChildren)
    : children = List.unmodifiable(sortedChildren),
      space = BlendSpace1D(sortedChildren.map((c) => c.threshold).toList());

  final String parameter;

  /// Sorted ascending by threshold; index-aligned with [space].
  final List<BlendTree1DChild> children;
  final BlendSpace1D space;

  factory BlendTree1DMotion.fromJson(Map<String, dynamic> json) =>
      BlendTree1DMotion(
        parameter: json['parameter'] as String,
        children: (json['children'] as List)
            .map(
              (c) => BlendTree1DChild.fromJson(
                (c as Map).cast<String, dynamic>(),
              ),
            )
            .toList(),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'blendTree1D',
    'parameter': parameter,
    'children': children.map((c) => c.toJson()).toList(),
  };
}

/// One (position, clip) sample in a [BlendTree2DMotion].
class BlendTree2DChild {
  const BlendTree2DChild({required this.position, required this.clip});

  final Offset position;
  final String clip;

  factory BlendTree2DChild.fromJson(Map<String, dynamic> json) =>
      BlendTree2DChild(
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        clip: json['clip'] as String,
      );

  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    'clip': clip,
  };
}

/// Blends several clips over a 2D (parameterX, parameterY) plane using
/// Gradient Band Interpolation ([BlendSpace2D]).
class BlendTree2DMotion extends BlendMotion {
  BlendTree2DMotion({
    required this.parameterX,
    required this.parameterY,
    required List<BlendTree2DChild> children,
  }) : children = List.unmodifiable(children),
       space = BlendSpace2D(children.map((c) => c.position).toList());

  final String parameterX;
  final String parameterY;

  /// Index-aligned with [space].
  final List<BlendTree2DChild> children;
  final BlendSpace2D space;

  factory BlendTree2DMotion.fromJson(Map<String, dynamic> json) =>
      BlendTree2DMotion(
        parameterX: json['parameterX'] as String,
        parameterY: json['parameterY'] as String,
        children: (json['children'] as List)
            .map(
              (c) => BlendTree2DChild.fromJson(
                (c as Map).cast<String, dynamic>(),
              ),
            )
            .toList(),
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'blendTree2D',
    'parameterX': parameterX,
    'parameterY': parameterY,
    'children': children.map((c) => c.toJson()).toList(),
  };
}
