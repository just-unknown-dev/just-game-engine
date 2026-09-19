library;

import 'field_type_impls.dart';
import 'field_type_shape_impls.dart';

export 'field_type_impls.dart';
export 'field_type_shape_impls.dart';

/// Bounds and parsers a field applies while decoding.
class FieldConstraints {
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

  @override
  String toString() => 'FieldType($id)';
}

/// The field types the engine ships with.
///
/// Named after the `FieldKind` enum members they replace, so
/// `FieldKind.decimal` became `FieldTypes.decimal` with nothing else to
/// change.
abstract final class FieldTypes {
  static const boolean = BooleanFieldType();
  static const integer = IntegerFieldType();
  static const decimal = DecimalFieldType();
  static const text = TextFieldType();
  static const assetRef = AssetRefFieldType();

  /// An enum stored by name, parsed back with [FieldConstraints.enumParser].
  /// Prefer [EnumFieldType], which needs no parser and knows its values.
  static const enumeration = EnumerationFieldType();
  static const list = ListFieldType();
  static const map = MapFieldType();
  static const vector2 = Vector2FieldType();
  static const vector3 = Vector3FieldType();
  static const color = ColorFieldType();
  static const offset = OffsetFieldType();
  static const offsetList = OffsetListFieldType();
  static const shapePaintStyle = ShapePaintStyleFieldType();

  /// A physics collision shape, stored as `{kind, ...dimensions}`.
  static const physicsShape = PhysicsShapeFieldType();

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
    enumeration,
    list,
    map,
    vector2,
    vector3,
    color,
    offset,
    offsetList,
    shapePaintStyle,
    physicsShape,
    unknown,
  ];
}

/// Field types by [FieldType.id].
///
/// A module registers its own here; the editor resolves editors and
/// formatters through the same ids.
class FieldTypeRegistry {
  FieldTypeRegistry({bool withBuiltIns = true}) {
    if (withBuiltIns) registerAll(FieldTypes.all);
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
