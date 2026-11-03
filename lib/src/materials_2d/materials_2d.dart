/// 2-D materials: the files entities are drawn through ([Material2DComponent]), and
/// what draws them.
library;

export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show
        Material2DEffect,
        Material2DEffects,
        Material2DFile,
        Material2DKind,
        Material2DParam,
        Material2DValue,
        MaterialChain,
        ResolvedMaterial;

export 'material_2d_batch.dart';
export 'material_2d_library.dart';
export 'material_2d_screen.dart';
export 'material_2d_shader.dart';
export 'material_2d_shapes.dart';
export 'material_2d_component.dart';
export 'screen_material_component.dart';
export 'materials_2d_context.dart' show ContextMaterials2D;
export 'material_2d_definitions.dart';
