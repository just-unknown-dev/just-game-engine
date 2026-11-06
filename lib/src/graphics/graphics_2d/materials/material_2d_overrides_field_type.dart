/// The values an entity overrides of its 2-D material, as a field a
/// timeline can key.
library;

import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import '../../../ecs/serialization/built_in_field_types.dart';
import 'material_2d_definitions.dart';

/// An entity's own values for its 2-D material —
/// `Material2DComponent.overrides`, `ScreenMaterialComponent.overrides` —
/// saved as a map by key, whose [channels] are the numbers in it a timeline
/// can key: every number of every effect, of both kinds (sprite and
/// screen), a pair as `key#0` and `key#1`. (A colour is changed from code:
/// keyed as one number it would not blend as a colour.)
final class Material2DOverridesFieldType extends MapFieldType {
  /// Const constructor; the shared instance is
  /// [Material2DDefinitions.overridesType].
  const Material2DOverridesFieldType();

  @override
  String get id => 'material2DOverrides';

  @override
  List<String> get channels => _channels;

  static final List<String> _channels = List.unmodifiable([
    for (final effect in Material2DEffects.all)
      for (final p in effect.params)
        if (p.type == Material2DValue.number)
          '${effect.id}.${p.name}'
        else if (p.type == Material2DValue.pair) ...[
          '${effect.id}.${p.name}#0',
          '${effect.id}.${p.name}#1',
        ],
  ]);
}
