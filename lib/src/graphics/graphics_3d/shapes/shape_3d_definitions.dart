import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:just_dart/just_dart.dart' show Aabb3, Vector2;

import '../../../ecs/ecs.dart';
import '../../../foundation/dimensions.dart';
import 'primitive_3d_component.dart';
import 'shape_3d_components.dart';

/// How the 3-D shapes are saved and shown in an editor. Each is a 3-D
/// component (`Dimensions.threeD`) in the `3D Shapes` group: its sizes, its
/// detail, then its material.
abstract final class Shape3DDefinitions {
  /// [Cube3DComponent].
  static ComponentDefinition<Cube3DComponent>
  get cube => _definition<Cube3DComponent>(
    type: 'Cube3DComponent',
    id: 'cube_3d_7e8d7b54',
    create: Cube3DComponent.new,
    name: 'Cube',
    description: 'A box: width, height and depth.',
    icon: Icons.view_in_ar_outlined,
    size: [
      _size<Cube3DComponent>('width', (c) => c.width, (c, v) => c.width = v),
      _size<Cube3DComponent>('height', (c) => c.height, (c, v) => c.height = v),
      _size<Cube3DComponent>('depth', (c) => c.depth, (c, v) => c.depth = v),
    ],
    rows: const [
      FieldRowHint('Size', {'width': 'W', 'height': 'H', 'depth': 'D'}),
    ],
  );

  /// [Sphere3DComponent].
  static ComponentDefinition<Sphere3DComponent> get sphere =>
      _definition<Sphere3DComponent>(
        type: 'Sphere3DComponent',
        id: 'sphere_3d_89734a64',
        create: Sphere3DComponent.new,
        name: 'Sphere',
        description: 'A ball.',
        icon: Icons.circle_outlined,
        size: [
          _size<Sphere3DComponent>(
            'radius',
            (c) => c.radius,
            (c, v) => c.radius = v,
          ),
        ],
        detail: [
          _count<Sphere3DComponent>(
            'segments',
            (c) => c.segments,
            (c, v) => c.segments = v,
            3,
            128,
          ),
          _count<Sphere3DComponent>(
            'rings',
            (c) => c.rings,
            (c, v) => c.rings = v,
            2,
            64,
          ),
          _flag<Sphere3DComponent>(
            'smooth',
            (c) => c.smooth,
            (c, v) => c.smooth = v,
          ),
        ],
      );

  /// [Plane3DComponent].
  static ComponentDefinition<Plane3DComponent> get plane =>
      _definition<Plane3DComponent>(
        type: 'Plane3DComponent',
        id: 'plane_3d_565609c7',
        create: Plane3DComponent.new,
        name: 'Plane',
        description: 'A flat rectangle on the ground, seen from both sides.',
        icon: Icons.crop_landscape_outlined,
        size: [
          _size<Plane3DComponent>(
            'width',
            (c) => c.width,
            (c, v) => c.width = v,
          ),
          _size<Plane3DComponent>(
            'depth',
            (c) => c.depth,
            (c, v) => c.depth = v,
          ),
        ],
        rows: const [
          FieldRowHint('Size', {'width': 'W', 'depth': 'D'}),
        ],
      );

  /// [Cylinder3DComponent].
  static ComponentDefinition<Cylinder3DComponent> get cylinder =>
      _definition<Cylinder3DComponent>(
        type: 'Cylinder3DComponent',
        id: 'cylinder_3d_0b49d83d',
        create: Cylinder3DComponent.new,
        name: 'Cylinder',
        description: 'An upright cylinder.',
        icon: Icons.storage_outlined,
        size: [
          _size<Cylinder3DComponent>(
            'radius',
            (c) => c.radius,
            (c, v) => c.radius = v,
          ),
          _size<Cylinder3DComponent>(
            'height',
            (c) => c.height,
            (c, v) => c.height = v,
          ),
        ],
        detail: [
          _count<Cylinder3DComponent>(
            'segments',
            (c) => c.segments,
            (c, v) => c.segments = v,
            3,
            128,
          ),
          _flag<Cylinder3DComponent>(
            'smooth',
            (c) => c.smooth,
            (c, v) => c.smooth = v,
          ),
        ],
      );

  /// [Capsule3DComponent].
  static ComponentDefinition<Capsule3DComponent> get capsule =>
      _definition<Capsule3DComponent>(
        type: 'Capsule3DComponent',
        id: 'capsule_3d_e6fcb787',
        create: Capsule3DComponent.new,
        name: 'Capsule',
        description: 'An upright capsule: a cylinder with round ends.',
        icon: Icons.medication_outlined,
        size: [
          _size<Capsule3DComponent>(
            'radius',
            (c) => c.radius,
            (c, v) => c.radius = v,
          ),
          _size<Capsule3DComponent>(
            'height',
            (c) => c.height,
            (c, v) => c.height = v,
          ),
        ],
        detail: [
          _count<Capsule3DComponent>(
            'segments',
            (c) => c.segments,
            (c, v) => c.segments = v,
            3,
            128,
          ),
          _count<Capsule3DComponent>(
            'rings',
            (c) => c.rings,
            (c, v) => c.rings = v,
            1,
            32,
          ),
          _flag<Capsule3DComponent>(
            'smooth',
            (c) => c.smooth,
            (c, v) => c.smooth = v,
          ),
        ],
        hints: const {
          'height': FieldHint(
            label: 'Height',
            description: 'Its whole height, ends included.',
          ),
        },
      );

  /// [Cone3DComponent].
  static ComponentDefinition<Cone3DComponent>
  get cone => _definition<Cone3DComponent>(
    type: 'Cone3DComponent',
    id: 'cone_3d_562bc28a',
    create: Cone3DComponent.new,
    name: 'Cone',
    description: 'A cone, its tip up.',
    icon: Icons.change_history,
    size: [
      _size<Cone3DComponent>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _size<Cone3DComponent>('height', (c) => c.height, (c, v) => c.height = v),
    ],
    detail: [
      _count<Cone3DComponent>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        3,
        128,
      ),
      _flag<Cone3DComponent>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
    ],
  );

  /// [Torus3DComponent].
  static ComponentDefinition<Torus3DComponent> get torus =>
      _definition<Torus3DComponent>(
        type: 'Torus3DComponent',
        id: 'torus_3d_8fcf8d1e',
        create: Torus3DComponent.new,
        name: 'Torus',
        description: 'A ring lying flat.',
        icon: Icons.donut_large,
        size: [
          _size<Torus3DComponent>(
            'radius',
            (c) => c.radius,
            (c, v) => c.radius = v,
          ),
          _size<Torus3DComponent>(
            'tubeRadius',
            (c) => c.tubeRadius,
            (c, v) => c.tubeRadius = v,
          ),
        ],
        detail: [
          _count<Torus3DComponent>(
            'segments',
            (c) => c.segments,
            (c, v) => c.segments = v,
            3,
            128,
          ),
          _count<Torus3DComponent>(
            'sides',
            (c) => c.sides,
            (c, v) => c.sides = v,
            3,
            64,
          ),
          _flag<Torus3DComponent>(
            'smooth',
            (c) => c.smooth,
            (c, v) => c.smooth = v,
          ),
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

  /// [Ramp3DComponent].
  static ComponentDefinition<Ramp3DComponent>
  get ramp => _definition<Ramp3DComponent>(
    type: 'Ramp3DComponent',
    id: 'ramp_3d_7923bada',
    create: Ramp3DComponent.new,
    name: 'Ramp',
    description: 'A wedge rising towards +Z, to walk up.',
    icon: Icons.trending_up,
    size: [
      _size<Ramp3DComponent>('width', (c) => c.width, (c, v) => c.width = v),
      _size<Ramp3DComponent>('height', (c) => c.height, (c, v) => c.height = v),
      _size<Ramp3DComponent>('depth', (c) => c.depth, (c, v) => c.depth = v),
    ],
    rows: const [
      FieldRowHint('Size', {'width': 'W', 'height': 'H', 'depth': 'D'}),
    ],
  );

  /// [Stairs3DComponent].
  static ComponentDefinition<Stairs3DComponent> get stairs =>
      _definition<Stairs3DComponent>(
        type: 'Stairs3DComponent',
        id: 'stairs_3d_bc0b192f',
        create: Stairs3DComponent.new,
        name: 'Stairs',
        description: 'A flight of solid steps rising towards +Z.',
        icon: Icons.stairs_outlined,
        size: [
          _size<Stairs3DComponent>(
            'width',
            (c) => c.width,
            (c, v) => c.width = v,
          ),
          _size<Stairs3DComponent>(
            'height',
            (c) => c.height,
            (c, v) => c.height = v,
          ),
          _size<Stairs3DComponent>(
            'depth',
            (c) => c.depth,
            (c, v) => c.depth = v,
          ),
        ],
        detail: [
          _count<Stairs3DComponent>(
            'steps',
            (c) => c.steps,
            (c, v) => c.steps = v,
            1,
            64,
          ),
        ],
        rows: const [
          FieldRowHint('Size', {'width': 'W', 'height': 'H', 'depth': 'D'}),
        ],
      );

  /// [Arch3DComponent].
  static ComponentDefinition<Arch3DComponent>
  get arch => _definition<Arch3DComponent>(
    type: 'Arch3DComponent',
    id: 'arch_3d_a19df39b',
    create: Arch3DComponent.new,
    name: 'Arch',
    description:
        'A curved band standing up: an arch, a bridge, part of a ring.',
    icon: Icons.architecture,
    size: [
      _size<Arch3DComponent>('radius', (c) => c.radius, (c, v) => c.radius = v),
      _size<Arch3DComponent>(
        'thickness',
        (c) => c.thickness,
        (c, v) => c.thickness = v,
      ),
      _size<Arch3DComponent>('depth', (c) => c.depth, (c, v) => c.depth = v),
      FieldDefinition(
        name: 'angle',
        kind: FieldTypes.decimal,
        read: (c) => (c as Arch3DComponent).angle,
        write: (c, v) => (c as Arch3DComponent).angle = (v as num).toDouble(),
        min: 0.01,
        max: 2 * math.pi,
      ),
    ],
    detail: [
      _count<Arch3DComponent>(
        'segments',
        (c) => c.segments,
        (c, v) => c.segments = v,
        1,
        128,
      ),
      _flag<Arch3DComponent>('smooth', (c) => c.smooth, (c, v) => c.smooth = v),
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

  /// [Polygon3DComponent].
  static ComponentDefinition<Polygon3DComponent> get polygon =>
      _definition<Polygon3DComponent>(
        type: 'Polygon3DComponent',
        id: 'polygon_3d_54238989',
        create: Polygon3DComponent.new,
        name: 'Polygon',
        description: 'An outline on the ground, raised to a height.',
        icon: Icons.hexagon_outlined,
        size: [
          FieldDefinition(
            name: 'points',
            kind: FieldTypes.offsetList,
            read: (c) => (c as Polygon3DComponent).points,
            write: (c, v) => (c as Polygon3DComponent).points = (v as List)
                .cast<Offset>()
                .toList(),
          ),
          _size<Polygon3DComponent>(
            'height',
            (c) => c.height,
            (c, v) => c.height = v,
          ),
        ],
        hints: const {
          'points': FieldHint(
            label: 'Points',
            description:
                'Its corners, in order round it: x and z on the ground.',
          ),
        },
      );

  /// Every 3-D shape.
  static List<ComponentDefinition> get all => [
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
    'material',
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

  static ComponentDefinition<T> _definition<T extends Primitive3DComponent>({
    required String type,
    required String id,
    required T Function() create,
    required String name,
    required String description,
    required IconData icon,
    required List<FieldDefinition> size,
    List<FieldDefinition> detail = const [],
    List<FieldRowHint> rows = const [],
    Map<String, FieldHint> hints = const {},
  }) => ComponentDefinition<T>(
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

  static Map<String, FieldHint> _sizeHints(List<FieldDefinition> size) => {
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

  // Its own look: shown while it has no material file.
  static bool _ownLook(Component c) =>
      (c as Primitive3DComponent).material.isEmpty;

  static bool _textured(Component c) =>
      _ownLook(c) && (c as Primitive3DComponent).texture.isNotEmpty;

  static Map<String, FieldHint> get _materialHints => {
    'material': const FieldHint(
      label: 'Material',
      description:
          'A material file shared with everything drawn with it; empty for '
          'its own colour and texture below.',
      fileExtensions: ['material.json'],
    ),
    'color': const FieldHint(label: 'Colour', visibleWhen: _ownLook),
    'metallic': const FieldHint(
      label: 'Metallic',
      slider: true,
      scrub: ScrubHint(step: 0.01, fractionDigits: 2),
      visibleWhen: _ownLook,
    ),
    'roughness': const FieldHint(
      label: 'Roughness',
      slider: true,
      scrub: ScrubHint(step: 0.01, fractionDigits: 2),
      visibleWhen: _ownLook,
    ),
    'emission': const FieldHint(
      label: 'Glow',
      description: 'The light it gives off itself; black for none.',
      visibleWhen: _ownLook,
    ),
    'emissionStrength': FieldHint(
      label: 'Glow strength',
      scrub: const ScrubHint(step: 0.1, fractionDigits: 1),
      visibleWhen: (c) =>
          _ownLook(c) &&
          (c as Primitive3DComponent).emission.toARGB32() & 0xFFFFFF != 0,
    ),
    'opacity': const FieldHint(
      label: 'Opacity',
      slider: true,
      scrub: ScrubHint(step: 0.01, fractionDigits: 2),
      visibleWhen: _ownLook,
    ),
    'unlit': const FieldHint(
      label: 'Unlit',
      description: 'Its colour as it is, with no light or shade.',
      visibleWhen: _ownLook,
    ),
    'texture': const FieldHint(
      label: 'Texture',
      fileExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      visibleWhen: _ownLook,
    ),
    'tiling': const FieldHint(label: 'Tiling', visibleWhen: _textured),
    'tileInMetres': const FieldHint(
      label: 'Tile per metre',
      description:
          'Tiling counts repeats per metre of the world, so the texture keeps its scale on any size.',
      visibleWhen: _textured,
    ),
    'castShadows': const FieldHint(label: 'Casts shadows'),
    'visible': const FieldHint(label: 'Visible'),
  };

  static List<FieldDefinition> get _material => [
    FieldDefinition(
      name: 'material',
      kind: FieldTypes.assetRef,
      read: (c) => (c as Primitive3DComponent).material,
      write: (c, v) =>
          (c as Primitive3DComponent).material = v as String? ?? '',
    ),
    FieldDefinition(
      name: 'color',
      kind: FieldTypes.color,
      read: (c) => (c as Primitive3DComponent).color,
      write: (c, v) => (c as Primitive3DComponent).color = v as Color,
    ),
    _unit('metallic', (c) => c.metallic, (c, v) => c.metallic = v),
    _unit('roughness', (c) => c.roughness, (c, v) => c.roughness = v),
    FieldDefinition(
      name: 'emission',
      kind: FieldTypes.color,
      read: (c) => (c as Primitive3DComponent).emission,
      write: (c, v) => (c as Primitive3DComponent).emission = v as Color,
    ),
    FieldDefinition(
      name: 'emissionStrength',
      kind: FieldTypes.decimal,
      read: (c) => (c as Primitive3DComponent).emissionStrength,
      write: (c, v) =>
          (c as Primitive3DComponent).emissionStrength = (v as num).toDouble(),
      min: 0,
    ),
    _unit('opacity', (c) => c.opacity, (c, v) => c.opacity = v),
    _flag<Primitive3DComponent>('unlit', (c) => c.unlit, (c, v) => c.unlit = v),
    FieldDefinition(
      name: 'texture',
      kind: FieldTypes.assetRef,
      read: (c) => (c as Primitive3DComponent).texture,
      write: (c, v) => (c as Primitive3DComponent).texture = v as String? ?? '',
    ),
    FieldDefinition(
      name: 'tiling',
      kind: FieldTypes.vector2,
      read: (c) => (c as Primitive3DComponent).tiling,
      write: (c, v) => (c as Primitive3DComponent).tiling = v is Vector2
          ? Vector2.copy(v)
          : Vector2(1, 1),
    ),
    _flag<Primitive3DComponent>(
      'tileInMetres',
      (c) => c.tileInMetres,
      (c, v) => c.tileInMetres = v,
    ),
    _flag<Primitive3DComponent>(
      'castShadows',
      (c) => c.castShadows,
      (c, v) => c.castShadows = v,
    ),
    _flag<Primitive3DComponent>(
      'visible',
      (c) => c.visible,
      (c, v) => c.visible = v,
    ),
  ];

  static FieldDefinition _size<T extends Primitive3DComponent>(
    String name,
    double Function(T c) read,
    void Function(T c, double v) write,
  ) => FieldDefinition(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toDouble()),
    min: 0.01,
  );

  static FieldDefinition _unit(
    String name,
    double Function(Primitive3DComponent c) read,
    void Function(Primitive3DComponent c, double v) write,
  ) => FieldDefinition(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as Primitive3DComponent),
    write: (c, v) =>
        write(c as Primitive3DComponent, (v as num).toDouble().clamp(0.0, 1.0)),
    min: 0,
    max: 1,
  );

  static FieldDefinition _count<T extends Primitive3DComponent>(
    String name,
    int Function(T c) read,
    void Function(T c, int v) write,
    int min,
    int max,
  ) => FieldDefinition(
    name: name,
    kind: FieldTypes.integer,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toInt().clamp(min, max)),
    min: min.toDouble(),
    max: max.toDouble(),
  );

  static FieldDefinition _flag<T extends Primitive3DComponent>(
    String name,
    bool Function(T c) read,
    void Function(T c, bool v) write,
  ) => FieldDefinition(
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
    (component as Primitive3DComponent).boundsInto(b);
    return Size(b.max.x - b.min.x, b.max.y - b.min.y);
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    (component as Primitive3DComponent).boundsInto(out);
    return true;
  }
}
