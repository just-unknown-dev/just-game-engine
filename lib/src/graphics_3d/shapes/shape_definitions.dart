import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:just_game_engine/just_game_engine.dart';

import 'primitive_3d.dart';
import 'shape_components.dart';

/// How the 3-D shapes are saved and shown in an editor. Each is a 3-D
/// component (`Dimensions.threeD`) in the `3D Shapes` group: its sizes, its
/// detail, then its material.
abstract final class ShapeSchemas {
  /// [Cube3D].
  static ComponentSchema<Cube3D> get cube => _schema<Cube3D>(
    type: 'Cube3D',
    id: 'cube_3d_7e8d7b54',
    create: Cube3D.new,
    name: 'Cube',
    description: 'A box: width, height and depth.',
    icon: Icons.view_in_ar_outlined,
    size: [
      _size<Cube3D>('width', (c) => c.width, (c, v) => c.width = v),
      _size<Cube3D>('height', (c) => c.height, (c, v) => c.height = v),
      _size<Cube3D>('depth', (c) => c.depth, (c, v) => c.depth = v),
    ],
    rows: const [
      FieldRowHint('Size', {'width': 'W', 'height': 'H', 'depth': 'D'}),
    ],
  );

  /// [Sphere3D].
  static ComponentSchema<Sphere3D> get sphere => _schema<Sphere3D>(
    type: 'Sphere3D',
    id: 'sphere_3d_89734a64',
    create: Sphere3D.new,
    name: 'Sphere',
    description: 'A ball.',
    icon: Icons.circle_outlined,
    size: [_size<Sphere3D>('radius', (c) => c.radius, (c, v) => c.radius = v)],
    detail: [
      _count<Sphere3D>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        3,
        128,
      ),
      _count<Sphere3D>('rings', (c) => c.rings, (c, v) => c.rings = v, 2, 64),
      _flag<Sphere3D>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
    ],
  );

  /// [Plane3D].
  static ComponentSchema<Plane3D> get plane => _schema<Plane3D>(
    type: 'Plane3D',
    id: 'plane_3d_565609c7',
    create: Plane3D.new,
    name: 'Plane',
    description: 'A flat rectangle on the ground, seen from both sides.',
    icon: Icons.crop_landscape_outlined,
    size: [
      _size<Plane3D>('width', (c) => c.width, (c, v) => c.width = v),
      _size<Plane3D>('depth', (c) => c.depth, (c, v) => c.depth = v),
    ],
    rows: const [
      FieldRowHint('Size', {'width': 'W', 'depth': 'D'}),
    ],
  );

  /// [Cylinder3D].
  static ComponentSchema<Cylinder3D> get cylinder => _schema<Cylinder3D>(
    type: 'Cylinder3D',
    id: 'cylinder_3d_0b49d83d',
    create: Cylinder3D.new,
    name: 'Cylinder',
    description: 'An upright cylinder.',
    icon: Icons.storage_outlined,
    size: [
      _size<Cylinder3D>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _size<Cylinder3D>('height', (c) => c.height, (c, v) => c.height = v),
    ],
    detail: [
      _count<Cylinder3D>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        3,
        128,
      ),
      _flag<Cylinder3D>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
    ],
  );

  /// [Capsule3D].
  static ComponentSchema<Capsule3D> get capsule => _schema<Capsule3D>(
    type: 'Capsule3D',
    id: 'capsule_3d_e6fcb787',
    create: Capsule3D.new,
    name: 'Capsule',
    description: 'An upright capsule: a cylinder with round ends.',
    icon: Icons.medication_outlined,
    size: [
      _size<Capsule3D>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _size<Capsule3D>('height', (c) => c.height, (c, v) => c.height = v),
    ],
    detail: [
      _count<Capsule3D>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        3,
        128,
      ),
      _count<Capsule3D>('rings', (c) => c.rings, (c, v) => c.rings = v, 1, 32),
      _flag<Capsule3D>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
    ],
    hints: const {
      'height': FieldHint(
        label: 'Height',
        description: 'Its whole height, ends included.',
      ),
    },
  );

  /// [Cone3D].
  static ComponentSchema<Cone3D> get cone => _schema<Cone3D>(
    type: 'Cone3D',
    id: 'cone_3d_562bc28a',
    create: Cone3D.new,
    name: 'Cone',
    description: 'A cone, its tip up.',
    icon: Icons.change_history,
    size: [
      _size<Cone3D>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _size<Cone3D>('height', (c) => c.height, (c, v) => c.height = v),
    ],
    detail: [
      _count<Cone3D>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        3,
        128,
      ),
      _flag<Cone3D>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
    ],
  );

  /// [Torus3D].
  static ComponentSchema<Torus3D> get torus => _schema<Torus3D>(
    type: 'Torus3D',
    id: 'torus_3d_8fcf8d1e',
    create: Torus3D.new,
    name: 'Torus',
    description: 'A ring lying flat.',
    icon: Icons.donut_large,
    size: [
      _size<Torus3D>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _size<Torus3D>(
        'tubeRadius',
        (c) => c.tubeRadius,
        (c, v) => c.tubeRadius = v,
      ),
    ],
    detail: [
      _count<Torus3D>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        3,
        128,
      ),
      _count<Torus3D>('sides', (c) => c.sides, (c, v) => c.sides = v, 3, 64),
      _flag<Torus3D>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
    ],
    hints: const {
      'radius': FieldHint(
        label: 'Radius',
        description: 'To the middle of the tube.',
        scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm'),
      ),
      'tubeRadius': FieldHint(
        label: 'Tube',
        scrub: ScrubHint(step: 0.01, fractionDigits: 2, suffix: 'm'),
      ),
    },
  );

  /// [Ramp3D].
  static ComponentSchema<Ramp3D> get ramp => _schema<Ramp3D>(
    type: 'Ramp3D',
    id: 'ramp_3d_7923bada',
    create: Ramp3D.new,
    name: 'Ramp',
    description: 'A wedge rising towards +Z, to walk up.',
    icon: Icons.trending_up,
    size: [
      _size<Ramp3D>('width', (c) => c.width, (c, v) => c.width = v),
      _size<Ramp3D>('height', (c) => c.height, (c, v) => c.height = v),
      _size<Ramp3D>('depth', (c) => c.depth, (c, v) => c.depth = v),
    ],
    rows: const [
      FieldRowHint('Size', {'width': 'W', 'height': 'H', 'depth': 'D'}),
    ],
  );

  /// [Stairs3D].
  static ComponentSchema<Stairs3D> get stairs => _schema<Stairs3D>(
    type: 'Stairs3D',
    id: 'stairs_3d_bc0b192f',
    create: Stairs3D.new,
    name: 'Stairs',
    description: 'A flight of solid steps rising towards +Z.',
    icon: Icons.stairs_outlined,
    size: [
      _size<Stairs3D>('width', (c) => c.width, (c, v) => c.width = v),
      _size<Stairs3D>('height', (c) => c.height, (c, v) => c.height = v),
      _size<Stairs3D>('depth', (c) => c.depth, (c, v) => c.depth = v),
    ],
    detail: [
      _count<Stairs3D>('steps', (c) => c.steps, (c, v) => c.steps = v, 1, 64),
    ],
    rows: const [
      FieldRowHint('Size', {'width': 'W', 'height': 'H', 'depth': 'D'}),
    ],
  );

  /// [Arch3D].
  static ComponentSchema<Arch3D> get arch => _schema<Arch3D>(
    type: 'Arch3D',
    id: 'arch_3d_a19df39b',
    create: Arch3D.new,
    name: 'Arch',
    description:
        'A curved band standing up: an arch, a bridge, part of a ring.',
    icon: Icons.architecture,
    size: [
      _size<Arch3D>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _size<Arch3D>('thickness', (c) => c.thickness, (c, v) => c.thickness = v),
      _size<Arch3D>('depth', (c) => c.depth, (c, v) => c.depth = v),
      SchemaField(
        name: 'angle',
        kind: FieldTypes.decimal,
        read: (c) => (c as Arch3D).angle,
        write: (c, v) => (c as Arch3D).angle = (v as num).toDouble(),
        min: 0.01,
        max: 2 * math.pi,
      ),
    ],
    detail: [
      _count<Arch3D>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        1,
        128,
      ),
      _flag<Arch3D>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
    ],
    hints: const {
      'radius': FieldHint(
        label: 'Radius',
        description: 'Its outside radius.',
        scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm'),
      ),
      'angle': FieldHint(
        label: 'Angle',
        description: 'How much of a ring it is: 180° stands on two feet.',
        unit: AngleUnit.degrees,
        scrub: ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
      ),
    },
  );

  /// [Polygon3D].
  static ComponentSchema<Polygon3D> get polygon => _schema<Polygon3D>(
    type: 'Polygon3D',
    id: 'polygon_3d_54238989',
    create: Polygon3D.new,
    name: 'Polygon',
    description: 'An outline on the ground, raised to a height.',
    icon: Icons.hexagon_outlined,
    size: [
      SchemaField(
        name: 'points',
        kind: FieldTypes.offsetList,
        read: (c) => (c as Polygon3D).points,
        write: (c, v) =>
            (c as Polygon3D).points = (v as List).cast<Offset>().toList(),
      ),
      _size<Polygon3D>('height', (c) => c.height, (c, v) => c.height = v),
    ],
    hints: const {
      'points': FieldHint(
        label: 'Points',
        description: 'Its corners, in order round it: x and z on the ground.',
      ),
    },
  );

  /// Every 3-D shape.
  static List<ComponentSchema> get all => [
    cube,
    sphere,
    plane,
    cylinder,
    capsule,
    cone,
    torus,
    ramp,
    stairs,
    arch,
    polygon,
  ];

  /// The material's fields, in the order the inspector shows them.
  static const List<String> materialFields = [
    'color',
    'metallic',
    'roughness',
    'emission',
    'emissionStrength',
    'opacity',
    'unlit',
    'texture',
    'tiling',
    'tileInMetres',
  ];

  static ComponentSchema<T> _schema<T extends Primitive3D>({
    required String type,
    required String id,
    required T Function() create,
    required String name,
    required String description,
    required IconData icon,
    required List<SchemaField> size,
    List<SchemaField> detail = const [],
    List<FieldRowHint> rows = const [],
    Map<String, FieldHint> hints = const {},
  }) => ComponentSchema<T>(
    type: type,
    id: id,
    create: create,
    extent: const _PrimitiveExtent(),
    hints: ComponentHints(
      dimensions: Dimensions.threeD,
      name: name,
      group: '3D Shapes',
      description: description,
      icon: icon,
      accentColor: const Color(0xFF26A69A),
      fieldGroups: {
        'Size': [for (final f in size) f.name],
        if (detail.isNotEmpty) 'Detail': [for (final f in detail) f.name],
        'Material': materialFields,
        'Drawing': const ['castShadows', 'visible'],
      },
      foldedGroups: const {'Detail', 'Drawing'},
      fieldRows: rows,
      fields: {
        ..._sizeHints(size),
        ..._detailHints,
        ..._materialHints,
        ...hints,
      },
    ),
    fields: [...size, ...detail, ..._material],
  );

  static Map<String, FieldHint> _sizeHints(List<SchemaField> size) => {
    for (final f in size)
      if (f.kind == FieldTypes.decimal)
        f.name: FieldHint(
          label: switch (f.name) {
            'width' => 'W',
            'height' => 'H',
            'depth' => 'D',
            _ => '${f.name[0].toUpperCase()}${f.name.substring(1)}',
          },
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm'),
        ),
  };

  static Map<String, FieldHint> get _detailHints => const {
    'segments': FieldHint(
      label: 'Segments',
      scrub: ScrubHint(integer: true, fractionDigits: 0, pixelsPerStep: 6),
    ),
    'rings': FieldHint(
      label: 'Rings',
      scrub: ScrubHint(integer: true, fractionDigits: 0, pixelsPerStep: 6),
    ),
    'sides': FieldHint(
      label: 'Sides',
      scrub: ScrubHint(integer: true, fractionDigits: 0, pixelsPerStep: 6),
    ),
    'steps': FieldHint(
      label: 'Steps',
      scrub: ScrubHint(integer: true, fractionDigits: 0, pixelsPerStep: 12),
    ),
    'smooth': FieldHint(
      label: 'Smooth',
      description: 'Shaded smooth, or faceted for a low-poly look.',
    ),
  };

  static Map<String, FieldHint> get _materialHints => {
    'color': const FieldHint(label: 'Colour'),
    'metallic': const FieldHint(
      label: 'Metallic',
      slider: true,
      scrub: ScrubHint(step: 0.01, fractionDigits: 2),
    ),
    'roughness': const FieldHint(
      label: 'Roughness',
      slider: true,
      scrub: ScrubHint(step: 0.01, fractionDigits: 2),
    ),
    'emission': const FieldHint(
      label: 'Glow',
      description: 'The light it gives off itself; black for none.',
    ),
    'emissionStrength': FieldHint(
      label: 'Glow strength',
      scrub: const ScrubHint(step: 0.1, fractionDigits: 1),
      visibleWhen: (c) =>
          (c as Primitive3D).emission.toARGB32() & 0xFFFFFF != 0,
    ),
    'opacity': const FieldHint(
      label: 'Opacity',
      slider: true,
      scrub: ScrubHint(step: 0.01, fractionDigits: 2),
    ),
    'unlit': const FieldHint(
      label: 'Unlit',
      description: 'Its colour as it is, with no light or shade.',
    ),
    'texture': const FieldHint(
      label: 'Texture',
      fileExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    ),
    'tiling': FieldHint(
      label: 'Tiling',
      visibleWhen: (c) => (c as Primitive3D).texture.isNotEmpty,
    ),
    'tileInMetres': FieldHint(
      label: 'Tile per metre',
      description:
          'Tiling counts repeats per metre of the world, so the texture keeps its scale on any size.',
      visibleWhen: (c) => (c as Primitive3D).texture.isNotEmpty,
    ),
    'castShadows': const FieldHint(label: 'Casts shadows'),
    'visible': const FieldHint(label: 'Visible'),
  };

  static List<SchemaField> get _material => [
    SchemaField(
      name: 'color',
      kind: FieldTypes.color,
      read: (c) => (c as Primitive3D).color,
      write: (c, v) => (c as Primitive3D).color = v as Color,
    ),
    _unit('metallic', (c) => c.metallic, (c, v) => c.metallic = v),
    _unit('roughness', (c) => c.roughness, (c, v) => c.roughness = v),
    SchemaField(
      name: 'emission',
      kind: FieldTypes.color,
      read: (c) => (c as Primitive3D).emission,
      write: (c, v) => (c as Primitive3D).emission = v as Color,
    ),
    SchemaField(
      name: 'emissionStrength',
      kind: FieldTypes.decimal,
      read: (c) => (c as Primitive3D).emissionStrength,
      write: (c, v) =>
          (c as Primitive3D).emissionStrength = (v as num).toDouble(),
      min: 0,
    ),
    _unit('opacity', (c) => c.opacity, (c, v) => c.opacity = v),
    _flag<Primitive3D>('unlit', (c) => c.unlit, (c, v) => c.unlit = v),
    SchemaField(
      name: 'texture',
      kind: FieldTypes.assetRef,
      read: (c) => (c as Primitive3D).texture,
      write: (c, v) => (c as Primitive3D).texture = v as String? ?? '',
    ),
    SchemaField(
      name: 'tiling',
      kind: FieldTypes.vector2,
      read: (c) => (c as Primitive3D).tiling,
      write: (c, v) => (c as Primitive3D).tiling = v is Vector2
          ? Vector2.copy(v)
          : Vector2(1, 1),
    ),
    _flag<Primitive3D>(
      'tileInMetres',
      (c) => c.tileInMetres,
      (c, v) => c.tileInMetres = v,
    ),
    _flag<Primitive3D>(
      'castShadows',
      (c) => c.castShadows,
      (c, v) => c.castShadows = v,
    ),
    _flag<Primitive3D>('visible', (c) => c.visible, (c, v) => c.visible = v),
  ];

  static SchemaField _size<T extends Primitive3D>(
    String name,
    double Function(T c) read,
    void Function(T c, double v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toDouble()),
    min: 0.01,
  );

  static SchemaField _unit(
    String name,
    double Function(Primitive3D c) read,
    void Function(Primitive3D c, double v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as Primitive3D),
    write: (c, v) =>
        write(c as Primitive3D, (v as num).toDouble().clamp(0.0, 1.0)),
    min: 0,
    max: 1,
  );

  static SchemaField _count<T extends Primitive3D>(
    String name,
    int Function(T c) read,
    void Function(T c, int v) write,
    int min,
    int max,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.integer,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toInt().clamp(min, max)),
    min: min.toDouble(),
    max: max.toDouble(),
  );

  static SchemaField _flag<T extends Primitive3D>(
    String name,
    bool Function(T c) read,
    void Function(T c, bool v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as bool),
  );
}

/// A shape's size is its own bounds.
final class _PrimitiveExtent extends ComponentExtent {
  const _PrimitiveExtent();

  @override
  Size? sizeOf(Component component) {
    final b = Aabb3();
    (component as Primitive3D).boundsInto(b);
    return Size(b.max.x - b.min.x, b.max.y - b.min.y);
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    (component as Primitive3D).boundsInto(out);
    return true;
  }
}
