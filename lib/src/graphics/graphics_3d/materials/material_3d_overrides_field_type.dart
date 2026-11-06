/// The values an entity overrides of its 3-D materials, as a field a
/// timeline can key.
library;

import '../../../ecs/serialization/built_in_field_types.dart';
import 'material_3d_definitions.dart';

/// An entity's own values for the 3-D material files it is drawn with —
/// `MaterialOverrides3DComponent.values` — saved as a map by key, whose
/// [channels] are the numbers in it a timeline can key, a pair as `key#0`
/// and `key#1`. (A colour is changed from code: keyed as one number it
/// would not blend as a colour.)
final class Material3DOverridesFieldType extends MapFieldType {
  /// Const constructor; the shared instance is
  /// [Material3DDefinitions.overridesType].
  const Material3DOverridesFieldType();

  @override
  String get id => 'material3DOverrides';

  @override
  List<String> get channels => const [
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
  ];
}
