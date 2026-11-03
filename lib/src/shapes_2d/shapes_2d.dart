/// Shape components — primitive geometry for entities.
///
/// Each component is a pure data container describing a shape in local
/// (entity-relative) space. A render system reads these to produce visuals.
library;

export 'circle_2d_component.dart';
export 'rectangle_2d_component.dart';
export 'polygon_2d_component.dart';
export 'line_2d_component.dart';
export 'capsule_2d_component.dart';
export '../foundation/shape_paint_style.dart';
export 'shape_painting.dart';
export 'shape_paint_cache.dart';
export 'solid_shape.dart';
export 'shape_definitions_2d.dart';
