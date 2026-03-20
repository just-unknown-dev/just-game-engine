library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Sprite component - Sprite rendering data
class SpriteComponent extends Component {
  /// Sprite asset path
  String spritePath;

  /// Current frame (for sprite sheets)
  int frame;

  /// Flip horizontal
  bool flipX;

  /// Flip vertical
  bool flipY;

  /// Tint color
  Color? tint;

  /// Create sprite component
  SpriteComponent({
    required this.spritePath,
    this.frame = 0,
    this.flipX = false,
    this.flipY = false,
    this.tint,
  });

  @override
  String toString() => 'Sprite($spritePath, frame: $frame)';
}
