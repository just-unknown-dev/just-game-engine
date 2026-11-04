/// Shorthands for the plain fields the engine's own definitions are made
/// of. Not exported: a package writes its fields with [FieldDefinition].
library;

import 'package:meta/meta.dart' show internal;

import '../world.dart';
import 'component_definition.dart';
import 'field_type.dart';

/// A decimal, boolean, whole-number or text field, read from and written to
/// a component by the given functions.
@internal
abstract final class FieldDefinitions {
  /// A decimal field, clamped to [min] and [max] when given.
  static FieldDefinition decimal(
    String name,
    double Function(Component) read,
    void Function(Component, double) write, {
    double? min,
    double? max,
  }) => FieldDefinition(
    name: name,
    kind: FieldTypes.decimal,
    read: read,
    write: (c, v) => write(c, (v as num).toDouble()),
    min: min,
    max: max,
  );

  /// A switch.
  static FieldDefinition boolean(
    String name,
    bool Function(Component) read,
    void Function(Component, bool) write,
  ) => FieldDefinition(
    name: name,
    kind: FieldTypes.boolean,
    read: read,
    write: (c, v) => write(c, v as bool),
  );

  /// A whole number.
  static FieldDefinition integer(
    String name,
    int Function(Component) read,
    void Function(Component, int) write,
  ) => FieldDefinition(
    name: name,
    kind: FieldTypes.integer,
    read: read,
    write: (c, v) => write(c, (v as num).toInt()),
  );

  /// A line of text.
  static FieldDefinition text(
    String name,
    String Function(Component) read,
    void Function(Component, String) write,
  ) => FieldDefinition(
    name: name,
    kind: FieldTypes.text,
    read: read,
    write: (c, v) => write(c, v as String),
  );
}
