/// Text with tags in it: `Press [b]Space[/b] for [color=#ffcc00]coins[/color]`.
///
/// One parse, two readers — the canvas painter draws the spans itself, and
/// the Flutter layer turns them into a `TextSpan` — so world text and screen
/// text always say the same thing.
library;

import 'package:flutter/painting.dart';

import 'ui_text_style.dart';

/// What a span does beyond sitting still.
enum UiTextEffect {
  none,

  /// Rides up and down.
  wave,

  /// Jitters in place.
  shake,

  /// Cycles through hues.
  rainbow,

  /// Fades in and out.
  pulse;

  bool get movesGlyphs => this == wave || this == shake;
}

/// A run of text that shares a look.
class UiTextSpan {
  const UiTextSpan({
    required this.text,
    this.style = const UiTextStyle(),
    this.effect = UiTextEffect.none,
    this.icon,
    this.link,
  });

  /// The characters. Empty for an icon.
  final String text;

  /// What this run says about itself; anything it leaves out comes from the
  /// paragraph's style.
  final UiTextStyle style;

  final UiTextEffect effect;

  /// An image drawn in the line instead of text — `[icon=coin]`. The name is
  /// resolved by whoever draws it.
  final String? icon;

  /// An action name this run runs when it is clicked — `[link=shop]`.
  final String? link;

  bool get isIcon => icon != null;

  /// How many characters this span counts for when text is revealed a
  /// letter at a time. An icon is one.
  int get length => isIcon ? 1 : text.length;

  UiTextSpan copyWith({String? text, UiTextStyle? style}) => UiTextSpan(
    text: text ?? this.text,
    style: style ?? this.style,
    effect: effect,
    icon: icon,
    link: link,
  );

  @override
  String toString() =>
      isIcon ? 'UiTextSpan(icon: $icon)' : 'UiTextSpan("$text")';
}

/// A parsed piece of rich text.
class UiRichText {
  const UiRichText(this.spans, {this.plain = ''});

  static const UiRichText empty = UiRichText([]);

  final List<UiTextSpan> spans;

  /// The text with every tag taken out — what a reader hears, what a
  /// character count counts, and what a plain `Text` shows.
  final String plain;

  bool get isEmpty => spans.isEmpty;

  /// Whether anything here needs painting by hand rather than by Flutter:
  /// a moving effect, a gradient or an outline.
  bool get needsPainter => spans.any(
    (s) =>
        s.effect != UiTextEffect.none ||
        s.style.gradient != null ||
        (s.style.outline?.isVisible ?? false),
  );

  /// How many characters there are in all, icons counting as one.
  int get length {
    var total = 0;
    for (final s in spans) {
      total += s.length;
    }
    return total;
  }

  /// The first [count] characters of this text, spans and all — what a
  /// typewriter shows part-way through.
  UiRichText take(int count) {
    if (count >= length) return this;
    if (count <= 0) return empty;
    final out = <UiTextSpan>[];
    var left = count;
    for (final span in spans) {
      if (left <= 0) break;
      if (span.length <= left) {
        out.add(span);
        left -= span.length;
      } else {
        out.add(span.copyWith(text: span.text.substring(0, left)));
        left = 0;
      }
    }
    return UiRichText(
      out,
      plain: plain.substring(0, count.clamp(0, plain.length)),
    );
  }

  /// A `TextSpan` for the Flutter layer. [base] is the style underneath,
  /// and [iconBuilder] turns an `[icon=…]` into something in the line.
  InlineSpan toTextSpan(
    UiTextStyle base, {
    InlineSpan Function(String name, UiTextStyle style)? iconBuilder,
  }) => TextSpan(
    children: [
      for (final span in spans)
        if (span.isIcon)
          iconBuilder?.call(span.icon!, span.style.over(base)) ??
              const TextSpan(text: '')
        else
          TextSpan(text: span.text, style: span.style.over(base).toTextStyle()),
    ],
  );

  /// Reads [source] and its tags.
  ///
  /// Unknown or unclosed tags are left as they were written rather than
  /// swallowed: an author sees their mistake on screen instead of watching
  /// text disappear. A `[` that starts nothing is just a bracket.
  factory UiRichText.parse(String source) {
    if (source.isEmpty) return empty;
    if (!source.contains('[')) {
      return UiRichText([UiTextSpan(text: source)], plain: source);
    }

    final spans = <UiTextSpan>[];
    final plain = StringBuffer();
    final buffer = StringBuffer();
    // What the tags we are inside say, innermost last.
    final stack = <_Tag>[];

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        UiTextSpan(
          text: buffer.toString(),
          style: _styleOf(stack),
          effect: _effectOf(stack),
          link: _linkOf(stack),
        ),
      );
      buffer.clear();
    }

    var i = 0;
    while (i < source.length) {
      final char = source[i];
      if (char != '[') {
        buffer.write(char);
        plain.write(char);
        i++;
        continue;
      }
      final close = source.indexOf(']', i);
      if (close < 0) {
        // No closing bracket at all: the rest is text.
        buffer.write(source.substring(i));
        plain.write(source.substring(i));
        break;
      }
      final body = source.substring(i + 1, close);
      final tag = _Tag.parse(body);
      if (tag == null) {
        // Not a tag we know: show it as written.
        buffer.write(source.substring(i, close + 1));
        plain.write(source.substring(i, close + 1));
        i = close + 1;
        continue;
      }
      if (tag.isClosing) {
        // Close the innermost tag of that name. One that closes nothing is
        // a mistake, and is shown as written rather than swallowed.
        final at = stack.lastIndexWhere((t) => t.name == tag.name);
        if (at < 0) {
          buffer.write(source.substring(i, close + 1));
          plain.write(source.substring(i, close + 1));
          i = close + 1;
          continue;
        }
        flush();
        stack.removeAt(at);
        i = close + 1;
        continue;
      }
      flush();
      if (tag.name == 'icon') {
        spans.add(
          UiTextSpan(
            text: '',
            icon: tag.value ?? '',
            style: _styleOf(stack),
            effect: _effectOf(stack),
            link: _linkOf(stack),
          ),
        );
        plain.write('\u{fffc}'); // the object-replacement character
      } else if (tag.isSelfClosing) {
        // A tag that opens and shuts itself, like [br].
        if (tag.name == 'br') {
          buffer.write('\n');
          plain.write('\n');
        }
      } else {
        stack.add(tag);
      }
      i = close + 1;
    }
    flush();
    return UiRichText(spans, plain: plain.toString());
  }

  static UiTextStyle _styleOf(List<_Tag> stack) {
    var style = const UiTextStyle();
    for (final tag in stack) {
      final own = tag.style;
      if (own != null) style = own.over(style);
    }
    return style;
  }

  static UiTextEffect _effectOf(List<_Tag> stack) {
    for (var i = stack.length - 1; i >= 0; i--) {
      final effect = stack[i].effect;
      if (effect != null) return effect;
    }
    return UiTextEffect.none;
  }

  static String? _linkOf(List<_Tag> stack) {
    for (var i = stack.length - 1; i >= 0; i--) {
      if (stack[i].name == 'link') return stack[i].value ?? '';
    }
    return null;
  }

  /// The tags that may be written, for an editor to offer.
  static const List<String> tagNames = [
    'b',
    'i',
    'color',
    'size',
    'font',
    'icon',
    'wave',
    'shake',
    'rainbow',
    'pulse',
    'link',
    'br',
  ];

  @override
  String toString() => 'UiRichText("$plain", ${spans.length} spans)';
}

/// One `[tag]`, `[tag=value]` or `[/tag]`.
class _Tag {
  const _Tag(this.name, this.value, {this.isClosing = false});

  final String name;
  final String? value;
  final bool isClosing;

  bool get isSelfClosing => name == 'br';

  static const Set<String> _known = {
    'b',
    'i',
    'color',
    'size',
    'font',
    'icon',
    'wave',
    'shake',
    'rainbow',
    'pulse',
    'link',
    'br',
  };

  /// [body] is what is between the brackets; null when it is not a tag.
  static _Tag? parse(String body) {
    if (body.isEmpty) return null;
    final closing = body.startsWith('/');
    final rest = closing ? body.substring(1) : body;
    final equals = rest.indexOf('=');
    final name = (equals < 0 ? rest : rest.substring(0, equals))
        .trim()
        .toLowerCase();
    if (!_known.contains(name)) return null;
    final value = equals < 0 ? null : rest.substring(equals + 1).trim();
    // A closing tag carries nothing, and an icon must say which.
    if (closing && value != null) return null;
    if (!closing && (name == 'icon' || name == 'color') && value == null) {
      return null;
    }
    return _Tag(name, value, isClosing: closing);
  }

  /// What this tag says about how its text looks.
  UiTextStyle? get style => switch (name) {
    'b' => const UiTextStyle(weight: FontWeight.w700),
    'i' => const UiTextStyle(italic: true),
    'color' => UiTextStyle(color: parseColor(value)),
    'size' => UiTextStyle(size: double.tryParse(value ?? '')),
    'font' => UiTextStyle(family: value),
    _ => null,
  };

  UiTextEffect? get effect => switch (name) {
    'wave' => UiTextEffect.wave,
    'shake' => UiTextEffect.shake,
    'rainbow' => UiTextEffect.rainbow,
    'pulse' => UiTextEffect.pulse,
    _ => null,
  };

  /// `#rgb`, `#rrggbb`, `#aarrggbb`, or one of a few names. Null when it
  /// makes no sense, which leaves the colour as it was.
  static Color? parseColor(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final named = _names[raw.toLowerCase()];
    if (named != null) return named;
    var hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  static const Map<String, Color> _names = {
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF000000),
    'red': Color(0xFFE53935),
    'green': Color(0xFF43A047),
    'blue': Color(0xFF1E88E5),
    'yellow': Color(0xFFFDD835),
    'orange': Color(0xFFFB8C00),
    'purple': Color(0xFF8E24AA),
    'grey': Color(0xFF9E9E9E),
    'gray': Color(0xFF9E9E9E),
  };
}
