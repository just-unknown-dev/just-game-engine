/// How one piece of UI sits inside another.
library;

import 'package:flutter/widgets.dart';

import '../../../ecs.dart';

/// The two ways a child can be placed.
enum UiSlotMode {
  /// Pinned to its parent by anchors — what a HUD is made of. Unity's
  /// RectTransform, and a `Positioned` inside a `Stack` underneath.
  anchored,

  /// Laid out in order by its parent, a row or a column. Flutter's own
  /// model, and what containers are for.
  flow,
}

/// Where a child is pinned, as a fraction of its parent: `(0,0)` is the
/// top-left corner, `(1,1)` the bottom-right.
///
/// When the two corners are the same point the child keeps its size and
/// hangs off that point; when they are apart it stretches between them.
class UiAnchor {
  const UiAnchor(this.min, this.max);

  /// The presets an editor offers, in the order a grid shows them.
  static const UiAnchor topLeft = UiAnchor(Offset.zero, Offset.zero);
  static const UiAnchor topCenter = UiAnchor(Offset(0.5, 0), Offset(0.5, 0));
  static const UiAnchor topRight = UiAnchor(Offset(1, 0), Offset(1, 0));
  static const UiAnchor centerLeft = UiAnchor(Offset(0, 0.5), Offset(0, 0.5));
  static const UiAnchor center = UiAnchor(Offset(0.5, 0.5), Offset(0.5, 0.5));
  static const UiAnchor centerRight = UiAnchor(Offset(1, 0.5), Offset(1, 0.5));
  static const UiAnchor bottomLeft = UiAnchor(Offset(0, 1), Offset(0, 1));
  static const UiAnchor bottomCenter = UiAnchor(Offset(0.5, 1), Offset(0.5, 1));
  static const UiAnchor bottomRight = UiAnchor(Offset(1, 1), Offset(1, 1));

  /// Stretched across the whole parent.
  static const UiAnchor stretch = UiAnchor(Offset.zero, Offset(1, 1));

  /// Stretched across the top, the bottom, and so on.
  static const UiAnchor stretchTop = UiAnchor(Offset.zero, Offset(1, 0));
  static const UiAnchor stretchBottom = UiAnchor(Offset(0, 1), Offset(1, 1));
  static const UiAnchor stretchLeft = UiAnchor(Offset.zero, Offset(0, 1));
  static const UiAnchor stretchRight = UiAnchor(Offset(1, 0), Offset(1, 1));

  static const Map<String, UiAnchor> presets = {
    'topLeft': topLeft,
    'topCenter': topCenter,
    'topRight': topRight,
    'centerLeft': centerLeft,
    'center': center,
    'centerRight': centerRight,
    'bottomLeft': bottomLeft,
    'bottomCenter': bottomCenter,
    'bottomRight': bottomRight,
    'stretch': stretch,
    'stretchTop': stretchTop,
    'stretchBottom': stretchBottom,
    'stretchLeft': stretchLeft,
    'stretchRight': stretchRight,
  };

  final Offset min;
  final Offset max;

  bool get stretchesX => (max.dx - min.dx).abs() > 1e-6;
  bool get stretchesY => (max.dy - min.dy).abs() > 1e-6;

  /// The name of the preset this matches, or null for something else.
  String? get presetName {
    for (final entry in presets.entries) {
      if (entry.value == this) return entry.key;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'minX': min.dx,
    'minY': min.dy,
    'maxX': max.dx,
    'maxY': max.dy,
  };

  factory UiAnchor.fromJson(Map<String, dynamic> json) => UiAnchor(
    Offset(
      (json['minX'] as num?)?.toDouble() ?? 0,
      (json['minY'] as num?)?.toDouble() ?? 0,
    ),
    Offset(
      (json['maxX'] as num?)?.toDouble() ?? 0,
      (json['maxY'] as num?)?.toDouble() ?? 0,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is UiAnchor && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'UiAnchor(${presetName ?? '$min–$max'})';
}

/// How a child sits in its parent: pinned by anchors, or in the flow.
class UiSlotComponent extends Component {
  UiSlotComponent({
    this.mode = UiSlotMode.flow,
    this.anchor = UiAnchor.topLeft,
    this.pivot = const Offset(0.5, 0.5),
    this.offset = Offset.zero,
    this.size = const Size(160, 48),
    this.margin = EdgeInsets.zero,
    this.flex = 0,
    this.alignSelf = '',
    this.opacity = 1,
    this.visible = true,
    this.ignorePointer = false,
    this.heroTag = '',
  });

  UiSlotMode mode;

  /// Where in the parent this is pinned. Only for [UiSlotMode.anchored].
  UiAnchor anchor;

  /// Which point of the child lands on the anchor.
  Offset pivot;

  /// How far from the anchor, in design pixels.
  Offset offset;

  /// How big it is, where the anchor does not stretch it.
  Size size;

  /// Space kept around it — the inset from each edge when stretched.
  EdgeInsets margin;

  /// In a row or a column: 0 takes what it needs, more than 0 shares what
  /// is left (Flutter's `Expanded`).
  int flex;

  /// `start`, `center`, `end`, `stretch` — how it sits across its parent's
  /// direction. Empty follows the parent.
  String alignSelf;

  double opacity;
  bool visible;

  /// Lets the pointer through to whatever is behind.
  bool ignorePointer;

  /// Matched between two screens to fly from one to the other.
  String heroTag;

  /// What Flutter alignment [alignSelf] means, or null to follow the parent.
  CrossAxisAlignment? get crossAlignment => switch (alignSelf) {
    'start' => CrossAxisAlignment.start,
    'center' => CrossAxisAlignment.center,
    'end' => CrossAxisAlignment.end,
    'stretch' => CrossAxisAlignment.stretch,
    _ => null,
  };

  /// Where an anchored child goes inside a parent of [parentSize].
  Rect rectIn(Size parentSize) {
    final left = anchor.min.dx * parentSize.width;
    final right = anchor.max.dx * parentSize.width;
    final top = anchor.min.dy * parentSize.height;
    final bottom = anchor.max.dy * parentSize.height;
    // Stretched: the anchors are the edges, and the margin insets them.
    final width = anchor.stretchesX
        ? (right - left) - margin.horizontal
        : size.width;
    final height = anchor.stretchesY
        ? (bottom - top) - margin.vertical
        : size.height;
    final x = anchor.stretchesX
        ? left + margin.left
        : left + offset.dx - width * pivot.dx;
    final y = anchor.stretchesY
        ? top + margin.top
        : top + offset.dy - height * pivot.dy;
    return Rect.fromLTWH(x, y, width < 0 ? 0 : width, height < 0 ? 0 : height);
  }

  @override
  String toString() => 'UiSlot(${mode.name})';
}
