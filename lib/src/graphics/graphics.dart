/// Graphics: 2-D shapes, materials and lighting (graphics_2d/) — what an entity is
/// drawn as, drawn through and lit by; `RenderSystem` (in `rendering/`) draws
/// them. 3-D graphics (graphics_3d/) is in
/// `package:just_game_engine/just_game_engine_3d.dart`.
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

export 'graphics_2d/shapes/circle_2d_component.dart';
export 'graphics_2d/shapes/rectangle_2d_component.dart';
export 'graphics_2d/shapes/polygon_2d_component.dart';
export 'graphics_2d/shapes/line_2d_component.dart';
export 'graphics_2d/shapes/capsule_2d_component.dart';
export 'graphics_2d/shapes/shape_painting.dart';
export 'graphics_2d/shapes/shape_2d_definitions.dart';
export 'graphics_2d/shapes/shape_2d_look.dart';

export 'graphics_2d/materials/material_2d_library.dart';
export 'graphics_2d/materials/screen_material_pass.dart';
export 'graphics_2d/materials/material_2d_shader.dart';
export 'graphics_2d/materials/material_2d_component.dart';
export 'graphics_2d/materials/screen_material_component.dart';
export 'graphics_2d/materials/materials_2d_context.dart'
    show ContextMaterials2D;
export 'graphics_2d/materials/material_2d_definitions.dart';
export 'graphics_2d/materials/material_2d_overrides_field_type.dart';

export 'graphics_2d/lighting/light_2d_component.dart';
export 'graphics_2d/lighting/shadow_caster_2d_component.dart';
export 'graphics_2d/lighting/lighting_2d_definitions.dart';
