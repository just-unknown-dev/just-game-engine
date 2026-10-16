library;

import 'field_type.dart';

/// Converts one field value to and from its JSON form.
///
/// A thin facade over [FieldType]: the value coding lives on the type, so a
/// package's own field types code their values the same way the built-ins
/// do. Kept for callers that pass a type and a value separately.
abstract final class FieldValueCodec {
  /// Encodes [value] for JSON.
  static Object? encode(FieldType kind, Object? value) => kind.encodeAny(value);

  /// Decodes [value] from JSON.
  ///
  /// [min] and [max] clamp numeric values, so a hand-edited file cannot push
  /// a field outside the range the inspector allows. [enumParser] turns an
  /// enum's stored name back into the value.
  static Object? decode(
    FieldType kind,
    Object? value, {
    Object? Function(String value)? enumParser,
    double? min,
    double? max,
  }) => kind.decodeAny(
    value,
    FieldConstraints(min: min, max: max, enumParser: enumParser),
  );
}
