part of 'particles.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Abstract base
// ═══════════════════════════════════════════════════════════════════════════════

/// Base class for all particle renderers.
///
/// A [ParticleRenderer] is attached to a [ParticleEmitter] and is responsible
/// for drawing one or more particles onto a [Canvas].  The default
/// [renderBatch] implementation iterates and calls [render] per particle; high-
/// throughput renderers (e.g. [SpriteParticleRenderer]) override [renderBatch]
/// to coalesce into a single draw call.
abstract class ParticleRenderer {
  const ParticleRenderer();

  /// Draw a single [particle] onto [canvas].
  void render(Canvas canvas, Particle particle);

  /// Draw all [particles] onto [canvas].
  ///
  /// The default implementation calls [render] for every particle.
  /// Override to batch draw calls.
  void renderBatch(Canvas canvas, List<Particle> particles) {
    for (final p in particles) {
      render(canvas, p);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Geometric renderers
// ═══════════════════════════════════════════════════════════════════════════════

/// Renders each particle as a filled circle.
class CircleParticleRenderer extends ParticleRenderer {
  /// Paint reused across all draw calls to avoid per-frame allocation.
  final Paint _paint = Paint()..style = PaintingStyle.fill;

  @override
  void render(Canvas canvas, Particle particle) {
    _paint.color = particle.currentColor;
    final radius = particle.currentSize / 2.0;
    canvas.drawCircle(particle.position, radius, _paint);
  }
}

/// Renders each particle as a filled square (axis-aligned, rotatable).
class SquareParticleRenderer extends ParticleRenderer {
  final Paint _paint = Paint()..style = PaintingStyle.fill;
  final Path _path = Path();

  @override
  void render(Canvas canvas, Particle particle) {
    _paint.color = particle.currentColor;
    final s = particle.currentSize;
    final half = s / 2.0;

    if (particle.rotation == 0.0) {
      canvas.drawRect(
        Rect.fromCenter(center: particle.position, width: s, height: s),
        _paint,
      );
    } else {
      // Rotate around particle center
      canvas.save();
      canvas.translate(particle.position.dx, particle.position.dy);
      canvas.rotate(particle.rotation);
      _path.reset();
      _path
        ..moveTo(-half, -half)
        ..lineTo(half, -half)
        ..lineTo(half, half)
        ..lineTo(-half, half)
        ..close();
      canvas.drawPath(_path, _paint);
      canvas.restore();
    }
  }
}

/// Renders each particle as a filled triangle.
class TriangleParticleRenderer extends ParticleRenderer {
  final Paint _paint = Paint()..style = PaintingStyle.fill;
  final Path _path = Path();

  @override
  void render(Canvas canvas, Particle particle) {
    _paint.color = particle.currentColor;
    final s = particle.currentSize;
    final half = s / 2.0;

    canvas.save();
    canvas.translate(particle.position.dx, particle.position.dy);
    canvas.rotate(particle.rotation);
    _path.reset();
    _path
      ..moveTo(0, -half)
      ..lineTo(half, half)
      ..lineTo(-half, half)
      ..close();
    canvas.drawPath(_path, _paint);
    canvas.restore();
  }
}

/// Renders each particle as a 5-pointed star.
class StarParticleRenderer extends ParticleRenderer {
  final Paint _paint = Paint()..style = PaintingStyle.fill;
  final Path _path = Path();

  @override
  void render(Canvas canvas, Particle particle) {
    _paint.color = particle.currentColor;
    final radius = particle.currentSize / 2.0;

    canvas.save();
    canvas.translate(particle.position.dx, particle.position.dy);
    canvas.rotate(particle.rotation);
    _drawStar(canvas, Offset.zero, radius, _paint);
    canvas.restore();
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    const points = 5;
    _path.reset();
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final r = i.isEven ? radius : radius / 2.0;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        _path.moveTo(x, y);
      } else {
        _path.lineTo(x, y);
      }
    }
    _path.close();
    canvas.drawPath(_path, paint);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Image-based renderers
// ═══════════════════════════════════════════════════════════════════════════════

/// Renders each particle using a [ui.Image], batched via [Canvas.drawAtlas].
///
/// [Canvas.drawAtlas] produces a single draw call for the entire batch,
/// significantly reducing driver overhead when many particles share the same
/// image (sprite atlas or simple texture).
///
/// Pre-allocates [RSTransform], [Rect], and [Color] lists up to [maxParticles]
/// to avoid any per-frame heap allocation inside [renderBatch].
class SpriteParticleRenderer extends ParticleRenderer {
  /// The image used as the particle sprite.
  final ui.Image image;

  /// The source rectangle within [image] (defaults to the full image).
  final Rect? sourceRect;

  /// Maximum particles to pre-allocate buffer space for.
  final int maxParticles;

  late final List<RSTransform> _transforms;
  late final List<Rect> _rects;
  late final List<Color> _colors;
  late final Rect _srcRect;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  SpriteParticleRenderer({
    required this.image,
    this.sourceRect,
    this.maxParticles = 1000,
  }) {
    _srcRect =
        sourceRect ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    _transforms = List<RSTransform>.filled(
      maxParticles,
      RSTransform(1, 0, 0, 0),
      growable: false,
    );
    _rects = List<Rect>.filled(maxParticles, _srcRect, growable: false);
    _colors = List<Color>.filled(
      maxParticles,
      const Color(0xFFFFFFFF),
      growable: false,
    );
  }

  @override
  void render(Canvas canvas, Particle particle) {
    // Fallback for single particle (e.g. from base renderBatch default)
    final size = particle.currentSize;
    final scale = size / _srcRect.width.clamp(1.0, double.infinity);
    final transform = RSTransform.fromComponents(
      rotation: particle.rotation,
      scale: scale,
      anchorX: _srcRect.width / 2.0,
      anchorY: _srcRect.height / 2.0,
      translateX: particle.position.dx,
      translateY: particle.position.dy,
    );
    _paint.color = particle.currentColor;
    canvas.drawAtlas(
      image,
      [transform],
      [_srcRect],
      [particle.currentColor],
      BlendMode.modulate,
      null,
      _paint,
    );
  }

  @override
  void renderBatch(Canvas canvas, List<Particle> particles) {
    if (particles.isEmpty) return;
    final count = particles.length.clamp(0, maxParticles);
    for (int i = 0; i < count; i++) {
      final p = particles[i];
      final size = p.currentSize;
      final scale = _srcRect.width > 0 ? size / _srcRect.width : 1.0;
      _transforms[i] = RSTransform.fromComponents(
        rotation: p.rotation,
        scale: scale,
        anchorX: _srcRect.width / 2.0,
        anchorY: _srcRect.height / 2.0,
        translateX: p.position.dx,
        translateY: p.position.dy,
      );
      _rects[i] = _srcRect;
      _colors[i] = p.currentColor;
    }
    canvas.drawAtlas(
      image,
      _transforms.sublist(0, count),
      _rects.sublist(0, count),
      _colors.sublist(0, count),
      BlendMode.modulate,
      null,
      _paint,
    );
  }
}

/// Renders particles as animated sprites, advancing through frames over the
/// particle's lifetime.
///
/// [frames] is the ordered list of source rectangles from [sheet] that form
/// the animation.
class AnimatedSpriteParticleRenderer extends ParticleRenderer {
  /// The sprite sheet image.
  final ui.Image sheet;

  /// Ordered source rectangles for each animation frame.
  final List<Rect> frames;

  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  AnimatedSpriteParticleRenderer({required this.sheet, required this.frames})
    : assert(frames.isNotEmpty, 'frames must not be empty');

  @override
  void render(Canvas canvas, Particle particle) {
    final frameIndex = (particle.normalizedLife * frames.length).floor().clamp(
      0,
      frames.length - 1,
    );
    final src = frames[frameIndex];
    final size = particle.currentSize;
    _paint.color = particle.currentColor;

    canvas.save();
    canvas.translate(particle.position.dx, particle.position.dy);
    canvas.rotate(particle.rotation);
    canvas.drawImageRect(
      sheet,
      src,
      Rect.fromCenter(center: Offset.zero, width: size, height: size),
      _paint,
    );
    canvas.restore();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Special renderers
// ═══════════════════════════════════════════════════════════════════════════════

/// Renders each particle as a line from [Particle.previousPosition] to
/// [Particle.position], creating a motion-blur streak effect.
class LineParticleRenderer extends ParticleRenderer {
  /// Width of the streak line.
  final double strokeWidth;

  final Paint _paint = Paint()..style = PaintingStyle.stroke;

  LineParticleRenderer({this.strokeWidth = 2.0});

  @override
  void render(Canvas canvas, Particle particle) {
    _paint
      ..color = particle.currentColor
      ..strokeWidth = strokeWidth * particle.currentSize / particle.startSize;
    canvas.drawLine(particle.previousPosition, particle.position, _paint);
  }
}

/// Renders each particle as an arbitrary developer-provided [Path].
///
/// The path is drawn centered at [Particle.position] and scaled to
/// [Particle.currentSize].  Supply a path normalized to the unit square
/// (approximately -0.5..0.5 on both axes) for predictable scaling.
class CustomPathParticleRenderer extends ParticleRenderer {
  /// The path to draw (normalized to roughly [-0.5, 0.5] bounds).
  final Path path;

  final Paint _paint = Paint()..style = PaintingStyle.fill;

  CustomPathParticleRenderer({required this.path});

  @override
  void render(Canvas canvas, Particle particle) {
    _paint.color = particle.currentColor;
    final size = particle.currentSize;

    canvas.save();
    canvas.translate(particle.position.dx, particle.position.dy);
    canvas.rotate(particle.rotation);
    canvas.scale(size, size);
    canvas.drawPath(path, _paint);
    canvas.restore();
  }
}

/// Renders each particle as a text glyph (e.g. an emoji).
///
/// The [TextPainter] is created once and reused; only the color changes per
/// particle.  The widget is rendered centered at [Particle.position] with
/// opacity mapped from [Particle.currentColor.alpha].
class TextParticleRenderer extends ParticleRenderer {
  /// The glyph or emoji to display.
  final String glyph;

  /// Optional base style; font size is scaled by [Particle.currentSize].
  final TextStyle baseStyle;

  TextParticleRenderer({
    required this.glyph,
    this.baseStyle = const TextStyle(fontSize: 16.0),
  });

  final Paint _layerPaint = Paint();

  @override
  void render(Canvas canvas, Particle particle) {
    final color = particle.currentColor;
    final size = particle.currentSize;

    final textPainter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: baseStyle.copyWith(fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _layerPaint.color = color;

    canvas.save();
    canvas.translate(
      particle.position.dx - textPainter.width / 2,
      particle.position.dy - textPainter.height / 2,
    );
    canvas.rotate(particle.rotation);
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Backward-compat enum + extension
// ═══════════════════════════════════════════════════════════════════════════════

/// Shape enum — kept for backward compatibility.
///
/// Prefer constructing a [ParticleRenderer] subclass directly.
///
/// Note: [ParticleEmitter.shape] is deprecated; use [ParticleEmitter.renderer]
/// instead.
enum ParticleShape { circle, square, triangle, star }

/// Converts a [ParticleShape] enum value to the corresponding [ParticleRenderer].
extension ParticleShapeRenderer on ParticleShape {
  /// Returns a new [ParticleRenderer] instance for this shape.
  ParticleRenderer toRenderer() {
    switch (this) {
      case ParticleShape.circle:
        return CircleParticleRenderer();
      case ParticleShape.square:
        return SquareParticleRenderer();
      case ParticleShape.triangle:
        return TriangleParticleRenderer();
      case ParticleShape.star:
        return StarParticleRenderer();
    }
  }
}
