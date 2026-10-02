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
  /// Const constructor so subclasses can be const.
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
    canvas.drawCircle(Offset(particle.x, particle.y), radius, _paint);
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
        Rect.fromLTRB(
          particle.x - half,
          particle.y - half,
          particle.x + half,
          particle.y + half,
        ),
        _paint,
      );
    } else {
      // Rotate around particle center
      canvas.save();
      canvas.translate(particle.x, particle.y);
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
    canvas.translate(particle.x, particle.y);
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
    canvas.translate(particle.x, particle.y);
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
/// [Canvas.drawRawAtlas] produces a single draw call for the entire batch,
/// significantly reducing driver overhead when many particles share the same
/// image (sprite atlas or simple texture).
///
/// The transforms, source rects and colours are written into typed buffers
/// sized for [maxParticles] once, and handed to the canvas as views — no
/// per-particle objects and no copies inside [renderBatch].
class SpriteParticleRenderer extends ParticleRenderer {
  /// The image used as the particle sprite.
  final ui.Image image;

  /// The source rectangle within [image] (defaults to the full image).
  final Rect? sourceRect;

  /// Maximum particles to pre-allocate buffer space for.
  final int maxParticles;

  late final Float32List _transforms;
  late final Float32List _rects;
  late final Int32List _colors;
  late final Rect _srcRect;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Draws each particle as [sourceRect] of [image] (all of it when null),
  /// scaled so the rect's width is the particle's size and tinted by its
  /// colour. One batch draws at most [maxParticles] (1000 by default);
  /// any beyond are skipped. The buffers are allocated here, once.
  SpriteParticleRenderer({
    required this.image,
    this.sourceRect,
    this.maxParticles = 1000,
  }) {
    _srcRect =
        sourceRect ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final slots = math.max(maxParticles, 1);
    _transforms = Float32List(4 * slots);
    _rects = Float32List(4 * slots);
    _colors = Int32List(slots);
    // Every particle shows the same part of the image.
    for (var i = 0; i < slots; i++) {
      _rects
        ..[4 * i] = _srcRect.left
        ..[4 * i + 1] = _srcRect.top
        ..[4 * i + 2] = _srcRect.right
        ..[4 * i + 3] = _srcRect.bottom;
    }
  }

  @override
  void render(Canvas canvas, Particle particle) {
    // Fallback for single particle (e.g. from base renderBatch default)
    _write(0, particle, _srcRect.width.clamp(1.0, double.infinity));
    _draw(canvas, 1);
  }

  @override
  void renderBatch(Canvas canvas, List<Particle> particles) {
    if (particles.isEmpty) return;
    final count = math.min(particles.length, maxParticles);
    final width = _srcRect.width > 0 ? _srcRect.width : 0.0;
    for (int i = 0; i < count; i++) {
      _write(i, particles[i], width);
    }
    _draw(canvas, count);
  }

  /// Writes [p]'s transform and colour into slot [i]; its size is scaled
  /// from a source [width] (0: drawn at the image's own size).
  void _write(int i, Particle p, double width) {
    final scale = width > 0 ? p.currentSize / width : 1.0;
    // RSTransform.fromComponents, anchored at the source rect's centre.
    final scos = math.cos(p.rotation) * scale;
    final ssin = math.sin(p.rotation) * scale;
    final ax = _srcRect.width / 2.0, ay = _srcRect.height / 2.0;
    _transforms
      ..[4 * i] = scos
      ..[4 * i + 1] = ssin
      ..[4 * i + 2] = p.x + -scos * ax + ssin * ay
      ..[4 * i + 3] = p.y + -ssin * ax - scos * ay;
    _colors[i] = p.currentColorArgb;
  }

  void _draw(Canvas canvas, int count) {
    canvas.drawRawAtlas(
      image,
      Float32List.sublistView(_transforms, 0, 4 * count),
      Float32List.sublistView(_rects, 0, 4 * count),
      Int32List.sublistView(_colors, 0, count),
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

  /// Draws each particle as one of [frames] (at least one, asserted) of
  /// [sheet], stepping through them evenly over its lifetime, in a square
  /// as wide as the particle's size, tinted by its colour.
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
    canvas.translate(particle.x, particle.y);
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

  /// Streaks [strokeWidth] wide (2 by default) while a particle is at its
  /// start size, thinner or thicker in proportion as its size changes.
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
  /// The path to draw (normalized to roughly `[-0.5, 0.5]` bounds).
  final Path path;

  final Paint _paint = Paint()..style = PaintingStyle.fill;

  /// Fills [path] in each particle's colour, scaled by its size and turned
  /// by its rotation.
  CustomPathParticleRenderer({required this.path});

  @override
  void render(Canvas canvas, Particle particle) {
    _paint.color = particle.currentColor;
    final size = particle.currentSize;

    canvas.save();
    canvas.translate(particle.x, particle.y);
    canvas.rotate(particle.rotation);
    canvas.scale(size, size);
    canvas.drawPath(path, _paint);
    canvas.restore();
  }
}

/// Renders each particle as a text glyph (e.g. an emoji).
///
/// The glyph is laid out and drawn into an image once — in white, at
/// [referenceSize] — and every particle is that image, scaled to
/// [Particle.currentSize] and turned about its centre, in one
/// [Canvas.drawRawAtlas] call. (It used to lay the text out again for every
/// particle, every frame, and never released the painters.)
///
/// The particle's colour reaches the glyph through [colorBlendMode]. With
/// the default, [BlendMode.modulate], the white glyph is multiplied by the
/// colour: plain text takes the colour, as before, and a colour emoji is
/// tinted by it — keep white start and end colours to show an emoji as
/// drawn, or use [BlendMode.dstIn], which keeps the glyph's own colours and
/// takes only the particle's opacity.
///
/// Call [dispose] when done with the renderer to release the image.
class TextParticleRenderer extends ParticleRenderer {
  /// The glyph or emoji to display.
  final String glyph;

  /// Optional base style; font size is scaled by [Particle.currentSize].
  final TextStyle baseStyle;

  /// How a particle's colour combines with the glyph; see the class notes.
  final BlendMode colorBlendMode;

  /// The font size the glyph is drawn at, once. A particle larger than this
  /// is the glyph scaled up, and softer for it: set it to about the largest
  /// size the particles reach.
  final double referenceSize;

  /// Draws [glyph] in [baseStyle] (its font size replaced by
  /// [referenceSize], 64 by default), coloured through [colorBlendMode]
  /// (modulate by default). The glyph's image is made on the first draw.
  TextParticleRenderer({
    required this.glyph,
    this.baseStyle = const TextStyle(fontSize: 16.0),
    this.colorBlendMode = BlendMode.modulate,
    this.referenceSize = 64.0,
  });

  ui.Image? _image;
  double _width = 0, _height = 0;
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);
  Int32List _colors = Int32List(0);
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Draws the glyph into [_image], once.
  ui.Image _glyph() {
    final existing = _image;
    if (existing != null) return existing;
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: baseStyle.copyWith(
          fontSize: referenceSize,
          color: const Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _width = math.max(painter.width, 1.0);
    _height = math.max(painter.height, 1.0);
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    painter.dispose();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(_width.ceil(), _height.ceil());
    picture.dispose();
    return _image = image;
  }

  void _reserve(int count) {
    if (_colors.length >= count) return;
    final slots = math.max(count, _colors.length * 2);
    _transforms = Float32List(4 * slots);
    _rects = Float32List(4 * slots);
    _colors = Int32List(slots);
  }

  @override
  void render(Canvas canvas, Particle particle) {
    final image = _glyph();
    _reserve(1);
    _write(0, particle);
    _draw(canvas, image, 1);
  }

  @override
  void renderBatch(Canvas canvas, List<Particle> particles) {
    if (particles.isEmpty) return;
    final image = _glyph();
    _reserve(particles.length);
    for (var i = 0; i < particles.length; i++) {
      _write(i, particles[i]);
    }
    _draw(canvas, image, particles.length);
  }

  void _write(int i, Particle p) {
    final scale = p.currentSize / referenceSize;
    final scos = math.cos(p.rotation) * scale;
    final ssin = math.sin(p.rotation) * scale;
    final ax = _width / 2, ay = _height / 2;
    _transforms
      ..[4 * i] = scos
      ..[4 * i + 1] = ssin
      ..[4 * i + 2] = p.x - scos * ax + ssin * ay
      ..[4 * i + 3] = p.y - ssin * ax - scos * ay;
    _rects
      ..[4 * i] = 0
      ..[4 * i + 1] = 0
      ..[4 * i + 2] = _width
      ..[4 * i + 3] = _height;
    _colors[i] = p.currentColorArgb;
  }

  void _draw(Canvas canvas, ui.Image image, int count) {
    canvas.drawRawAtlas(
      image,
      Float32List.sublistView(_transforms, 0, 4 * count),
      Float32List.sublistView(_rects, 0, 4 * count),
      Int32List.sublistView(_colors, 0, count),
      colorBlendMode,
      null,
      _paint,
    );
  }

  /// Releases the glyph image. The renderer draws it again if used after.
  void dispose() {
    _image?.dispose();
    _image = null;
  }
}
