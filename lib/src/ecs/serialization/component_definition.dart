library;

import 'dart:ui';

import 'package:flutter/widgets.dart' show IconData;

import '../../interfaces/interfaces.dart';
import '../ecs.dart';
import 'component_codec.dart';
import 'field_type.dart';

/// One persisted property of a component.
class SchemaField {
  const SchemaField({
    required this.name,
    required this.kind,
    required this.read,
    this.write,
    this.enumParser,
    this.min,
    this.max,
  });

  /// Key in the saved JSON. Stable: renaming it orphans saved values, which
  /// then silently load as defaults.
  final String name;

  /// How the value is written to JSON.
  final FieldType kind;

  /// Reads the value from a component.
  final Object? Function(Component component) read;

  /// Writes a decoded value back. Null for a derived, read-only value that is
  /// saved for reference but never restored.
  final void Function(Component component, Object? value)? write;

  /// Turns a stored enum name back into its value, for the generic
  /// [FieldTypes.enumeration] kind. An [EnumFieldType] needs none.
  final Object? Function(String value)? enumParser;

  /// Lower bound applied on decode.
  final double? min;

  /// Upper bound applied on decode.
  final double? max;

  /// The constraints [kind] applies while decoding.
  FieldConstraints get constraints =>
      FieldConstraints(min: min, max: max, enumParser: enumParser);

  /// Encodes this field's current value on [component].
  Object? encodeFrom(Component component) => kind.encodeAny(read(component));

  /// Decodes [json] and writes it, if the field is writable.
  void decodeInto(Component component, Object? json) =>
      write?.call(component, kind.decodeAny(json, constraints));
}

/// Drag-to-scrub feel for a numeric field in an inspector. Limits are not
/// here: they come from [SchemaField.min]/[SchemaField.max], so what the
/// inspector allows and what a load accepts cannot drift apart.
class ScrubHint {
  const ScrubHint({
    this.step = 1.0,
    this.pixelsPerStep = 12.0,
    this.fractionDigits = 2,
    this.integer = false,
  });

  final double step;
  final double pixelsPerStep;
  final int fractionDigits;
  final bool integer;
}

/// How an angle is shown; the value itself is always radians.
enum AngleUnit { radians, degrees }

/// How one field appears in an inspector. Presentation only — the field's
/// name, kind, limits and read/write come from its [SchemaField].
class FieldHint {
  const FieldHint({
    this.label,
    this.description,
    this.visible = true,
    this.visibleWhen,
    this.editable = true,
    this.scrub,
    this.unit,
    this.fileExtensions,
  });

  final String? label;
  final String? description;
  final bool visible;

  /// Shown only while this returns true — a crumble delay only on a
  /// crumbling platform, say.
  final bool Function(Component component)? visibleWhen;
  final bool editable;
  final ScrubHint? scrub;

  /// For angles: show degrees while storing radians.
  final AngleUnit? unit;

  /// For asset references: which files the picker offers.
  final List<String>? fileExtensions;
}

/// How a component appears in an inspector and component picker.
///
/// Plain data, so it can live beside the runtime definition — a handful of
/// constants, tree-shaken from a build that never shows an inspector.
class ComponentHints {
  const ComponentHints({
    this.name,
    this.group,
    this.description,
    this.icon,
    this.accentColor,
    this.allowMultiple = false,
    this.deletable = true,
    this.fieldGroups,
    this.fields = const {},
  });

  /// Display name; the type name when unset.
  final String? name;

  /// Component picker group.
  final String? group;
  final String? description;
  final IconData? icon;
  final Color? accentColor;

  /// Whether an entity may carry more than one.
  final bool allowMultiple;

  /// Whether the inspector offers to remove it.
  final bool deletable;

  /// Header → field names under it, in order. Fields in no group list first.
  final Map<String, List<String>>? fieldGroups;

  /// Per-field presentation, by [SchemaField.name].
  final Map<String, FieldHint> fields;
}

/// The size a component implies, and how to change it.
///
/// Unifies what used to be three separate type switches (selection bounds,
/// resize handles, gizmo bounds) into one answer per definition.
abstract class ComponentExtent {
  const ComponentExtent();

  /// The component's local, unrotated size, or null if it implies none.
  Size? sizeOf(Component component);

  /// Scales the component's own dimensions by ([sx], [sy]). Returns false when
  /// it has nothing to scale.
  bool scale(Component component, double sx, double sy) => false;

  /// Mirrors the component across its own centre, if that means anything
  /// for it — a sprite's flip flag, say.
  void flip(Component component, {required bool horizontal}) {}
}

/// What a [ComponentPainter] is given per frame.
class RenderContext {
  const RenderContext({
    required this.world,
    required this.size,
    this.camera,
    this.interpolation = 1.0,
  });

  final World world;
  final Size size;
  final GameCamera? camera;

  /// Sub-frame interpolation factor for physics-driven entities.
  final double interpolation;
}

/// Draws a component that is not a [RenderableComponent] — text, a button, a
/// progress bar, anything that renders itself from its own fields.
///
/// The canvas is already translated, rotated and scaled by the entity's
/// transform, so painters draw around the origin.
abstract class ComponentPainter<T extends Component> {
  const ComponentPainter();

  /// Draw order within the painter pass; lower first.
  int layerOf(T component) => 0;

  /// Whether to draw at all this frame.
  bool isVisible(T component) => true;

  void paint(Canvas canvas, Entity entity, T component, RenderContext context);

  /// [paint] for a component typed only as [Component].
  void paintAny(Canvas canvas, Entity entity, Component c, RenderContext ctx) =>
      paint(canvas, entity, c as T, ctx);

  int layerOfAny(Component c) => layerOf(c as T);
  bool isVisibleAny(Component c) => isVisible(c as T);
}

/// Everything the engine and editor need to know about one component type,
/// in one place: how to build it, what it persists, how it looks in an
/// inspector, how big it is, and how it draws.
///
/// It *is* the codec — registering a definition makes the component
/// saveable — and the inspector is built from the same fields, so a field
/// cannot be shown without being saved.
///
/// Writes `{type, fields}`. A definition given an [id] also writes
/// `customComponentId`, which the editor stored for years; new definitions
/// leave it null.
class ComponentDefinition<T extends Component> extends ComponentCodec<T> {
  const ComponentDefinition({
    required this.type,
    required this.create,
    required this.fields,
    this.id,
    this.aliases = const [],
    this.hints = const ComponentHints(),
    this.extent,
    this.painter,
    this.parent,
  });

  /// A definition for a subclass of [base]'s component: inherits its fields,
  /// hints, extent and painter, and persists [extraFields] on top.
  ///
  /// This is how a game extends a built-in without losing its own fields on
  /// save — the alternative, a bare subclass, would encode as the base type
  /// and reload without them.
  ComponentDefinition.extend(
    ComponentDefinition<Component> base, {
    required this.type,
    required this.create,
    List<SchemaField> extraFields = const [],
    this.id,
    this.aliases = const [],
    ComponentHints? hints,
    ComponentExtent? extent,
    ComponentPainter? painter,
  }) : fields = [...base.fields, ...extraFields],
       hints = hints ?? base.hints,
       extent = extent ?? base.extent,
       painter = painter ?? base.painter,
       parent = base;

  @override
  final String type;

  /// Older `customComponentId` written for compatibility; null for none.
  final String? id;

  /// Builds a component with default values, which [decode] then overwrites
  /// field by field. A field missing from the JSON keeps its default.
  final T Function() create;

  /// Every persisted property.
  final List<SchemaField> fields;

  /// Other `type` strings (or old `customComponentId`s) this definition also
  /// loads, so a component can be renamed without breaking saved levels.
  final List<String> aliases;

  /// Inspector presentation.
  final ComponentHints hints;

  /// Size and resize behaviour, if the component implies an extent.
  final ComponentExtent? extent;

  /// How the render system draws it, if it draws itself.
  final ComponentPainter? painter;

  /// The definition this one extends, if any.
  final ComponentDefinition<Component>? parent;

  /// The field named [name], or null.
  SchemaField? field(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  @override
  Map<String, dynamic> encode(T component) => {
    'type': type,
    'fields': {for (final f in fields) f.name: f.encodeFrom(component)},
  };

  @override
  T decode(Map<String, dynamic> json) {
    final component = create();
    final values =
        (json['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final f in fields) {
      if (values.containsKey(f.name)) f.decodeInto(component, values[f.name]);
    }
    return component;
  }
}
