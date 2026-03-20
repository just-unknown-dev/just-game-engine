part of '../animation_system.dart';

/// Sprite animation for frame-based animations
class SpriteAnimation extends Animation {
  /// The sprite to animate
  final Sprite sprite;

  /// List of frame rectangles from sprite sheet
  final List<Rect> frames;

  /// Current frame index
  int currentFrame = 0;

  /// Create a sprite animation
  SpriteAnimation({
    required this.sprite,
    required this.frames,
    required super.duration,
    super.loop = true,
    super.onComplete,
  });

  @override
  void updateAnimation(double deltaTime) {
    // Calculate current frame
    final frameIndex = (normalizedTime * frames.length).floor();
    currentFrame = frameIndex.clamp(0, frames.length - 1);

    // Update sprite source rect
    sprite.sourceRect = frames[currentFrame];
  }

  /// Create from sprite sheet
  static SpriteAnimation fromSpriteSheet({
    required Sprite sprite,
    required int frameCount,
    required int frameWidth,
    required int frameHeight,
    required double duration,
    int startFrame = 0,
    bool loop = true,
  }) {
    final frames = <Rect>[];
    for (int i = 0; i < frameCount; i++) {
      final x = ((startFrame + i) * frameWidth) % sprite.image!.width;
      final y =
          ((startFrame + i) * frameWidth ~/ sprite.image!.width) * frameHeight;
      frames.add(
        Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          frameWidth.toDouble(),
          frameHeight.toDouble(),
        ),
      );
    }

    return SpriteAnimation(
      sprite: sprite,
      frames: frames,
      duration: duration,
      loop: loop,
    );
  }
}
