/// Text in the world, drawn on the game's canvas.
library;

import 'package:flutter/painting.dart';

import '../../../subsystems/ui/ui_bindings.dart';
import '../../../subsystems/ui/ui_rich_text.dart';
import '../../../subsystems/ui/ui_text_painter.dart';
import '../../../subsystems/ui/ui_text_style.dart';
import '../../../subsystems/ui/ui_theme.dart';
import '../../ecs.dart';
import 'ui_component.dart';

/// A piece of text at an entity's transform: a sign, a name over a head, a
/// number that floats up and fades.
///
/// What it says may be written out, read from the game (`"Coins: {coins}"`),
/// or looked up in the current language (`"@hud.coins"`) — and it may carry
/// tags: `"Press [b]Space[/b]"`.
class TextComponent extends UIComponent {
  TextComponent({
    required String text,
    UiTextStyle style = const UiTextStyle(),
    this.styleRole = 'body',
    this.align = UiTextAlign.center,
    this.overflow = UiTextOverflow.visible,
    this.wrap = false,
    this.maxLines,
    this.minFontSize = 8,
    this.revealSpeed = 0,
    super.size = const Size(200, 40),
    super.visible,
    super.enabled = false,
    super.layer,
  }) : _text = text,
       _style = style;

  String _text;
  UiTextStyle _style;

  /// What is written in the scene, tags and all.
  String get text => _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    _resolvedFrom = null;
    markDirty();
  }

  /// How it looks. Anything left unset comes from [styleRole] in the theme.
  UiTextStyle get style => _style;
  set style(UiTextStyle value) {
    if (value == _style) return;
    _style = value;
    markDirty();
  }

  /// The theme role underneath [style] — `body`, `title`, `caption`.
  String styleRole;

  UiTextAlign align;
  UiTextOverflow overflow;

  /// Whether text wraps at the component's width. Without it, text runs on
  /// as far as it likes and [size] is only what the editor draws.
  bool wrap;

  int? maxLines;

  /// How small [UiTextOverflow.shrink] may go.
  double minFontSize;

  /// Characters a second, for text that types itself out. Zero shows it all
  /// at once.
  double revealSpeed;

  // ── Runtime ──────────────────────────────────────────────────────────────

  /// How much of it has been revealed, in characters.
  double revealed = 0;

  /// Seconds this text has been on screen, for the moving effects.
  double elapsed = 0;

  /// The text with its bindings filled in and its tags parsed. Kept until
  /// something it was made from changes — laying text out is the expensive
  /// part of drawing it.
  UiRichText? _parsed;
  String? _resolvedFrom;
  int _revision = 0;

  /// Bumped whenever something that changes how this looks is set. The
  /// screen-side UI watches this to know when to rebuild one node.
  int get revision => _revision;

  void markDirty() {
    _revision++;
    _parsed = null;
  }

  /// Everything resolved: bindings filled in, language applied, tags read.
  ///
  /// [localise] turns `@a.key` into words; without it the key shows, which
  /// is what an editor wants to see.
  UiRichText resolve({Entity? self, String Function(String key)? localise}) {
    final source = _resolve(self: self, localise: localise);
    if (_parsed != null && _resolvedFrom == source) return _parsed!;
    _resolvedFrom = source;
    return _parsed = UiRichText.parse(source);
  }

  String _resolve({Entity? self, String Function(String key)? localise}) {
    var source = _text;
    if (source.startsWith('@') && source.length > 1) {
      final key = source.substring(1);
      source = localise?.call(key) ?? key;
    }
    return UiBindings.interpolate(source, self: self);
  }

  /// Whether this text is still typing itself out.
  bool get isRevealing =>
      revealSpeed > 0 && _parsed != null && revealed < _parsed!.length;

  /// Shows the whole of it at once.
  void revealAll() => revealed = double.maxFinite;

  /// Types it again from the start.
  void restartReveal() => revealed = 0;

  /// How this text is laid out, for a painter.
  UiTextLayout layoutFor() => UiTextLayout(
    align: align,
    overflow: overflow,
    maxWidth: wrap ? size.width : null,
    maxHeight: size.height,
    maxLines: maxLines,
    minSize: minFontSize,
  );

  /// The style to draw with, under [theme].
  UiTextStyle styleUnder(UiTheme theme) =>
      _style.over(theme.textStyle(styleRole));

  @override
  String toString() => 'Text("$_text")';
}
