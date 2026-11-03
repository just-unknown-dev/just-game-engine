/// Shorthands for the plain fields the engine's own definitions are made
/// of. Not exported: a package writes its fields with [SchemaField].
library;

import '../ecs.dart';
import 'component_definition.dart';
import 'field_type.dart';

/// A decimal, boolean, whole-number or text field, read from and written to
/// a component by the given functions.
abstract final class SchemaFields {
  /// A decimal field, clamped to [min] and [max] when given.
  static SchemaField decimal(
    String name,
    double Function(Component) read,
    void Function(Component, double) write, {
    double? min,
    double? max,
  }) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: read,
    write: (c, v) => write(c, (v as num).toDouble()),
    min: min,
    max: max,
  );

  /// A switch.
  static SchemaField boolean(
    String name,
    bool Function(Component) read,
    void Function(Component, bool) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: read,
    write: (c, v) => write(c, v as bool),
  );

  /// A whole number.
  static SchemaField integer(
    String name,
    int Function(Component) read,
    void Function(Component, int) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.integer,
    read: read,
    write: (c, v) => write(c, (v as num).toInt()),
  );

  /// A line of text.
  static SchemaField text(
    String name,
    String Function(Component) read,
    void Function(Component, String) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.text,
    read: read,
    write: (c, v) => write(c, v as String),
  );
}
