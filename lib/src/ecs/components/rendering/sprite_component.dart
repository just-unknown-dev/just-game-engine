library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// A still image on this entity: a whole image file, or one region of a
/// sprite atlas. [SpriteLoadSystem] loads it and keeps it showing.
class SpriteComponent extends Component {
  /// Asset path of an image to show whole. Ignored when [atlasPath] is set.
  String spritePath;

  /// Asset path of an atlas JSON to take [region] from; empty for a plain
  /// image.
  String atlasPath;

  /// The atlas region to show; empty shows the atlas's first.
  String region;

  /// Flip horizontal
  bool flipX;

  /// Flip vertical
  bool flipY;

  /// Tint color
  Color? tint;

  /// Sample the texture without smoothing, so scaled pixels stay square.
  bool pixelArt;

  /// Create sprite component
  SpriteComponent({
    required this.spritePath,
    this.atlasPath = '',
    this.region = '',
    this.flipX = false,
    this.flipY = false,
    this.tint,
    this.pixelArt = false,
  });

  @override
  String toString() =>
      'Sprite(${atlasPath.isEmpty ? spritePath : '$atlasPath#$region'})';
}
