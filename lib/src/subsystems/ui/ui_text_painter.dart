/// Drawing text on the game's canvas: wrapping, fitting, outlines,
/// gradients, and letters that move.
///
/// Flutter's own `TextPainter` does the hard part — shaping and line
/// breaking — and this adds what a game wants on top of it. The screen-side
/// UI uses real widgets instead, except where an effect needs painting by
/// hand; both read the same [UiRichText], so they agree about what the text
/// says.
library;

import 'dart:math' as math;

// widgets.dart, not painting.dart, for the `characters` extension: a
// per-letter effect must step over emoji whole rather than splitting them.
import 'package:flutter/widgets.dart';

import 'ui_rich_text.dart';
import 'ui_text_style.dart';

/// How a piece of text is laid out, apart from how it looks.
class UiTextLayout {
  const UiTextLayout({
    this.align = UiTextAlign.center,
    this.overflow = UiTextOverflow.visible,
    this.maxWidth,
    this.maxHeight,
    this.maxLines,
    this.minSize = 8,
  });

  final UiTextAlign align;
  final UiTextOverflow overflow;

  /// Where text wraps. Null lets it run on.
  final double? maxWidth;

  /// What it must fit in vertically, for [UiTextOverflow.shrink].
  final double? maxHeight;

  final int? maxLines;

  /// How small shrinking may go before it gives up and lets text spill.
  final double minSize;

  UiTextLayout copyWith({
    UiTextAlign? align,
    UiTextOverflow? overflow,
    double? maxWidth,
    double? maxHeight,
    int? maxLines,
    double? minSize,
  }) => UiTextLayout(
    align: align ?? this.align,
    overflow: overflow ?? this.overflow,
    maxWidth: maxWidth ?? this.maxWidth,
    maxHeight: maxHeight ?? this.maxHeight,
    maxLines: maxLines ?? this.maxLines,
    minSize: minSize ?? this.minSize,
  );
}

/// What the moving effects need to know: how far into the game we are.
class UiTextAnimation {
  const UiTextAnimation({this.seconds = 0, this.amplitude = 3, this.speed = 1});

  static const UiTextAnimation still = UiTextAnimation();

  final double seconds;

  /// How far a wave rides, in pixels.
  final double amplitude;

  /// A multiple of the usual rate.
  final double speed;
}

/// Lays out and draws rich text on a canvas.
///
/// Made once and reused: laying text out is the expensive part, and this
/// only redoes it when something it was given actually changed.
class UiTextPainter {
  UiTextPainter();

  final TextPainter _painter = TextPainter(textDirection: TextDirection.ltr);

  UiRichText _text = UiRichText.empty;
  UiTextStyle _style = const UiTextStyle();
  UiTextLayout _layout = const UiTextLayout();
  double _fittedSize = 0;
  bool _dirty = true;

  /// The size the text came out at once it had been fitted — what an
  /// inspector shows when auto-fit is on.
  double get fittedSize => _fittedSize;

  Size get size => _painter.size;

  /// Where the text will be drawn, relative to the point it is drawn at
  /// (which is its centre).
  Rect get bounds => Rect.fromCenter(
    center: Offset.zero,
    width: _painter.width,
    height: _painter.height,
  );

  /// What to draw and how. Nothing is laid out until [layout].
  void set({
    required UiRichText text,
    required UiTextStyle style,
    UiTextLayout layout = const UiTextLayout(),
  }) {
    if (_sameText(text, _text) && style == _style && _sameLayout(layout)) {
      return;
    }
    _text = text;
    _style = style;
    _layout = layout;
    _dirty = true;
  }

  bool _sameLayout(UiTextLayout other) =>
      other.align == _layout.align &&
      other.overflow == _layout.overflow &&
      other.maxWidth == _layout.maxWidth &&
      other.maxHeight == _layout.maxHeight &&
      other.maxLines == _layout.maxLines &&
      other.minSize == _layout.minSize;

  static bool _sameText(UiRichText a, UiRichText b) =>
      identical(a, b) ||
      (a.plain == b.plain && a.spans.length == b.spans.length);

  /// Measures the text, shrinking it if that is what was asked for.
  void layout() {
    if (!_dirty) return;
    _dirty = false;
    final wanted = _style.effectiveSize;
    _fittedSize = wanted;

    if (_layout.overflow != UiTextOverflow.shrink) {
      _layoutAt(wanted);
      return;
    }

    // Come down a point at a time until it fits. A binary search would do
    // fewer layouts, but text jumps a whole line at a time as it shrinks,
    // so stepping is what actually lands on the largest size that fits.
    for (var size = wanted; size >= _layout.minSize; size -= 1) {
      _layoutAt(size);
      if (_fits) {
        _fittedSize = size;
        return;
      }
    }
    _fittedSize = _layout.minSize;
    _layoutAt(_layout.minSize);
  }

  bool get _fits {
    final height = _layout.maxHeight;
    if (height != null && _painter.height > height + 0.5) return false;
    if (_painter.didExceedMaxLines) return false;
    final width = _layout.maxWidth;
    // A single word longer than its box cannot be broken, and would
    // otherwise shrink forever.
    if (width != null && _painter.width > width + 0.5) return false;
    return true;
  }

  void _layoutAt(double size) {
    _painter
      ..text = _text.toTextSpan(_style.copyWith(size: size))
      ..textAlign = _layout.align.flutter
      ..maxLines = _layout.maxLines
      ..ellipsis = _layout.overflow == UiTextOverflow.ellipsis ? '…' : null
      ..layout(maxWidth: _layout.maxWidth ?? double.infinity);
  }

  /// Draws the text centred on [at].
  ///
  /// [animation] moves what moves; leave it still and the text sits.
  void paint(
    Canvas canvas,
    Offset at, {
    UiTextAnimation animation = UiTextAnimation.still,
  }) {
    layout();
    final origin = at - Offset(_painter.width / 2, _painter.height / 2);
    final resolved = _style.over(UiTextStyle.fallback);

    if (_text.spans.any((s) => s.effect.movesGlyphs)) {
      _paintMoving(canvas, origin, animation, resolved);
      return;
    }

    final outline = resolved.outline;
    if (outline != null && outline.isVisible) {
      _paintOutline(canvas, origin, outline);
    }
    final gradient = resolved.gradient;
    if (gradient != null && gradient.length > 1) {
      _paintGradient(canvas, origin, gradient);
      return;
    }
    _painter.paint(canvas, origin);
  }

  /// The outline: the same glyphs drawn as a thick stroke underneath.
  void _paintOutline(Canvas canvas, Offset origin, UiTextOutline outline) {
    final foreground = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outline.width
      ..strokeJoin = StrokeJoin.round
      ..color = outline.color;
    final stroked = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: _layout.align.flutter,
      maxLines: _layout.maxLines,
      ellipsis: _painter.ellipsis,
      text: _text.toTextSpan(
        _style
            .copyWith(size: _fittedSize)
            .copyWith()
            .over(UiTextStyle.fallback),
      ),
    );
    // The stroke rides on the same spans, with the paint swapped in.
    stroked
      ..text = _strokeSpan(foreground)
      ..layout(maxWidth: _layout.maxWidth ?? double.infinity)
      ..paint(canvas, origin);
  }

  InlineSpan _strokeSpan(Paint foreground) {
    final base = _style.copyWith(size: _fittedSize);
    return TextSpan(
      children: [
        for (final span in _text.spans)
          TextSpan(
            text: span.isIcon ? ' ' : span.text,
            style: span.style
                .over(base)
                .toTextStyle()
                .copyWith(foreground: foreground, shadows: const []),
          ),
      ],
    );
  }

  /// Colours swept across the whole block of text.
  void _paintGradient(Canvas canvas, Offset origin, List<Color> colors) {
    final rect = origin & _painter.size;
    canvas.saveLayer(rect, Paint());
    _painter.paint(canvas, origin);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    canvas.restore();
  }

  /// Text whose letters move: each is laid out and drawn on its own, which
  /// is why this is kept for the spans that ask for it.
  void _paintMoving(
    Canvas canvas,
    Offset origin,
    UiTextAnimation animation,
    UiTextStyle resolved,
  ) {
    final base = _style.copyWith(size: _fittedSize);
    var index = 0;
    var x = origin.dx;
    final glyph = TextPainter(textDirection: TextDirection.ltr);

    for (final span in _text.spans) {
      final style = span.style.over(base);
      for (final char in span.text.characters) {
        glyph
          ..text = TextSpan(text: char, style: style.toTextStyle())
          ..layout();
        final offset = _offsetFor(span.effect, index, animation);
        final color = _colorFor(span.effect, index, animation, style);
        if (color != null) {
          glyph
            ..text = TextSpan(
              text: char,
              style: style.copyWith(color: color).toTextStyle(),
            )
            ..layout();
        }
        glyph.paint(canvas, Offset(x, origin.dy) + offset);
        x += glyph.width;
        index++;
      }
    }
  }

  Offset _offsetFor(UiTextEffect effect, int index, UiTextAnimation a) {
    final t = a.seconds * a.speed;
    return switch (effect) {
      UiTextEffect.wave => Offset(
        0,
        math.sin(t * 6 + index * 0.6) * a.amplitude,
      ),
      // Deterministic jitter: the same letter at the same moment always
      // lands in the same place, so a screenshot test can hold it still.
      UiTextEffect.shake => Offset(
        math.sin(t * 43 + index * 12.9) * a.amplitude * 0.4,
        math.cos(t * 37 + index * 7.3) * a.amplitude * 0.4,
      ),
      _ => Offset.zero,
    };
  }

  Color? _colorFor(
    UiTextEffect effect,
    int index,
    UiTextAnimation a,
    UiTextStyle style,
  ) {
    final t = a.seconds * a.speed;
    switch (effect) {
      case UiTextEffect.rainbow:
        return HSVColor.fromAHSV(
          1,
          (t * 120 + index * 40) % 360,
          0.85,
          1,
        ).toColor();
      case UiTextEffect.pulse:
        final base = style.color ?? const Color(0xFFFFFFFF);
        final alpha = 0.55 + 0.45 * math.sin(t * 4 + index * 0.2);
        return base.withValues(alpha: alpha.clamp(0.0, 1.0));
      default:
        return null;
    }
  }
}
