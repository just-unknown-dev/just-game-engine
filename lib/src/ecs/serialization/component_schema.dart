library;

import '../ecs.dart';
import 'component_definition.dart';

export 'component_definition.dart';

/// A component described as data: a type name, a factory, and its fields.
///
/// This is the way to make a component saveable, and it is also what the
/// editor's inspector can be built from — describe a component once and it
/// both persists and appears in the editor:
///
/// ```dart
/// final healthSchema = ComponentSchema<HealthComponent>(
///   type: 'HealthComponent',
///   id: 'health',
///   create: HealthComponent.new,
///   fields: [
///     SchemaField(
///       name: 'max',
///       kind: FieldKind.decimal,
///       read: (c) => (c as HealthComponent).max,
///       write: (c, v) => (c as HealthComponent).max = v as double,
///       min: 0,
///     ),
///   ],
/// );
/// ```
///
/// A [ComponentDefinition] that always writes a `customComponentId` — the
/// shape the editor has saved descriptor-backed components in, so existing
/// levels load unchanged. New definitions should use [ComponentDefinition]
/// directly.
class ComponentSchema<T extends Component> extends ComponentDefinition<T> {
  const ComponentSchema({
    required super.type,
    required String id,
    required super.create,
    required super.fields,
    super.aliases,
    super.hints,
    super.extent,
    super.painter,
  }) : super(id: id);

  /// The `customComponentId` this schema writes. Never null on a schema.
  @override
  String get id => super.id!;
}
