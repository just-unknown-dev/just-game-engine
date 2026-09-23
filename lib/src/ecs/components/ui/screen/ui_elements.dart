/// The pieces a screen is built from: containers, panels, pictures and
/// controls.
///
/// Each maps onto a Flutter widget, so what the editor shows and what the
/// game runs are the same thing.
library;

import 'package:flutter/widgets.dart';

import '../../../../subsystems/ui/ui_actions.dart';
import '../../../../subsystems/ui/ui_theme.dart';
import '../../../ecs.dart';

/// A container, by what it does with its children.
enum UiLayoutKind {
  /// Left to right — Flutter's `Row`.
  row,

  /// Top to bottom — `Column`.
  column,

  /// Piled up, each placed by its own anchors — `Stack`.
  stack,

  /// In a line that wraps — `Wrap`.
  wrap,

  /// A grid of equal cells — `GridView`.
  grid,

  /// Scrolls when there is more than fits — `SingleChildScrollView`.
  scroll,

  /// Keeps clear of notches — `SafeArea`.
  safeArea;

  bool get isFlex => this == row || this == column;
  Axis get axis => this == row ? Axis.horizontal : Axis.vertical;
}

/// How children line up along and across a container.
enum UiAlign {
  start,
  center,
  end,
  spaceBetween,
  spaceAround,
  spaceEvenly,
  stretch;

  MainAxisAlignment get main => switch (this) {
    start => MainAxisAlignment.start,
    center => MainAxisAlignment.center,
    end => MainAxisAlignment.end,
    spaceBetween => MainAxisAlignment.spaceBetween,
    spaceAround => MainAxisAlignment.spaceAround,
    spaceEvenly => MainAxisAlignment.spaceEvenly,
    stretch => MainAxisAlignment.start,
  };

  CrossAxisAlignment get cross => switch (this) {
    start => CrossAxisAlignment.start,
    center => CrossAxisAlignment.center,
    end => CrossAxisAlignment.end,
    stretch => CrossAxisAlignment.stretch,
    _ => CrossAxisAlignment.center,
  };
}

/// A container: what it does with the entities under it.
class UiLayoutComponent extends Component {
  UiLayoutComponent({
    this.kind = UiLayoutKind.column,
    this.mainAxis = UiAlign.start,
    this.crossAxis = UiAlign.center,
    this.spacing = 0,
    this.padding = EdgeInsets.zero,
    this.columns = 3,
    this.tight = false,
  });

  UiLayoutKind kind;

  /// Along the container's direction.
  UiAlign mainAxis;

  /// Across it.
  UiAlign crossAxis;

  /// The gap between children.
  double spacing;

  EdgeInsets padding;

  /// For [UiLayoutKind.grid]: how many cells across.
  int columns;

  /// Whether the container takes only the room its children need.
  bool tight;

  @override
  String toString() => 'UiLayout(${kind.name})';
}

/// Something drawn behind its children: a background, a card, a bar.
class UiPanelComponent extends Component {
  UiPanelComponent({
    this.colorRole = 'surface',
    this.color,
    this.gradient,
    this.borderColor,
    this.borderWidth = 0,
    this.radius = 8,
    this.shadowBlur = 0,
    this.blur = 0,
    this.image = '',
    this.nineSlice = EdgeInsets.zero,
  });

  /// A colour from the theme, unless [color] says otherwise.
  String colorRole;
  Color? color;

  /// Two or more colours swept behind it.
  List<Color>? gradient;

  Color? borderColor;
  double borderWidth;
  double radius;

  /// A shadow under it; 0 for none.
  double shadowBlur;

  /// Frosts whatever is behind it.
  double blur;

  /// A picture instead of a colour.
  String image;

  /// Which parts of [image] stretch: the middle does, the corners do not.
  EdgeInsets nineSlice;

  bool get hasNineSlice =>
      image.isNotEmpty && (nineSlice.horizontal + nineSlice.vertical) > 0;

  /// What it is actually filled with under [theme]: its own colour where it
  /// has one, otherwise the colour its role names, otherwise the theme's
  /// surface.
  ///
  /// Here rather than in the layer so that what is drawn and what the
  /// inspector says it inherits cannot drift apart.
  Color colorUnder(UiTheme theme) =>
      color ?? theme.color(colorRole, fallbackColor: theme.palette.surface);

  /// The colour of its edge: its own, else the theme's outline. Only drawn
  /// where [borderWidth] is more than nothing.
  Color borderColorUnder(UiTheme theme) => borderColor ?? theme.palette.outline;

  @override
  String toString() => 'UiPanel($colorRole)';
}

/// A picture in the interface.
class UiImageComponent extends Component {
  UiImageComponent({
    this.path = '',
    this.atlasRegion = '',
    this.fit = BoxFit.contain,
    this.tint,
    this.opacity = 1,
  });

  /// An image asset, or the atlas the region is in.
  String path;

  /// A named region of an atlas at [path]; empty uses the whole image.
  String atlasRegion;

  BoxFit fit;
  Color? tint;
  double opacity;

  @override
  String toString() => 'UiImage($path)';
}

/// A switch with two states.
class UiToggleComponent extends Component {
  UiToggleComponent({
    this.value = false,
    this.label = '',
    this.binding = '',
    this.onChanged = UiActionList.empty,
  });

  bool value;
  String label;

  /// A binding read to keep this in step with the game.
  String binding;

  /// What happens when it is flipped; the new state is the action's value.
  UiActionList onChanged;

  @override
  String toString() => 'UiToggle($value)';
}

/// A number chosen by dragging.
class UiSliderComponent extends Component {
  UiSliderComponent({
    this.value = 0.5,
    this.min = 0,
    this.max = 1,
    this.steps = 0,
    this.label = '',
    this.binding = '',
    this.onChanged = UiActionList.empty,
  });

  double value;
  double min;
  double max;

  /// How many notches; 0 slides freely.
  int steps;

  String label;
  String binding;
  UiActionList onChanged;

  /// Where the handle sits, 0–1.
  double get fraction =>
      max <= min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0);

  @override
  String toString() => 'UiSlider($value)';
}

/// A line the player types into.
class UiTextFieldComponent extends Component {
  UiTextFieldComponent({
    this.value = '',
    this.hint = '',
    this.maxLength = 0,
    this.obscure = false,
    this.onSubmitted = UiActionList.empty,
    this.onChanged = UiActionList.empty,
  });

  String value;
  String hint;

  /// 0 for no limit.
  int maxLength;

  /// For a password.
  bool obscure;

  UiActionList onSubmitted;
  UiActionList onChanged;

  @override
  String toString() => 'UiTextField("$value")';
}

/// One of several choices.
class UiDropdownComponent extends Component {
  UiDropdownComponent({
    this.value = '',
    List<String>? options,
    this.label = '',
    this.onChanged = UiActionList.empty,
  }) : options = options ?? <String>[];

  String value;
  final List<String> options;
  String label;
  UiActionList onChanged;

  @override
  String toString() => 'UiDropdown($value)';
}

/// A bar that fills: health, loading, a timer.
class UiProgressComponent extends Component {
  UiProgressComponent({
    this.value = 0.5,
    this.binding = '',
    this.maxBinding = '',
    this.colorRole = 'accent',
    this.color,
    this.trackColor,
    this.radius = 6,
    this.radial = false,
    this.thickness = 8,
  });

  /// 0–1, unless a binding is reading it.
  double value;

  /// A binding to read instead of [value].
  String binding;

  /// With [binding], what to divide by — `health` over `maxHealth`.
  String maxBinding;

  String colorRole;
  Color? color;
  Color? trackColor;
  double radius;

  /// A ring rather than a bar.
  bool radial;

  /// How thick the ring is.
  double thickness;

  /// The colour the bar fills with under [theme].
  Color colorUnder(UiTheme theme) =>
      color ?? theme.color(colorRole, fallbackColor: theme.palette.accent);

  /// The colour behind it.
  Color trackColorUnder(UiTheme theme) => trackColor ?? theme.palette.outline;

  @override
  String toString() => 'UiProgress(${(value * 100).round()}%)';
}

/// A widget the game registered, placed from the editor.
///
/// This is the seam that makes the whole thing open-ended: anything
/// Flutter can do, a scene can hold.
class UiCustomComponent extends Component {
  UiCustomComponent({this.widgetId = '', Map<String, String>? props})
    : props = props ?? <String, String>{};

  /// The name it was registered under in `UiWidgets`.
  String widgetId;

  /// What the scene tells it, as plain text so it saves and shows in the
  /// inspector. A widget reads what it knows and ignores the rest.
  final Map<String, String> props;

  /// A property as a number, for a widget that wants one.
  double? number(String key) => double.tryParse(props[key] ?? '');

  /// A property as a flag.
  bool flag(String key) => props[key] == 'true';

  @override
  String toString() => 'UiCustom($widgetId)';
}

/// Empty room in a row or a column.
class UiSpacerComponent extends Component {
  UiSpacerComponent({this.size = 8, this.expand = false});

  /// How much room, when it is not expanding.
  double size;

  /// Take everything that is left, as Flutter's `Spacer` does.
  bool expand;

  @override
  String toString() => 'UiSpacer(${expand ? 'expand' : size})';
}
