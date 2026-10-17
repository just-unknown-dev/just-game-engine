/// The values an entity overrides of its material, as a field a timeline
/// can key.
library;

import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import 'field_type_impls.dart';

/// An entity's own values for its material — `Material2D.overrides`,
/// `ScreenMaterial.overrides`, `MaterialOverrides3D.values` — saved as a map
/// by key, whose [channels] are the numbers in it a timeline can key: each
/// animatable number, a pair as `key#0` and `key#1`. (A colour is changed
/// from code: keyed as one number it would not blend as a colour.)
final class MaterialOverridesFieldType extends MapFieldType {
  MaterialOverridesFieldType._(this.id, this.channels);

  @override
  final String id;

  @override
  final List<String> channels;

  /// A 2-D material's overrides: every number of every effect, of both
  /// kinds (sprite and screen).
  static final MaterialOverridesFieldType material2D =
      MaterialOverridesFieldType._(
        'material2DOverrides',
        List.unmodifiable([
          for (final effect in Material2DEffects.all)
            for (final p in effect.params)
              if (p.type == Material2DValue.number)
                '${effect.id}.${p.name}'
              else if (p.type == Material2DValue.pair) ...[
                '${effect.id}.${p.name}#0',
                '${effect.id}.${p.name}#1',
              ],
        ]),
      );

  /// A 3-D material's overrides: its animatable numbers.
  static final MaterialOverridesFieldType material3D =
      MaterialOverridesFieldType._('material3DOverrides', const [
        'metallic',
        'roughness',
        'emissionStrength',
        'opacity',
        'alphaCutoff',
        'normalScale',
        'occlusionStrength',
        'rotation',
        'tiling#0',
        'tiling#1',
        'offset#0',
        'offset#1',
      ]);

  /// Both.
  static List<MaterialOverridesFieldType> get all => [material2D, material3D];
}
