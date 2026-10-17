import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:just_dart/just_dart.dart' show Aabb3;
import 'package:just_graphics_engine/assets.dart';

import '../../ecs/components/components.dart';
import 'outline.dart';
import 'primitive_3d.dart';

// The 3-D shapes. Plain data with no GPU imports, like the other 3-D
// components: a scene holding them loads everywhere. Sizes are metres, every
// shape is centred on its entity, +Y is down (up is −Y).

/// A box [width] × [height] × [depth]: a cube when they are equal.
class Cube3D extends Primitive3D {
  /// A box, 1 m each way by default.
  Cube3D({
    this.width = 1.0,
    this.height = 1.0,
    this.depth = 1.0,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Along X.
  double width;

  /// Along Y.
  double height;

  /// Along Z.
  double depth;

  @override
  String get shapeName => 'Cube';

  @override
  Object get shapeKey => ('cube', width, height, depth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(width)
    ..add(height)
    ..add(depth);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final hx = Primitive3D.size(width) / 2,
        hy = Primitive3D.size(height) / 2,
        hz = Primitive3D.size(depth) / 2;
    return (MeshBuilder(
      uv,
    )..box(-hx, -hy, -hz, hx, hy, hz, stretch: true)).build();
  }

  @override
  void boundsInto(Aabb3 out) {
    final hx = Primitive3D.size(width) / 2,
        hy = Primitive3D.size(height) / 2,
        hz = Primitive3D.size(depth) / 2;
    out.setValues(-hx, -hy, -hz, hx, hy, hz);
  }

  @override
  List<SolidPart> get solidParts => [
    SolidBox(
      Primitive3D.size(width) / 2,
      Primitive3D.size(height) / 2,
      Primitive3D.size(depth) / 2,
    ),
  ];
}

/// A flat rectangle [width] × [depth] lying on its entity's ground plane,
/// seen from both sides. Its collider is a slab 0.1 m thick just under it.
class Plane3D extends Primitive3D {
  /// A plane, 10 m each way by default.
  Plane3D({
    this.width = 10.0,
    this.depth = 10.0,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Along X.
  double width;

  /// Along Z.
  double depth;

  /// How thick its collider is, under its surface.
  static const double colliderThickness = 0.1;

  @override
  String get shapeName => 'Plane';

  @override
  bool get doubleSided => true;

  @override
  Object get shapeKey => ('plane', width, depth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(width)
    ..add(depth);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final hx = Primitive3D.size(width) / 2, hz = Primitive3D.size(depth) / 2;
    return (MeshBuilder(uv)..face(
          [(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz)],
          0,
          -1,
          0,
          stretch: true,
        ))
        .build();
  }

  @override
  void boundsInto(Aabb3 out) {
    final hx = Primitive3D.size(width) / 2, hz = Primitive3D.size(depth) / 2;
    out.setValues(-hx, 0, -hz, hx, 0, hz);
  }

  @override
  List<SolidPart> get solidParts => [
    SolidBox(
      Primitive3D.size(width) / 2,
      colliderThickness / 2,
      Primitive3D.size(depth) / 2,
      y: colliderThickness / 2,
    ),
  ];
}

/// A ball of [radius], [segments] round and [rings] from pole to pole.
class Sphere3D extends Primitive3D {
  /// A ball 1 m across by default.
  Sphere3D({
    this.radius = 0.5,
    this.segments = 32,
    this.rings = 16,
    this.smooth = true,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Its radius.
  double radius;

  /// Steps round it (3–128).
  int segments;

  /// Steps from top to bottom (2–64).
  int rings;

  /// Whether it is shaded smooth, or faceted.
  bool smooth;

  @override
  String get shapeName => 'Sphere';

  @override
  Object get shapeKey => ('sphere', radius, segments, rings, smooth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(radius)
    ..addInt(segments)
    ..addInt(rings)
    ..addBool(smooth);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final r = Primitive3D.size(radius);
    final n = Primitive3D.count(rings, 2, 64);
    final b = MeshBuilder(uv)
      ..lathe(
        [
          for (var j = 0; j <= n; j++)
            (
              r * math.sin(math.pi * j / n),
              -r * math.cos(math.pi * j / n),
              math.sin(math.pi * j / n),
              -math.cos(math.pi * j / n),
              uv.anyway(r * math.pi * j / n),
            ),
        ],
        Primitive3D.count(segments, 3, 128),
        aroundLength: uv.around(r),
        profileLength: uv.anyway(r * math.pi),
      );
    final mesh = b.build();
    return smooth ? mesh : mesh.faceted();
  }

  @override
  void boundsInto(Aabb3 out) {
    final r = Primitive3D.size(radius);
    out.setValues(-r, -r, -r, r, r, r);
  }

  @override
  List<SolidPart> get solidParts => [SolidSphere(Primitive3D.size(radius))];
}

/// An upright cylinder of [radius] and [height], [segments] round.
class Cylinder3D extends Primitive3D {
  /// A cylinder 1 m across and 1 m tall by default.
  Cylinder3D({
    this.radius = 0.5,
    this.height = 1.0,
    this.segments = 24,
    this.smooth = true,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Its radius.
  double radius;

  /// Its height.
  double height;

  /// Steps round it (3–128).
  int segments;

  /// Whether its side is shaded smooth, or faceted.
  bool smooth;

  @override
  String get shapeName => 'Cylinder';

  @override
  Object get shapeKey => ('cylinder', radius, height, segments, smooth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(radius)
    ..add(height)
    ..addInt(segments)
    ..addBool(smooth);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final r = Primitive3D.size(radius), hy = Primitive3D.size(height) / 2;
    final s = Primitive3D.count(segments, 3, 128);
    final side = uv.alongY(hy * 2);
    final b = MeshBuilder(uv)
      ..lathe(
        [(r, -hy, 1, 0, 0), (r, hy, 1, 0, side)],
        s,
        aroundLength: uv.around(r),
        profileLength: side,
      )
      ..disc(r, -hy, s, up: true)
      ..disc(r, hy, s, up: false);
    final mesh = b.build();
    return smooth ? mesh : mesh.faceted();
  }

  @override
  void boundsInto(Aabb3 out) {
    final r = Primitive3D.size(radius), hy = Primitive3D.size(height) / 2;
    out.setValues(-r, -hy, -r, r, hy, r);
  }

  @override
  List<SolidPart> get solidParts => [
    SolidCylinder(Primitive3D.size(height) / 2, Primitive3D.size(radius)),
  ];
}

/// An upright capsule: a cylinder with a half ball on each end, [height]
/// tall overall (never less than its width) and of [radius].
class Capsule3D extends Primitive3D {
  /// A capsule 1 m across and 2 m tall by default.
  Capsule3D({
    this.radius = 0.5,
    this.height = 2.0,
    this.segments = 24,
    this.rings = 8,
    this.smooth = true,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Its radius.
  double radius;

  /// Its whole height, ends included.
  double height;

  /// Steps round it (3–128).
  int segments;

  /// Steps over each end, from its side to its tip (1–32).
  int rings;

  /// Whether it is shaded smooth, or faceted.
  bool smooth;

  @override
  String get shapeName => 'Capsule';

  @override
  Object get shapeKey => ('capsule', radius, height, segments, rings, smooth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(radius)
    ..add(height)
    ..addInt(segments)
    ..addInt(rings)
    ..addBool(smooth);

  /// Half the length of its straight part.
  double get _half =>
      math.max(Primitive3D.size(height) / 2 - Primitive3D.size(radius), 0.0);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final r = Primitive3D.size(radius), c = _half;
    final n = Primitive3D.count(rings, 1, 32);
    final cap = uv.anyway(r * math.pi / 2);
    final straight = uv.alongY(c * 2);
    final profile = <(double, double, double, double, double)>[];
    for (var j = 0; j <= n; j++) {
      final t = math.pi / 2 * j / n;
      profile.add((
        r * math.sin(t),
        -c - r * math.cos(t),
        math.sin(t),
        -math.cos(t),
        uv.anyway(r * t),
      ));
    }
    for (var j = 0; j <= n; j++) {
      final t = math.pi / 2 + math.pi / 2 * j / n;
      profile.add((
        r * math.sin(t),
        c - r * math.cos(t),
        math.sin(t),
        -math.cos(t),
        cap + straight + uv.anyway(r * (t - math.pi / 2)),
      ));
    }
    final b = MeshBuilder(uv)
      ..lathe(
        profile,
        Primitive3D.count(segments, 3, 128),
        aroundLength: uv.around(r),
        profileLength: cap * 2 + straight,
      );
    final mesh = b.build();
    return smooth ? mesh : mesh.faceted();
  }

  @override
  void boundsInto(Aabb3 out) {
    final r = Primitive3D.size(radius), h = _half + r;
    out.setValues(-r, -h, -r, r, h, r);
  }

  @override
  List<SolidPart> get solidParts {
    final r = Primitive3D.size(radius), c = _half;
    return [c > 0 ? SolidCapsule(c, r) : SolidSphere(r)];
  }
}

/// A cone of [radius] at its base and [height], its tip up.
class Cone3D extends Primitive3D {
  /// A cone 1 m across and 1 m tall by default.
  Cone3D({
    this.radius = 0.5,
    this.height = 1.0,
    this.segments = 24,
    this.smooth = true,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// The radius of its base.
  double radius;

  /// From base to tip.
  double height;

  /// Steps round it (3–128).
  int segments;

  /// Whether its side is shaded smooth, or faceted.
  bool smooth;

  @override
  String get shapeName => 'Cone';

  @override
  Object get shapeKey => ('cone', radius, height, segments, smooth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(radius)
    ..add(height)
    ..addInt(segments)
    ..addBool(smooth);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final r = Primitive3D.size(radius),
        h = Primitive3D.size(height),
        hy = h / 2;
    final s = Primitive3D.count(segments, 3, 128);
    final slant = math.sqrt(r * r + h * h);
    final nr = h / slant, ny = -r / slant;
    final along = uv.anyway(slant);
    final b = MeshBuilder(uv)
      ..lathe(
        [(0, -hy, nr, ny, 0), (r, hy, nr, ny, along)],
        s,
        aroundLength: uv.around(r),
        profileLength: along,
      )
      ..disc(r, hy, s, up: false);
    final mesh = b.build();
    return smooth ? mesh : mesh.faceted();
  }

  @override
  void boundsInto(Aabb3 out) {
    final r = Primitive3D.size(radius), hy = Primitive3D.size(height) / 2;
    out.setValues(-r, -hy, -r, r, hy, r);
  }

  @override
  List<SolidPart> get solidParts {
    final r = Primitive3D.size(radius), hy = Primitive3D.size(height) / 2;
    final s = Primitive3D.count(segments, 3, 32);
    final points = Float32List((s + 1) * 3);
    for (var i = 0; i < s; i++) {
      final a = 2 * math.pi * i / s;
      points
        ..[i * 3] = r * math.cos(a)
        ..[i * 3 + 1] = hy
        ..[i * 3 + 2] = r * math.sin(a);
    }
    points[s * 3 + 1] = -hy;
    return [SolidHull(points)];
  }
}

/// A ring lying flat: a tube of [tubeRadius] bent round a circle of
/// [radius] (to the middle of the tube).
class Torus3D extends Primitive3D {
  /// A ring 1.4 m across by default.
  Torus3D({
    this.radius = 0.5,
    this.tubeRadius = 0.2,
    this.segments = 32,
    this.sides = 16,
    this.smooth = true,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// From the middle to the middle of the tube.
  double radius;

  /// The tube's radius.
  double tubeRadius;

  /// Steps round the ring (3–128).
  int segments;

  /// Steps round the tube (3–64).
  int sides;

  /// Whether it is shaded smooth, or faceted.
  bool smooth;

  @override
  String get shapeName => 'Torus';

  @override
  Object get shapeKey => ('torus', radius, tubeRadius, segments, sides, smooth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(radius)
    ..add(tubeRadius)
    ..addInt(segments)
    ..addInt(sides)
    ..addBool(smooth);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final big = Primitive3D.size(radius), r = Primitive3D.size(tubeRadius);
    final t = Primitive3D.count(sides, 3, 64);
    final b = MeshBuilder(uv)
      ..lathe(
        [
          for (var k = 0; k <= t; k++)
            (
              big + r * math.cos(2 * math.pi * k / t),
              -r * math.sin(2 * math.pi * k / t),
              math.cos(2 * math.pi * k / t),
              -math.sin(2 * math.pi * k / t),
              uv.anyway(r * 2 * math.pi * k / t),
            ),
        ],
        Primitive3D.count(segments, 3, 128),
        aroundLength: uv.around(big),
        profileLength: uv.anyway(r * 2 * math.pi),
      );
    final mesh = b.build();
    return smooth ? mesh : mesh.faceted();
  }

  @override
  void boundsInto(Aabb3 out) {
    final big = Primitive3D.size(radius), r = Primitive3D.size(tubeRadius);
    out.setValues(-(big + r), -r, -(big + r), big + r, r, big + r);
  }

  /// One piece per step round the ring (at most 24): the hull of the tube
  /// where the step begins and ends.
  @override
  List<SolidPart> get solidParts {
    final big = Primitive3D.size(radius), r = Primitive3D.size(tubeRadius);
    final s = Primitive3D.count(segments, 3, 24);
    final t = Primitive3D.count(sides, 3, 12);
    SolidHull piece(int i) {
      final points = Float32List(t * 6);
      var o = 0;
      for (final step in [i, i + 1]) {
        final a = 2 * math.pi * step / s;
        for (var k = 0; k < t; k++) {
          final b = 2 * math.pi * k / t;
          final rho = big + r * math.cos(b);
          points
            ..[o++] = rho * math.cos(a)
            ..[o++] = -r * math.sin(b)
            ..[o++] = rho * math.sin(a);
        }
      }
      return SolidHull(points);
    }

    return [for (var i = 0; i < s; i++) piece(i)];
  }
}

/// A wedge rising towards +Z: flat underneath, [height] tall at its back,
/// nothing at its front — something to walk up.
class Ramp3D extends Primitive3D {
  /// A ramp 1 m wide, 1 m tall and 2 m long by default.
  Ramp3D({
    this.width = 1.0,
    this.height = 1.0,
    this.depth = 2.0,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Along X.
  double width;

  /// Along Y, at its back.
  double height;

  /// Along Z: how long the slope runs.
  double depth;

  @override
  String get shapeName => 'Ramp';

  @override
  Object get shapeKey => ('ramp', width, height, depth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(width)
    ..add(height)
    ..add(depth);

  List<(double, double, double)> get _corners {
    final hx = Primitive3D.size(width) / 2,
        hy = Primitive3D.size(height) / 2,
        hz = Primitive3D.size(depth) / 2;
    return [
      (-hx, hy, -hz), // front left, on the ground
      (hx, hy, -hz), // front right
      (hx, hy, hz), // back right
      (-hx, hy, hz), // back left
      (hx, -hy, hz), // back right, at the top
      (-hx, -hy, hz), // back left, at the top
    ];
  }

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final c = _corners;
    final h = Primitive3D.size(height), d = Primitive3D.size(depth);
    final len = math.sqrt(h * h + d * d);
    final b = MeshBuilder(uv)
      ..face([c[0], c[1], c[2], c[3]], 0, 1, 0) // underneath
      ..face([c[3], c[2], c[4], c[5]], 0, 0, 1) // back
      ..face([c[0], c[1], c[4], c[5]], 0, -d / len, -h / len) // slope
      ..face([c[0], c[3], c[5]], -1, 0, 0)
      ..face([c[1], c[2], c[4]], 1, 0, 0);
    return b.build();
  }

  @override
  void boundsInto(Aabb3 out) {
    final hx = Primitive3D.size(width) / 2,
        hy = Primitive3D.size(height) / 2,
        hz = Primitive3D.size(depth) / 2;
    out.setValues(-hx, -hy, -hz, hx, hy, hz);
  }

  @override
  List<SolidPart> get solidParts => [
    SolidHull(
      Float32List.fromList([
        for (final (x, y, z) in _corners) ...[x, y, z],
      ]),
    ),
  ];
}

/// A flight of [steps] solid steps rising towards +Z, [width] wide, [height]
/// tall and [depth] long overall.
class Stairs3D extends Primitive3D {
  /// Five steps, 1 m wide, 1 m tall and 2 m long by default.
  Stairs3D({
    this.width = 1.0,
    this.height = 1.0,
    this.depth = 2.0,
    this.steps = 5,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Along X.
  double width;

  /// Along Y, to the top of the last step.
  double height;

  /// Along Z, from the first step's front to the last's back.
  double depth;

  /// How many steps (1–64).
  int steps;

  @override
  String get shapeName => 'Stairs';

  @override
  Object get shapeKey => ('stairs', width, height, depth, steps);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(width)
    ..add(height)
    ..add(depth)
    ..addInt(steps);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final hx = Primitive3D.size(width) / 2,
        hy = Primitive3D.size(height) / 2,
        hz = Primitive3D.size(depth) / 2;
    final n = Primitive3D.count(steps, 1, 64);
    final run = hz * 2 / n, rise = hy * 2 / n;
    final b = MeshBuilder(uv)
      ..face(
        [(-hx, hy, -hz), (hx, hy, -hz), (hx, hy, hz), (-hx, hy, hz)],
        0,
        1,
        0,
      ) // underneath
      ..face(
        [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)],
        0,
        0,
        1,
      ); // back
    for (var i = 0; i < n; i++) {
      final z0 = -hz + i * run, z1 = z0 + run;
      final top = hy - (i + 1) * rise; // this step's tread
      final below = hy - i * rise; // the one before's, or the ground
      b
        ..face(
          [(-hx, top, z0), (hx, top, z0), (hx, top, z1), (-hx, top, z1)],
          0,
          -1,
          0,
        ) // tread
        ..face(
          [(-hx, top, z0), (hx, top, z0), (hx, below, z0), (-hx, below, z0)],
          0,
          0,
          -1,
        ) // riser
        ..face(
          [(-hx, top, z0), (-hx, top, z1), (-hx, hy, z1), (-hx, hy, z0)],
          -1,
          0,
          0,
        )
        ..face(
          [(hx, top, z0), (hx, top, z1), (hx, hy, z1), (hx, hy, z0)],
          1,
          0,
          0,
        );
    }
    return b.build();
  }

  @override
  void boundsInto(Aabb3 out) {
    final hx = Primitive3D.size(width) / 2,
        hy = Primitive3D.size(height) / 2,
        hz = Primitive3D.size(depth) / 2;
    out.setValues(-hx, -hy, -hz, hx, hy, hz);
  }

  /// One box per step, from the ground to its tread.
  @override
  List<SolidPart> get solidParts {
    final hx = Primitive3D.size(width) / 2,
        hy = Primitive3D.size(height) / 2,
        hz = Primitive3D.size(depth) / 2;
    final n = Primitive3D.count(steps, 1, 64);
    final run = hz * 2 / n, rise = hy * 2 / n;
    return [
      for (var i = 0; i < n; i++)
        SolidBox(
          hx,
          (i + 1) * rise / 2,
          run / 2,
          y: hy - (i + 1) * rise / 2,
          z: -hz + (i + 0.5) * run,
        ),
    ];
  }
}

/// A curved band standing up in its entity's XY plane: [angle] of a ring of
/// [radius] (outside) and [thickness], [depth] deep. Half a turn, the
/// default, is an arch with its feet on the ground.
class Arch3D extends Primitive3D {
  /// A half-round arch 3 m across by default.
  Arch3D({
    this.radius = 1.5,
    this.thickness = 0.3,
    this.depth = 0.5,
    this.angle = math.pi,
    this.segments = 16,
    this.smooth = true,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  });

  /// Its outside radius.
  double radius;

  /// From its outside to its inside.
  double thickness;

  /// Along Z.
  double depth;

  /// How much of a ring it is, radians (up to a whole turn), centred on
  /// straight up.
  double angle;

  /// Steps along it (1–128).
  int segments;

  /// Whether its curved faces are shaded smooth, or faceted.
  bool smooth;

  @override
  String get shapeName => 'Arch';

  @override
  Object get shapeKey =>
      ('arch', radius, thickness, depth, angle, segments, smooth);

  @override
  void writeShapeValues(ShapeValues values) => values
    ..add(radius)
    ..add(thickness)
    ..add(depth)
    ..add(angle)
    ..addInt(segments)
    ..addBool(smooth);

  double get _angle => angle.abs().clamp(0.01, 2 * math.pi);
  bool get _closed => _angle >= 2 * math.pi - 1e-6;
  double get _outer => Primitive3D.size(radius);
  double get _inner => math.max(_outer - Primitive3D.size(thickness), 0.0);
  int get _steps => Primitive3D.count(segments, 1, 128);

  /// Where along the ring step [i] is, radians from +X towards up.
  double _at(int i) => math.pi / 2 - _angle / 2 + _angle * i / _steps;

  /// The middle of its bounds before centring: (x, y).
  (double, double) get _centre {
    var x0 = double.infinity,
        x1 = -double.infinity,
        y0 = double.infinity,
        y1 = -double.infinity;
    for (var i = 0; i <= _steps; i++) {
      final a = _at(i);
      for (final r in [_inner, _outer]) {
        final x = r * math.cos(a), y = -r * math.sin(a);
        x0 = math.min(x0, x);
        x1 = math.max(x1, x);
        y0 = math.min(y0, y);
        y1 = math.max(y1, y);
      }
    }
    return ((x0 + x1) / 2, (y0 + y1) / 2);
  }

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final (cx, cy) = _centre;
    final hz = Primitive3D.size(depth) / 2;
    final n = _steps;
    final b = MeshBuilder(uv);
    (double, double, double) at(int i, double r, double z) {
      final a = _at(i);
      return (r * math.cos(a) - cx, -r * math.sin(a) - cy, z);
    }

    // The curved faces: outside facing out, inside facing the middle.
    for (final (r, out) in [(_outer, 1.0), (_inner, -1.0)]) {
      if (r <= 0) continue;
      final first = b.vertexCount;
      final length = uv.anyway(r * _angle);
      for (var i = 0; i <= n; i++) {
        final a = _at(i);
        final nx = math.cos(a) * out, ny = -math.sin(a) * out;
        for (final z in [-hz, hz]) {
          final (x, y, _) = at(i, r, z);
          final u = uv.metres ? length * i / n : i / n;
          final v = uv.metres ? z * uv.sz + hz * uv.sz : (z + hz) / (2 * hz);
          b.vertex(x, y, z, nx, ny, 0, u, v);
        }
      }
      for (var i = 0; i < n; i++) {
        final a = first + i * 2;
        b.quad(a, a + 1, a + 3, a + 2);
      }
    }
    // Front and back.
    for (var i = 0; i < n; i++) {
      for (final z in [-hz, hz]) {
        b.face(
          [
            at(i, _inner, z),
            at(i, _outer, z),
            at(i + 1, _outer, z),
            at(i + 1, _inner, z),
          ],
          0,
          0,
          z < 0 ? -1 : 1,
        );
      }
    }
    // Its two ends.
    if (!_closed) {
      for (final (i, sign) in [(0, 1.0), (n, -1.0)]) {
        final a = _at(i);
        b.face(
          [
            at(i, _inner, -hz),
            at(i, _outer, -hz),
            at(i, _outer, hz),
            at(i, _inner, hz),
          ],
          math.sin(a) * sign,
          math.cos(a) * sign,
          0,
        );
      }
    }
    final mesh = b.build();
    return smooth ? mesh : mesh.faceted();
  }

  @override
  void boundsInto(Aabb3 out) {
    final (cx, cy) = _centre;
    final hz = Primitive3D.size(depth) / 2;
    out.setEmpty();
    for (var i = 0; i <= _steps; i++) {
      final a = _at(i);
      for (final r in [_inner, _outer]) {
        out.addXYZ(r * math.cos(a) - cx, -r * math.sin(a) - cy, -hz);
      }
    }
    out.max.z = hz;
  }

  /// One piece per step along it.
  @override
  List<SolidPart> get solidParts {
    final (cx, cy) = _centre;
    final hz = Primitive3D.size(depth) / 2;
    return [
      for (var i = 0; i < _steps; i++)
        SolidHull(
          Float32List.fromList([
            for (final step in [i, i + 1])
              for (final r in [_inner, _outer])
                for (final z in [-hz, hz]) ...[
                  r * math.cos(_at(step)) - cx,
                  -r * math.sin(_at(step)) - cy,
                  z,
                ],
          ]),
        ),
    ];
  }
}

/// An outline drawn on the ground, raised [height]: a floor, a wall or a
/// platform of any shape. Each of its [points] is (x, z) in its entity's
/// space — `Offset.dx` is x, `Offset.dy` is z.
class Polygon3D extends Primitive3D {
  /// A prism through [points] (a hexagon 1 m across when none are given),
  /// 1 m tall by default.
  Polygon3D({
    List<Offset>? points,
    this.height = 1.0,
    super.material,
    super.color,
    super.metallic,
    super.roughness,
    super.emission,
    super.emissionStrength,
    super.opacity,
    super.unlit,
    super.texture,
    super.tiling,
    super.tileInMetres,
    super.castShadows,
    super.visible,
  }) : points = points ?? regular(6, 0.5);

  /// A regular outline of [sides] corners on a circle of [radius].
  static List<Offset> regular(int sides, double radius) => [
    for (var i = 0; i < sides; i++)
      Offset(
        radius * math.cos(2 * math.pi * i / sides),
        radius * math.sin(2 * math.pi * i / sides),
      ),
  ];

  /// The outline's corners, in order round it: (x, z).
  List<Offset> points;

  /// Along Y.
  double height;

  @override
  String get shapeName => 'Polygon';

  @override
  Object get shapeKey => ('polygon', height, _PointsKey(points));

  @override
  void writeShapeValues(ShapeValues values) {
    values.add(height);
    final points = this.points;
    for (var i = 0; i < points.length; i++) {
      values
        ..add(points[i].dx)
        ..add(points[i].dy);
    }
  }

  List<(double, double)> get _outline =>
      Outline.clean([for (final p in points) (p.dx, p.dy)]);

  @override
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]) {
    final outline = _outline;
    final b = MeshBuilder(uv);
    if (outline.length < 3) return b.build();
    final hy = Primitive3D.size(height) / 2;
    final triangles = Outline.triangulate(outline);
    for (final (y, ny) in [(-hy, -1.0), (hy, 1.0)]) {
      final first = b.vertexCount;
      for (final (x, z) in outline) {
        final (u, v) = b.planar(x, y, z, 0, ny, 0);
        b.vertex(x, y, z, 0, ny, 0, u, v);
      }
      for (var i = 0; i + 2 < triangles.length; i += 3) {
        b.triangle(
          first + triangles[i],
          first + triangles[i + 1],
          first + triangles[i + 2],
        );
      }
    }
    // Its sides, facing out whichever way the outline runs.
    final out = Outline.signedArea2(outline) > 0 ? 1.0 : -1.0;
    for (var i = 0; i < outline.length; i++) {
      final (x0, z0) = outline[i];
      final (x1, z1) = outline[(i + 1) % outline.length];
      final dx = x1 - x0, dz = z1 - z0;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len == 0) continue;
      b.face(
        [(x0, -hy, z0), (x1, -hy, z1), (x1, hy, z1), (x0, hy, z0)],
        dz / len * out,
        0,
        -dx / len * out,
      );
    }
    return b.build();
  }

  @override
  void boundsInto(Aabb3 out) {
    final hy = Primitive3D.size(height) / 2;
    out.setEmpty();
    for (final p in points) {
      out.addXYZ(p.dx, -hy, p.dy);
    }
    if (out.isEmpty) {
      out.setValues(0, -hy, 0, 0, hy, 0);
    } else {
      out.max.y = hy;
    }
  }

  /// One piece when the outline is convex, else one per convex part of it.
  @override
  List<SolidPart> get solidParts {
    final outline = _outline;
    if (outline.length < 3) return const [];
    final hy = Primitive3D.size(height) / 2;
    SolidHull hull(Iterable<(double, double)> corners) => SolidHull(
      Float32List.fromList([
        for (final (x, z) in corners) ...[x, -hy, z, x, hy, z],
      ]),
    );
    if (Outline.isConvex(outline)) return [hull(outline)];
    return [
      for (final part in Outline.convexParts(
        outline,
        Outline.triangulate(outline),
      ))
        hull([for (final i in part) outline[i]]),
    ];
  }
}

/// A list of points compared by value, for [Polygon3D.shapeKey].
final class _PointsKey {
  _PointsKey(List<Offset> points)
    : _values = [
        for (final p in points) ...[p.dx, p.dy],
      ];

  final List<double> _values;

  @override
  bool operator ==(Object other) {
    if (other is! _PointsKey || other._values.length != _values.length) {
      return false;
    }
    for (var i = 0; i < _values.length; i++) {
      if (other._values[i] != _values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_values);
}
