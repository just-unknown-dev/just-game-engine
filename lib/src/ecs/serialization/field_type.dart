library;

import 'field_type_impls.dart';
import 'field_type_shape_impls.dart';
import 'material_overrides_field_type.dart';

export 'field_type_impls.dart';
export 'field_type_shape_impls.dart';
export 'material_overrides_field_type.dart';

/// Bounds and parsers a field applies while decoding.
class FieldConstraints {
  /// Constraints with the bounds and parser given; each unset one is not
  /// applied.
  const FieldConstraints({this.min, this.max, this.enumParser});

  /// No constraints.
  static const none = FieldConstraints();

  /// Lower bound for numeric fields.
  final double? min;

  /// Upper bound for numeric fields.
  final double? max;

  /// Turns a stored enum name back into its value, for the generic
  /// [FieldTypes.enumeration] type. [EnumFieldType] needs none.
  final Object? Function(String value)? enumParser;
}

/// How one kind of field value is written to and read from JSON.
///
/// An open set: the engine ships the common kinds as [FieldTypes], and a
/// package adds its own by subclassing and registering it in a
/// [FieldTypeRegistry] — a waypoint list, a tile reference, a curve. The
/// editor looks up an inspector widget by [id], so a new type shows up in the
/// inspector as soon as a module supplies an editor for it, and as a visible
/// read-only row until then.
abstract class FieldType<T> {
  /// Const constructor so subclasses can be const.
  const FieldType();

  /// Stable identifier, written nowhere in a save but used to find the
  /// inspector editor and formatter for this type. Namespace custom ones
  /// (`'platformer.waypoints'`).
  String get id;

  /// Encodes a non-null [value] for JSON.
  Object? encode(T value);

  /// Decodes a non-null JSON [json]. Unrecognised shapes are returned as they
  /// are, so a value hand-edited into the wrong shape surfaces as a type
  /// error on write rather than silently becoming a default.
  Object? decode(Object? json, FieldConstraints constraints);

  /// [encode] for a value typed only as [Object].
  Object? encodeAny(Object? value) => value == null ? null : encode(value as T);

  /// [decode] that passes nulls through.
  Object? decodeAny(Object? json, FieldConstraints constraints) =>
      json == null ? null : decode(json, constraints);

  /// The named parts of a vector-like value as saved — `['x', 'y', 'z']` —
  /// or empty for a single value. What a timeline keys one by one, and what
  /// an inspector lays out on a row.
  List<String> get channels => const [];

  /// Which of [channels] a 2-D scene shows: a position's x and y, a
  /// rotation's z. All of them unless a type says otherwise.
  Set<String> get channels2D => channels.toSet();

  @override
  String toString() => 'FieldType($id)';
}

/// The field types the engine ships with.
///
/// Named after the `FieldKind` enum members they replace, so
/// `FieldKind.decimal` became `FieldTypes.decimal` with nothing else to
/// change.
abstract final class FieldTypes {
  /// A `bool`, saved as JSON `true` / `false`.
  static const boolean = BooleanFieldType();

  /// An `int`, clamped to the field's min and max when read.
  static const integer = IntegerFieldType();

  /// A `double`, clamped to the field's min and max when read.
  static const decimal = DecimalFieldType();

  /// A plain string.
  static const text = TextFieldType();

  /// A path into the asset bundle, stored as text; the editor offers a
  /// picker.
  static const assetRef = AssetRefFieldType();

  /// The name of another entity in the scene. Stored as text, looked up
  /// when it is needed; the editor offers the scene's entities.
  static const entityRef = EntityRefFieldType();

  /// A tag from the project's tag list; the editor offers the list.
  static const tagRef = TagRefFieldType();

  /// Several tags, as an entity's TagComponent carries them.
  static const tagList = TagListFieldType();

  /// A spawner the game registers, by id; the editor offers them.
  static const spawnerRef = SpawnerRefFieldType();

  /// Who a component means — an entity by name, or entities by tag. See
  /// [EntityTargetFieldType].
  static const target = EntityTargetFieldType();

  /// [target], also offering the component's own entity.
  static const targetOrSelf = EntityTargetFieldType(allowSelf: true);

  /// An enum stored by name, parsed back with [FieldConstraints.enumParser].
  /// Prefer [EnumFieldType], which needs no parser and knows its values.
  static const enumeration = EnumerationFieldType();

  /// A list of raw JSON values, kept as they are.
  static const list = ListFieldType();

  /// A map of raw JSON values, kept as they are.
  static const map = MapFieldType();

  /// A `Vector2`, saved as `{x, y}`.
  static const vector2 = Vector2FieldType();

  /// A `Vector3`, saved as `{x, y, z}`; a 2-D scene shows x and y.
  static const vector3 = Vector3FieldType();

  /// A rotation as Euler angles in radians, `{x, y, z}`.
  static const euler = EulerFieldType();

  /// A `Color`, saved as its ARGB int.
  static const color = ColorFieldType();

  /// An `Offset`, saved as `{dx, dy}`.
  static const offset = OffsetFieldType();

  /// A list of `Offset`s, saved as a list of `{dx, dy}`.
  static const offsetList = OffsetListFieldType();

  /// A shape's fill: colour, blend mode and optional gradient.
  static const shapePaintStyle = ShapePaintStyleFieldType();

  /// A physics collision shape, stored as `{kind, ...dimensions}`.
  static const physicsShape = PhysicsShapeFieldType();

  /// A collision layer, 0 to 15, saved as its number; the editor offers the
  /// project's layer names.
  static const physicsLayer = PhysicsLayerFieldType();

  /// A set of collision layers as a mask (bit `n` for layer `n`), or null
  /// for "as the project's grid says"; the editor offers the layers by name.
  static const physicsLayerMask = PhysicsLayerMaskFieldType();

  /// Space around something.
  static const edgeInsets = EdgeInsetsFieldType();

  /// A value the engine cannot interpret; stored and restored as raw JSON.
  static const unknown = UnknownFieldType();

  /// The built-in type with [id], or null. For mapping an editor's own
  /// field-kind names onto engine types.
  static FieldType? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Every built-in type, for seeding a [FieldTypeRegistry].
  static const List<FieldType> all = [
    boolean,
    integer,
    decimal,
    text,
    assetRef,
    entityRef,
    tagRef,
    tagList,
    spawnerRef,
    target,
    enumeration,
    list,
    map,
    vector2,
    vector3,
    euler,
    color,
    offset,
    offsetList,
    shapePaintStyle,
    physicsShape,
    physicsLayer,
    physicsLayerMask,
    edgeInsets,
    unknown,
  ];
}

/// Field types by [FieldType.id].
///
/// A module registers its own here; the editor resolves editors and
/// formatters through the same ids.
class FieldTypeRegistry {
  /// A registry holding every type in [FieldTypes.all], or nothing when
  /// [withBuiltIns] is false.
  FieldTypeRegistry({bool withBuiltIns = true}) {
    if (withBuiltIns) {
      registerAll(FieldTypes.all);
      registerAll(MaterialOverridesFieldType.all);
    }
  }

  final Map<String, FieldType> _byId = {};

  /// Registers [type]. Re-registering the same instance is a no-op; a
  /// different type with the same id throws unless [override] is set.
  void register(FieldType type, {bool override = false}) {
    final existing = _byId[type.id];
    if (existing != null && !identical(existing, type) && !override) {
      throw StateError(
        'A field type with id "${type.id}" is already registered '
        '(${existing.runtimeType}). Pass override: true to replace it.',
      );
    }
    _byId[type.id] = type;
  }

  /// Registers several types.
  void registerAll(Iterable<FieldType> types, {bool override = false}) {
    for (final t in types) {
      register(t, override: override);
    }
  }

  /// The type with [id], or null.
  FieldType? byId(String id) => _byId[id];

  /// Every registered type.
  Iterable<FieldType> get all => _byId.values;
}
