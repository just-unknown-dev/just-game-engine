/// How text looks, in a form that survives a save.
///
/// Flutter's own `TextStyle` cannot be written to a file, and the engine's
/// text used to keep one in memory and lose everything but the string when
/// the scene was saved. This holds the same choices as plain data.
library;

import 'package:flutter/painting.dart';

/// A line drawn around every glyph, so text reads over a busy background.
class UiTextOutline {
  const UiTextOutline({this.color = const Color(0xFF000000), this.width = 2});

  static const UiTextOutline none = UiTextOutline(width: 0);

  final Color color;
  final double width;

  bool get isVisible => width > 0 && color.a > 0;

  UiTextOutline copyWith({Color? color, double? width}) =>
      UiTextOutline(color: color ?? this.color, width: width ?? this.width);

  Map<String, dynamic> toJson() => {'color': color.toARGB32(), 'width': width};

  factory UiTextOutline.fromJson(Map<String, dynamic> json) => UiTextOutline(
    color: Color((json['color'] as num?)?.toInt() ?? 0xFF000000),
    width: (json['width'] as num?)?.toDouble() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is UiTextOutline && other.color == color && other.width == width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// A shadow cast by the text.
class UiTextShadow {
  const UiTextShadow({
    this.color = const Color(0xA6000000),
    this.offset = const Offset(1, 2),
    this.blur = 2,
  });

  static const UiTextShadow none = UiTextShadow(
    color: Color(0x00000000),
    offset: Offset.zero,
    blur: 0,
  );

  final Color color;
  final Offset offset;
  final double blur;

  bool get isVisible => color.a > 0 && (blur > 0 || offset != Offset.zero);

  Shadow toShadow() => Shadow(color: color, offset: offset, blurRadius: blur);

  UiTextShadow copyWith({Color? color, Offset? offset, double? blur}) =>
      UiTextShadow(
        color: color ?? this.color,
        offset: offset ?? this.offset,
        blur: blur ?? this.blur,
      );

  Map<String, dynamic> toJson() => {
    'color': color.toARGB32(),
    'dx': offset.dx,
    'dy': offset.dy,
    'blur': blur,
  };

  factory UiTextShadow.fromJson(Map<String, dynamic> json) => UiTextShadow(
    color: Color((json['color'] as num?)?.toInt() ?? 0),
    offset: Offset(
      (json['dx'] as num?)?.toDouble() ?? 0,
      (json['dy'] as num?)?.toDouble() ?? 0,
    ),
    blur: (json['blur'] as num?)?.toDouble() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is UiTextShadow &&
      other.color == color &&
      other.offset == offset &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(color, offset, blur);
}

/// Everything about how a piece of text is drawn.
///
/// Every field may be left unset, in which case what a theme (or a parent
/// span) says is used — which is how one style is layered over another
/// without a null check per field at the call site.
class UiTextStyle {
  const UiTextStyle({
    this.family,
    this.size,
    this.weight,
    this.italic,
    this.color,
    this.gradient,
    this.letterSpacing,
    this.lineHeight,
    this.outline,
    this.shadow,
  });

  /// What text falls back to when nothing says otherwise.
  static const UiTextStyle fallback = UiTextStyle(
    size: 16,
    weight: FontWeight.w400,
    italic: false,
    color: Color(0xFFFFFFFF),
  );

  /// A font family loaded through `UiFonts`, or one from the pubspec. Null
  /// takes the theme's.
  final String? family;
  final double? size;
  final FontWeight? weight;
  final bool? italic;
  final Color? color;

  /// Colours swept across the text instead of a flat [color]; two or more.
  final List<Color>? gradient;

  final double? letterSpacing;

  /// A multiple of the font size, as Flutter's `height` is.
  final double? lineHeight;

  final UiTextOutline? outline;
  final UiTextShadow? shadow;

  bool get isEmpty =>
      family == null &&
      size == null &&
      weight == null &&
      italic == null &&
      color == null &&
      gradient == null &&
      letterSpacing == null &&
      lineHeight == null &&
      outline == null &&
      shadow == null;

  /// This style over [base]: what this one says wins, and what it leaves
  /// unset comes from underneath. A span's style over its paragraph's, a
  /// component's over its theme's.
  UiTextStyle over(UiTextStyle base) => UiTextStyle(
    family: family ?? base.family,
    size: size ?? base.size,
    weight: weight ?? base.weight,
    italic: italic ?? base.italic,
    color: color ?? base.color,
    gradient: gradient ?? base.gradient,
    letterSpacing: letterSpacing ?? base.letterSpacing,
    lineHeight: lineHeight ?? base.lineHeight,
    outline: outline ?? base.outline,
    shadow: shadow ?? base.shadow,
  );

  UiTextStyle copyWith({
    String? family,
    double? size,
    FontWeight? weight,
    bool? italic,
    Color? color,
    List<Color>? gradient,
    double? letterSpacing,
    double? lineHeight,
    UiTextOutline? outline,
    UiTextShadow? shadow,
  }) => UiTextStyle(
    family: family ?? this.family,
    size: size ?? this.size,
    weight: weight ?? this.weight,
    italic: italic ?? this.italic,
    color: color ?? this.color,
    gradient: gradient ?? this.gradient,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    lineHeight: lineHeight ?? this.lineHeight,
    outline: outline ?? this.outline,
    shadow: shadow ?? this.shadow,
  );

  /// The same style with [field] cleared, so it falls back again.
  UiTextStyle without(String field) => UiTextStyle(
    family: field == 'family' ? null : family,
    size: field == 'size' ? null : size,
    weight: field == 'weight' ? null : weight,
    italic: field == 'italic' ? null : italic,
    color: field == 'color' ? null : color,
    gradient: field == 'gradient' ? null : gradient,
    letterSpacing: field == 'letterSpacing' ? null : letterSpacing,
    lineHeight: field == 'lineHeight' ? null : lineHeight,
    outline: field == 'outline' ? null : outline,
    shadow: field == 'shadow' ? null : shadow,
  );

  /// What Flutter draws with.
  ///
  /// A gradient is not a `TextStyle` — the painter reads [gradient] and
  /// shades the glyphs itself — so the colour here is the first of the
  /// gradient's, which is what shows if anything ignores it.
  TextStyle toTextStyle() {
    final resolved = over(fallback);
    return TextStyle(
      fontFamily: resolved.family,
      fontSize: resolved.size,
      fontWeight: resolved.weight,
      fontStyle: (resolved.italic ?? false)
          ? FontStyle.italic
          : FontStyle.normal,
      color: resolved.gradient?.isNotEmpty ?? false
          ? resolved.gradient!.first
          : resolved.color,
      letterSpacing: resolved.letterSpacing,
      height: resolved.lineHeight,
      shadows: [
        if (resolved.shadow?.isVisible ?? false) resolved.shadow!.toShadow(),
      ],
    );
  }

  /// The size text is drawn at once everything has had its say.
  double get effectiveSize => size ?? fallback.size!;

  /// Only what was set: a style that says nothing is `{}`, and a file never
  /// carries a field nobody chose.
  Map<String, dynamic> toJson() => {
    if (family != null) 'family': family,
    if (size != null) 'size': size,
    if (weight != null) 'weight': weight!.value,
    if (italic != null) 'italic': italic,
    if (color != null) 'color': color!.toARGB32(),
    if (gradient != null) 'gradient': [for (final c in gradient!) c.toARGB32()],
    if (letterSpacing != null) 'letterSpacing': letterSpacing,
    if (lineHeight != null) 'lineHeight': lineHeight,
    if (outline != null) 'outline': outline!.toJson(),
    if (shadow != null) 'shadow': shadow!.toJson(),
  };

  factory UiTextStyle.fromJson(Map<String, dynamic> json) => UiTextStyle(
    family: json['family'] as String?,
    size: (json['size'] as num?)?.toDouble(),
    weight: json['weight'] == null
        ? null
        : _weightOf((json['weight'] as num).toInt()),
    italic: json['italic'] as bool?,
    color: json['color'] == null ? null : Color((json['color'] as num).toInt()),
    gradient: json['gradient'] is List
        ? [
            for (final c in json['gradient'] as List)
              if (c is num) Color(c.toInt()),
          ]
        : null,
    letterSpacing: (json['letterSpacing'] as num?)?.toDouble(),
    lineHeight: (json['lineHeight'] as num?)?.toDouble(),
    outline: json['outline'] is Map
        ? UiTextOutline.fromJson(
            (json['outline'] as Map).cast<String, dynamic>(),
          )
        : null,
    shadow: json['shadow'] is Map
        ? UiTextShadow.fromJson((json['shadow'] as Map).cast<String, dynamic>())
        : null,
  );

  /// The nearest of Flutter's nine weights to [value].
  static FontWeight _weightOf(int value) {
    final steps = FontWeight.values;
    var best = steps.first;
    for (final w in steps) {
      if ((w.value - value).abs() < (best.value - value).abs()) best = w;
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is UiTextStyle &&
      other.family == family &&
      other.size == size &&
      other.weight == weight &&
      other.italic == italic &&
      other.color == color &&
      _sameColors(other.gradient, gradient) &&
      other.letterSpacing == letterSpacing &&
      other.lineHeight == lineHeight &&
      other.outline == outline &&
      other.shadow == shadow;

  static bool _sameColors(List<Color>? a, List<Color>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    family,
    size,
    weight,
    italic,
    color,
    gradient == null ? null : Object.hashAll(gradient!),
    letterSpacing,
    lineHeight,
    outline,
    shadow,
  );

  @override
  String toString() => 'UiTextStyle(${toJson()})';
}

/// Where text sits in the box it is given.
enum UiTextAlign {
  left,
  center,
  right,
  justify;

  TextAlign get flutter => switch (this) {
    left => TextAlign.left,
    center => TextAlign.center,
    right => TextAlign.right,
    justify => TextAlign.justify,
  };
}

/// What happens when text does not fit its box.
enum UiTextOverflow {
  /// Spills out of it.
  visible,

  /// Cut at the edge.
  clip,

  /// Cut, with an ellipsis on the last line.
  ellipsis,

  /// The size is brought down until it fits.
  shrink;

  TextOverflow get flutter => switch (this) {
    visible => TextOverflow.visible,
    clip => TextOverflow.clip,
    ellipsis => TextOverflow.ellipsis,
    // Shrinking is the painter's doing; once it has, nothing overflows.
    shrink => TextOverflow.clip,
  };
}
