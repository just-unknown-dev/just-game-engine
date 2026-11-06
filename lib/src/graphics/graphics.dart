/// Graphics: 2-D (graphics_2d/) — the 2-D renderer, `RenderSystem`, and the
/// shapes, materials and lighting it draws an entity as, through and lit
/// by. 3-D graphics (graphics_3d/) is in
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

// The 2-D renderer: RenderSystem, its passes and 2-D lighting's pass.
export 'graphics_2d/render_system.dart';
export 'graphics_2d/render_pass.dart';
export 'graphics_2d/lighting_2d_pass.dart';

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
export 'graphics_2d/lighting/lighting_2d_item.dart';
