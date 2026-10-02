library;

import 'dart:ui';

import 'package:flutter/widgets.dart' show IconData;

import '../../foundation/dimensions.dart';
import '../ecs.dart';
import 'component_codec.dart';
import 'component_presentation.dart';
import 'field_type.dart';

/// One persisted property of a component.
class SchemaField {
  /// A field saved under [name] as [kind], taken from a component by [read]
  /// and put back by [write]. [min], [max] and [enumParser] shape what
  /// decoding accepts; leave them null to apply none.
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
  /// A scrub of [step] per [pixelsPerStep] pixels dragged, shown with
  /// [fractionDigits] decimals, or as a whole number when [integer], and
  /// followed by [suffix].
  const ScrubHint({
    this.step = 1.0,
    this.pixelsPerStep = 12.0,
    this.fractionDigits = 2,
    this.integer = false,
    this.suffix,
  });

  /// How much the value changes for each [pixelsPerStep] dragged.
  final double step;

  /// Horizontal drag distance, in logical pixels, that moves the value by
  /// one [step].
  final double pixelsPerStep;

  /// Decimal places the value is shown with.
  final int fractionDigits;

  /// Whether scrubbing rounds to whole numbers and shows no decimals.
  final bool integer;

  /// The unit shown after the value — `px`, `/s`, `°/s` — or none.
  final String? suffix;
}

/// How an angle is shown; the value itself is always radians.
enum AngleUnit {
  /// Shown as stored, in radians.
  radians,

  /// Shown and typed in degrees; converted to radians to store.
  degrees,
}

/// Several numeric fields of a component on one inspector row, as a vector's
/// axes are: `Dead zone  W [0.10]  H [0.10]`.
class FieldRowHint {
  /// A row called [label] holding the fields named in [cells], in order.
  const FieldRowHint(this.label, this.cells);

  /// The row's label, where a single field's would be.
  final String label;

  /// [SchemaField.name] → the short label of its cell: `X`, `W`, `Min`.
  /// In order, left to right.
  final Map<String, String> cells;
}

/// How one field appears in an inspector. Presentation only — the field's
/// name, kind, limits and read/write come from its [SchemaField].
class FieldHint {
  /// Presentation for one field; every hint is optional, and by default the
  /// field is shown, editable, in both 2-D and 3-D scenes.
  const FieldHint({
    this.label,
    this.description,
    this.visible = true,
    this.visibleWhen,
    this.editable = true,
    this.scrub,
    this.slider = false,
    this.unit,
    this.fileExtensions,
    this.itemTemplate,
    this.itemKinds,
    this.dimensions = Dimensions.both,
    this.channels2D,
  });

  /// The name shown for the field; its [SchemaField.name] when null.
  final String? label;

  /// Help text about the field an editor may show with it; none when null.
  final String? description;

  /// Whether the inspector shows the field at all. Hidden, it is still
  /// saved.
  final bool visible;

  /// Shown only while this returns true — a crumble delay only on a
  /// crumbling platform, say.
  final bool Function(Component component)? visibleWhen;

  /// Whether the inspector lets the value be changed; off, it is shown
  /// read-only. A field with no [SchemaField.write] is read-only anyway.
  final bool editable;

  /// Makes a numeric field drag-to-scrub, and how; null leaves it to the
  /// editor.
  final ScrubHint? scrub;

  /// For a number with both a [SchemaField.min] and a [SchemaField.max]:
  /// show a slider between them beside the value, for a setting whose
  /// range matters more than its digits — a bounciness from 0 to 1.
  final bool slider;

  /// For angles: show degrees while storing radians.
  final AngleUnit? unit;

  /// For asset references: which files the picker offers.
  final List<String>? fileExtensions;

  /// For a list or map field: what a newly added item looks like — a map of
  /// keys to starting values for a list of objects, a value for a map's new
  /// entry. An editor's "Add" copies it, so a new item starts with the right
  /// shape and types. Null leaves the editor to copy the last item.
  final Object? itemTemplate;

  /// For a list of objects: the [FieldType] of an item's key whose value is
  /// more than plain text, a number or a switch — a target, a tag — so an
  /// editor offers the right picker for it.
  final Map<String, FieldType>? itemKinds;

  /// Which scene modes the field is shown in — a camera's field of view only
  /// in 3-D, say. It is saved either way.
  final Dimensions dimensions;

  /// Which of a vector field's axes a 2-D scene shows (`{'x', 'y'}`), where
  /// they differ from its type's [FieldType.channels2D]. Hidden axes keep
  /// their values.
  final Set<String>? channels2D;
}

/// How a component appears in an inspector and component picker.
///
/// Plain data, so it can live beside the runtime definition — a handful of
/// constants, tree-shaken from a build that never shows an inspector.
class ComponentHints {
  /// Presentation for one component; every hint is optional. By default it
  /// is one per entity, removable, and offered in 2-D and 3-D scenes.
  const ComponentHints({
    this.name,
    this.group,
    this.description,
    this.icon,
    this.accentColor,
    this.allowMultiple = false,
    this.deletable = true,
    this.fieldGroups,
    this.foldedGroups = const {},
    this.fieldRows = const [],
    this.fields = const {},
    this.dimensions = Dimensions.both,
  });

  /// Display name; the type name when unset.
  final String? name;

  /// Component picker group.
  final String? group;

  /// A line about what the component does, shown under its inspector
  /// header and in the component picker; none when null.
  final String? description;

  /// The icon beside its name in the inspector; none when null.
  final IconData? icon;

  /// The colour that marks it — its inspector card's edge and icon; the
  /// editor's own colours when null.
  final Color? accentColor;

  /// Whether an entity may carry more than one.
  final bool allowMultiple;

  /// Whether the inspector offers to remove it.
  final bool deletable;

  /// Header → field names under it, in order. Fields in no group list first.
  final Map<String, List<String>>? fieldGroups;

  /// Which of [fieldGroups] start folded, opened with a click: settings few
  /// people need, kept out of the way of the ones everybody does.
  final Set<String> foldedGroups;

  /// Numbers that belong together, shown side by side on one row — a width
  /// and a height, a minimum and a maximum. A row sits where its first field
  /// would, and only gathers fields listed beside it (the same group).
  final List<FieldRowHint> fieldRows;

  /// Per-field presentation, by [SchemaField.name].
  final Map<String, FieldHint> fields;

  /// Which scene modes the component belongs in. An editor offers it only
  /// there — though one already on an entity is always shown.
  final Dimensions dimensions;
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
  /// A definition saved as [type], built by [create] and persisting
  /// [fields]. [aliases] are older names it also loads; [extent] and
  /// [painter] only matter to components with a size or that draw
  /// themselves.
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
    this.afterDecode,
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
    void Function(Component component)? afterDecode,
  }) : fields = [...base.fields, ...extraFields],
       hints = hints ?? base.hints,
       extent = extent ?? base.extent,
       painter = painter ?? base.painter,
       afterDecode = afterDecode ?? base.afterDecode,
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

  /// Runs on a component [decode] has just filled in, once every saved field
  /// is set: for state that is not saved but has to agree with what was —
  /// a transform's previous pose, which render interpolation reads, has to
  /// be the pose just loaded rather than the origin. Null for none.
  final void Function(Component component)? afterDecode;

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
    afterDecode?.call(component);
    return component;
  }
}
