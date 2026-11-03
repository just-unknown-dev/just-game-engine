/// The 2-D shape components: rectangle, circle, capsule, line and polygon.
library;

import '../ecs/ecs.dart';
import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_presentation.dart';
import '../ecs/serialization/component_schema.dart';
import '../ecs/serialization/field_type.dart';
import '../ecs/serialization/schema_fields.dart';
import '../foundation/dimensions.dart';
import 'capsule_2d_component.dart';
import 'circle_2d_component.dart';
import 'line_2d_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'polygon_2d_component.dart';
import 'rectangle_2d_component.dart';
import '../foundation/shape_paint_style.dart';

/// The 2-D shape components: rectangle, circle, capsule, line and polygon.
abstract final class Shape2DDefinitions {
  static SchemaField _style(
    String name,
    ShapePaintStyle Function(Component) read,
    void Function(Component, ShapePaintStyle) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.shapePaintStyle,
    read: read,
    write: (c, v) => write(c, v as ShapePaintStyle),
  );

  static List<SchemaField> _styleFields<T extends Component>(
    ShapePaintStyle Function(T) fill,
    void Function(T, ShapePaintStyle) setFill,
    ShapePaintStyle Function(T) stroke,
    void Function(T, ShapePaintStyle) setStroke,
    bool Function(T) filled,
    void Function(T, bool) setFilled,
    double Function(T) strokeWidth,
    void Function(T, double) setStrokeWidth,
  ) => [
    _style('fillStyle', (c) => fill(c as T), (c, v) => setFill(c as T, v)),
    _style(
      'strokeStyle',
      (c) => stroke(c as T),
      (c, v) => setStroke(c as T, v),
    ),
    SchemaFields.boolean(
      'filled',
      (c) => filled(c as T),
      (c, v) => setFilled(c as T, v),
    ),
    SchemaFields.decimal(
      'strokeWidth',
      (c) => strokeWidth(c as T),
      (c, v) => setStrokeWidth(c as T, v),
      min: 0,
    ),
  ];

  /// Presentation shared by the shape components' style fields.
  static const Map<String, FieldHint> _styleHints = {
    'filled': FieldHint(label: 'Filled'),
    'fillStyle': FieldHint(label: 'Fill'),
    'strokeStyle': FieldHint(label: 'Stroke'),
    'strokeWidth': FieldHint(
      label: 'SW',
      scrub: ScrubHint(step: 0.5, fractionDigits: 1),
    ),
  };

  /// Definition of [Rectangle2DComponent], saved as `Rectangle2DComponent`; a
  /// new one is 64 × 64. 2-D only.
  static ComponentDefinition<Rectangle2DComponent> get rectangle =>
      ComponentDefinition<Rectangle2DComponent>(
        type: 'Rectangle2DComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Rectangle',
          group: 'Rendering',
          description: 'A filled or outlined rectangle.',
          icon: Icons.rectangle_outlined,
          accentColor: Color(0xFF42A5F5),
          fieldGroups: {
            'Size': ['width', 'height', 'cornerRadius'],
            'Appearance': ['filled', 'fillStyle', 'strokeStyle', 'strokeWidth'],
          },
          fieldRows: [
            FieldRowHint('Size', {'width': 'W', 'height': 'H'}),
          ],
          fields: {
            'width': FieldHint(label: 'W', scrub: ScrubHint(fractionDigits: 1)),
            'height': FieldHint(
              label: 'H',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'cornerRadius': FieldHint(
              label: 'CR',
              scrub: ScrubHint(step: 0.5, fractionDigits: 1),
            ),
            ..._styleHints,
          },
        ),
        create: () => Rectangle2DComponent(width: 64, height: 64),
        fields: [
          SchemaFields.decimal(
            'width',
            (c) => (c as Rectangle2DComponent).width,
            (c, v) => (c as Rectangle2DComponent).width = v,
            min: 1,
          ),
          SchemaFields.decimal(
            'height',
            (c) => (c as Rectangle2DComponent).height,
            (c, v) => (c as Rectangle2DComponent).height = v,
            min: 1,
          ),
          ..._styleFields<Rectangle2DComponent>(
            (c) => c.fillStyle,
            (c, v) => c.fillStyle = v,
            (c) => c.strokeStyle,
            (c, v) => c.strokeStyle = v,
            (c) => c.filled,
            (c, v) => c.filled = v,
            (c) => c.strokeWidth,
            (c, v) => c.strokeWidth = v,
          ),
          SchemaFields.decimal(
            'cornerRadius',
            (c) => (c as Rectangle2DComponent).cornerRadius,
            (c, v) => (c as Rectangle2DComponent).cornerRadius = v,
            min: 0,
          ),
        ],
        extent: const _RectangleExtent(),
      );

  /// Definition of [Circle2DComponent], saved as `Circle2DComponent`; a new one
  /// has radius 32. 2-D only.
  static ComponentDefinition<Circle2DComponent> get circle =>
      ComponentDefinition<Circle2DComponent>(
        type: 'Circle2DComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Circle',
          group: 'Rendering',
          description: 'A filled or outlined circle.',
          icon: Icons.circle_outlined,
          accentColor: Color(0xFF42A5F5),
          fieldGroups: {
            'Size': ['radius'],
            'Appearance': ['filled', 'fillStyle', 'strokeStyle', 'strokeWidth'],
          },
          fields: {
            'radius': FieldHint(
              label: 'Radius',
              scrub: ScrubHint(step: 0.5, fractionDigits: 1),
            ),
            ..._styleHints,
          },
        ),
        create: () => Circle2DComponent(radius: 32),
        fields: [
          SchemaFields.decimal(
            'radius',
            (c) => (c as Circle2DComponent).radius,
            (c, v) => (c as Circle2DComponent).radius = v,
            min: 1,
          ),
          ..._styleFields<Circle2DComponent>(
            (c) => c.fillStyle,
            (c, v) => c.fillStyle = v,
            (c) => c.strokeStyle,
            (c, v) => c.strokeStyle = v,
            (c) => c.filled,
            (c, v) => c.filled = v,
            (c) => c.strokeWidth,
            (c, v) => c.strokeWidth = v,
          ),
        ],
        extent: const _CircleExtent(),
      );

  /// Definition of [Capsule2DComponent], saved as `Capsule2DComponent`; a new
  /// one is 32 wide, 64 high. 2-D only.
  static ComponentDefinition<Capsule2DComponent> get capsule =>
      ComponentDefinition<Capsule2DComponent>(
        type: 'Capsule2DComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Capsule',
          group: 'Rendering',
          description: 'A filled or outlined capsule.',
          icon: Icons.crop_portrait,
          accentColor: Color(0xFF42A5F5),
          fieldGroups: {
            'Size': ['width', 'height'],
            'Appearance': ['filled', 'fillStyle', 'strokeStyle', 'strokeWidth'],
          },
          fieldRows: [
            FieldRowHint('Size', {'width': 'W', 'height': 'H'}),
          ],
          fields: {
            'width': FieldHint(label: 'W', scrub: ScrubHint(fractionDigits: 1)),
            'height': FieldHint(
              label: 'H',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            ..._styleHints,
          },
        ),
        create: () => Capsule2DComponent(width: 32, height: 64),
        fields: [
          SchemaFields.decimal(
            'width',
            (c) => (c as Capsule2DComponent).width,
            (c, v) => (c as Capsule2DComponent).width = v,
            min: 1,
          ),
          SchemaFields.decimal(
            'height',
            (c) => (c as Capsule2DComponent).height,
            (c, v) => (c as Capsule2DComponent).height = v,
            min: 1,
          ),
          ..._styleFields<Capsule2DComponent>(
            (c) => c.fillStyle,
            (c, v) => c.fillStyle = v,
            (c) => c.strokeStyle,
            (c, v) => c.strokeStyle = v,
            (c) => c.filled,
            (c, v) => c.filled = v,
            (c) => c.strokeWidth,
            (c, v) => c.strokeWidth = v,
          ),
        ],
        extent: const _CapsuleExtent(),
      );

  /// [Line2DComponent], from `line_editor_component.dart`.
  static ComponentSchema<Line2DComponent> get line =>
      ComponentSchema<Line2DComponent>(
        type: 'Line2DComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Line',
          group: 'Rendering',
          icon: Icons.show_chart,
          accentColor: Color(0xFF42A5F5),
          fieldGroups: {
            'Points': ['startX', 'startY', 'endX', 'endY'],
            'Appearance': ['strokeColor', 'strokeW', 'roundCaps'],
          },
          fields: {
            'startX': FieldHint(
              label: 'Start X',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'startY': FieldHint(
              label: 'Start Y',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'endX': FieldHint(
              label: 'End X',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'endY': FieldHint(
              label: 'End Y',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'strokeColor': FieldHint(label: 'Paint'),
            'strokeW': FieldHint(
              label: 'Stroke',
              scrub: ScrubHint(step: 0.5, fractionDigits: 1),
            ),
            'roundCaps': FieldHint(label: 'Round'),
          },
        ),
        id: 'line_5a69b8e2',
        create: () => Line2DComponent(end: const Offset(100, 0)),
        extent: const _LineExtent(),
        fields: [
          SchemaField(
            name: 'startX',
            kind: FieldTypes.decimal,
            read: (c) => (c as Line2DComponent).start.dx,
            write: (c, v) {
              final l = c as Line2DComponent;
              l.start = Offset((v as num).toDouble(), l.start.dy);
            },
          ),
          SchemaField(
            name: 'startY',
            kind: FieldTypes.decimal,
            read: (c) => (c as Line2DComponent).start.dy,
            write: (c, v) {
              final l = c as Line2DComponent;
              l.start = Offset(l.start.dx, (v as num).toDouble());
            },
          ),
          SchemaField(
            name: 'endX',
            kind: FieldTypes.decimal,
            read: (c) => (c as Line2DComponent).end.dx,
            write: (c, v) {
              final l = c as Line2DComponent;
              l.end = Offset((v as num).toDouble(), l.end.dy);
            },
          ),
          SchemaField(
            name: 'endY',
            kind: FieldTypes.decimal,
            read: (c) => (c as Line2DComponent).end.dy,
            write: (c, v) {
              final l = c as Line2DComponent;
              l.end = Offset(l.end.dx, (v as num).toDouble());
            },
          ),
          SchemaField(
            name: 'strokeColor',
            kind: FieldTypes.shapePaintStyle,
            read: (c) => (c as Line2DComponent).strokeStyle,
            write: (c, v) =>
                (c as Line2DComponent).strokeStyle = v as ShapePaintStyle,
          ),
          SchemaField(
            name: 'strokeW',
            kind: FieldTypes.decimal,
            read: (c) => (c as Line2DComponent).strokeWidth,
            write: (c, v) =>
                (c as Line2DComponent).strokeWidth = (v as num).toDouble(),
            min: 0.0,
          ),
          SchemaField(
            name: 'roundCaps',
            kind: FieldTypes.boolean,
            read: (c) => (c as Line2DComponent).roundCaps,
            write: (c, v) => (c as Line2DComponent).roundCaps = v as bool,
          ),
        ],
      );

  /// [Polygon2DComponent], from `polygon_editor_component.dart`.
  static ComponentSchema<Polygon2DComponent> get polygon =>
      ComponentSchema<Polygon2DComponent>(
        type: 'Polygon2DComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Polygon',
          group: 'Rendering',
          icon: Icons.pentagon_outlined,
          accentColor: Color(0xFF42A5F5),
          fieldGroups: {
            'Shape': ['vertCount', 'vertices'],
            'Appearance': ['filled', 'fillColor', 'strokeColor', 'strokeW'],
          },
          fields: {
            'vertCount': FieldHint(label: 'Verts', editable: false),
            'vertices': FieldHint(label: 'Vertices'),
            'filled': FieldHint(label: 'Filled'),
            'fillColor': FieldHint(label: 'Fill'),
            'strokeColor': FieldHint(label: 'Stroke Color'),
            'strokeW': FieldHint(
              label: 'Stroke',
              scrub: ScrubHint(step: 0.5, fractionDigits: 1),
            ),
          },
        ),
        id: 'polygon_671a97e0',
        create: () => Polygon2DComponent(
          vertices: const [
            Offset(-32, -32),
            Offset(32, -32),
            Offset(32, 32),
            Offset(-32, 32),
          ],
        ),
        extent: const _PolygonExtent(),
        fields: [
          SchemaField(
            name: 'vertCount',
            kind: FieldTypes.integer,
            read: (c) => (c as Polygon2DComponent).vertices.length,
          ),
          // The shape itself. The descriptor this schema was transcribed from
          // saved only the count, so every polygon reloaded as the default
          // square. A file without this key still loads that way.
          SchemaField(
            name: 'vertices',
            kind: FieldTypes.offsetList,
            read: (c) => (c as Polygon2DComponent).vertices,
            write: (c, v) => (c as Polygon2DComponent).vertices = (v as List)
                .cast<Offset>()
                .toList(),
          ),
          SchemaField(
            name: 'filled',
            kind: FieldTypes.boolean,
            read: (c) => (c as Polygon2DComponent).filled,
            write: (c, v) => (c as Polygon2DComponent).filled = v as bool,
          ),
          SchemaField(
            name: 'fillColor',
            kind: FieldTypes.shapePaintStyle,
            read: (c) => (c as Polygon2DComponent).fillStyle,
            write: (c, v) =>
                (c as Polygon2DComponent).fillStyle = v as ShapePaintStyle,
          ),
          SchemaField(
            name: 'strokeColor',
            kind: FieldTypes.shapePaintStyle,
            read: (c) => (c as Polygon2DComponent).strokeStyle,
            write: (c, v) =>
                (c as Polygon2DComponent).strokeStyle = v as ShapePaintStyle,
          ),
          SchemaField(
            name: 'strokeW',
            kind: FieldTypes.decimal,
            read: (c) => (c as Polygon2DComponent).strokeWidth,
            write: (c, v) =>
                (c as Polygon2DComponent).strokeWidth = (v as num).toDouble(),
            min: 0.0,
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [
    rectangle,
    circle,
    capsule,
    line,
    polygon,
  ];
}

class _RectangleExtent extends ComponentExtent {
  const _RectangleExtent();
  @override
  Size? sizeOf(Component c) =>
      Size((c as Rectangle2DComponent).width, c.height);
  @override
  bool scale(Component c, double sx, double sy) {
    (c as Rectangle2DComponent)
      ..width = (c.width * sx).abs().clamp(1, double.infinity)
      ..height = (c.height * sy).abs().clamp(1, double.infinity);
    return true;
  }
}

class _CircleExtent extends ComponentExtent {
  const _CircleExtent();
  @override
  Size? sizeOf(Component c) => Size.square((c as Circle2DComponent).radius * 2);
  @override
  bool scale(Component c, double sx, double sy) {
    final k = sx < sy ? sx : sy;
    (c as Circle2DComponent).radius = (c.radius * k).abs().clamp(
      0.5,
      double.infinity,
    );
    return true;
  }
}

class _CapsuleExtent extends ComponentExtent {
  const _CapsuleExtent();
  @override
  Size? sizeOf(Component c) => Size((c as Capsule2DComponent).width, c.height);
  @override
  bool scale(Component c, double sx, double sy) {
    (c as Capsule2DComponent)
      ..width = (c.width * sx).abs().clamp(1, double.infinity)
      ..height = (c.height * sy).abs().clamp(1, double.infinity);
    return true;
  }
}

/// A line's size is the box its endpoints span; scaling moves them about
/// their midpoint.
class _LineExtent extends ComponentExtent {
  const _LineExtent();

  @override
  Size? sizeOf(Component component) {
    final line = component as Line2DComponent;
    return Rect.fromPoints(line.start, line.end).size;
  }

  @override
  bool scale(Component component, double sx, double sy) {
    final line = component as Line2DComponent;
    final mid = (line.start + line.end) / 2;
    Offset about(Offset p) =>
        Offset(mid.dx + (p.dx - mid.dx) * sx, mid.dy + (p.dy - mid.dy) * sy);
    line
      ..start = about(line.start)
      ..end = about(line.end);
    return true;
  }
}

/// A polygon's size is its vertices' bounds; scaling moves the vertices.
class _PolygonExtent extends ComponentExtent {
  const _PolygonExtent();

  @override
  Size? sizeOf(Component component) {
    final vertices = (component as Polygon2DComponent).vertices;
    if (vertices.isEmpty) return null;
    var bounds = Rect.fromPoints(vertices.first, vertices.first);
    for (final v in vertices) {
      bounds = bounds.expandToInclude(Rect.fromPoints(v, v));
    }
    return bounds.size;
  }

  @override
  bool scale(Component component, double sx, double sy) {
    final polygon = component as Polygon2DComponent;
    polygon.vertices = [
      for (final v in polygon.vertices) Offset(v.dx * sx, v.dy * sy),
    ];
    return true;
  }
}
