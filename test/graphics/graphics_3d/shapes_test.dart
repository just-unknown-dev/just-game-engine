@Tags(['graphics3d'])
library;

import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine/src/graphics/graphics_3d/shapes/outline.dart';

/// The volume a mesh encloses: positive when its triangles face out.
double volumeOf(ShapeMesh m) {
  var v = 0.0;
  final p = m.positions;
  for (var t = 0; t < m.indices.length; t += 3) {
    final a = m.indices[t] * 3, b = m.indices[t + 1] * 3, c = m.indices[t + 2] * 3;
    final cx = p[b + 1] * p[c + 2] - p[b + 2] * p[c + 1];
    final cy = p[b + 2] * p[c] - p[b] * p[c + 2];
    final cz = p[b] * p[c + 1] - p[b + 1] * p[c];
    v += p[a] * cx + p[a + 1] * cy + p[a + 2] * cz;
  }
  return v / 6;
}

/// Directed edges (by position) left without a twin running the other way:
/// none for a closed, consistently wound mesh.
int openEdges(ShapeMesh m) {
  String key(int i) {
    final p = m.positions;
    String r(double v) => (v * 1e4).round().toString();
    return '${r(p[i * 3])},${r(p[i * 3 + 1])},${r(p[i * 3 + 2])}';
  }

  final edges = <String, int>{};
  for (var t = 0; t < m.indices.length; t += 3) {
    for (var k = 0; k < 3; k++) {
      final a = key(m.indices[t + k]), b = key(m.indices[t + (k + 1) % 3]);
      edges.update('$a>$b', (n) => n + 1, ifAbsent: () => 1);
    }
  }
  var open = 0;
  edges.forEach((edge, n) {
    final [a, b] = edge.split('>');
    if ((edges['$b>$a'] ?? 0) != n) open++;
  });
  return open;
}

/// Whether each triangle faces the way its vertices' normals point.
bool facesAgree(ShapeMesh m) {
  final p = m.positions, n = m.normals;
  for (var t = 0; t < m.indices.length; t += 3) {
    final a = m.indices[t] * 3, b = m.indices[t + 1] * 3, c = m.indices[t + 2] * 3;
    final ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
    final vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2];
    final fx = uy * vz - uz * vy, fy = uz * vx - ux * vz, fz = ux * vy - uy * vx;
    final sx = n[a] + n[b] + n[c], sy = n[a + 1] + n[b + 1] + n[c + 1], sz = n[a + 2] + n[b + 2] + n[c + 2];
    if (fx * sx + fy * sy + fz * sz <= 0) return false;
  }
  return true;
}

void main() {
  final closed = <String, (Primitive3DComponent, double, double)>{
    // shape, expected volume, tolerance (relative)
    'cube': (Cube3DComponent(width: 2, height: 1, depth: 3), 6, 1e-6),
    'sphere': (Sphere3DComponent(radius: 1), 4 / 3 * math.pi, 0.03),
    'cylinder': (Cylinder3DComponent(radius: 1, height: 2, segments: 24), 24 / 2 * math.sin(2 * math.pi / 24) * 2, 1e-5),
    'capsule': (Capsule3DComponent(radius: 0.5, height: 2), math.pi * 0.25 * 1 + 4 / 3 * math.pi * 0.125, 0.03),
    'round capsule': (Capsule3DComponent(radius: 0.5, height: 1), 4 / 3 * math.pi * 0.125, 0.03),
    'cone': (Cone3DComponent(radius: 1, height: 3, segments: 16), 16 / 2 * math.sin(2 * math.pi / 16) * 3 / 3, 1e-5),
    // Pappus, for the 16-sided tube swept in 32 flat steps.
    'torus': (
      Torus3DComponent(radius: 1, tubeRadius: 0.25),
      16 / 2 * 0.0625 * math.sin(2 * math.pi / 16) * 32 * math.sin(2 * math.pi / 32),
      2e-3,
    ),
    'ramp': (Ramp3DComponent(width: 2, height: 1, depth: 4), 4, 1e-6),
    'stairs': (Stairs3DComponent(width: 1, height: 1, depth: 2, steps: 4), 1 * 0.5 * 0.25 * 10, 1e-6),
    'arch': (Arch3DComponent(radius: 2, thickness: 0.5, depth: 1, segments: 32), math.pi * (4 - 2.25) / 2, 0.01),
    'whole ring': (Arch3DComponent(radius: 2, thickness: 0.5, depth: 1, angle: 2 * math.pi, segments: 32), math.pi * (4 - 2.25), 0.01),
    'hexagon': (Polygon3DComponent(height: 2), 3 * math.sqrt(3) / 2 * 0.25 * 2, 1e-5),
    'L': (
      Polygon3DComponent(points: const [Offset(0, 0), Offset(2, 0), Offset(2, 1), Offset(1, 1), Offset(1, 2), Offset(0, 2)]),
      3,
      1e-6,
    ),
    'L drawn the other way': (
      Polygon3DComponent(points: const [Offset(0, 2), Offset(1, 2), Offset(1, 1), Offset(2, 1), Offset(2, 0), Offset(0, 0)]),
      3,
      1e-6,
    ),
  };

  group('every shape is closed, faces out and holds what it should', () {
    for (final MapEntry(key: name, value: (shape, volume, tolerance)) in closed.entries) {
      test(name, () {
        for (final mesh in [shape.buildMesh(), shape.buildMesh(const ShapeUv.metresAt(2, 1, 0.5))]) {
          expect(mesh.triangleCount, greaterThan(0));
          expect(facesAgree(mesh), isTrue, reason: 'a triangle faces against its normals');
          // Stairs meet their sides in T-junctions: closed, but not edge for edge.
          if (shape is! Stairs3DComponent) expect(openEdges(mesh), 0, reason: 'holes or mixed winding');
          expect(volumeOf(mesh), closeTo(volume, volume * tolerance));
        }
      });
    }
  });

  test('faceted shapes keep their volume, each triangle on its own', () {
    for (final shape in [
      Sphere3DComponent(smooth: false),
      Cylinder3DComponent(smooth: false),
      Capsule3DComponent(smooth: false),
      Cone3DComponent(smooth: false),
      Torus3DComponent(smooth: false),
      Arch3DComponent(smooth: false),
    ]) {
      final smooth = (shape..buildMesh()).buildMesh();
      final mesh = shape.buildMesh();
      expect(mesh.vertexCount, mesh.triangleCount * 3, reason: shape.shapeName);
      expect(facesAgree(mesh), isTrue, reason: shape.shapeName);
      expect(volumeOf(mesh), closeTo(volumeOf(smooth), 1e-6), reason: shape.shapeName);
    }
  });

  test('a plane faces up, both sides drawn, with a slab under it to stand on', () {
    final plane = Plane3DComponent(width: 4, depth: 2);
    final mesh = plane.buildMesh();
    expect(mesh.triangleCount, 2);
    for (var i = 0; i < mesh.vertexCount; i++) {
      expect(mesh.normals[i * 3 + 1], -1);
      expect(mesh.positions[i * 3 + 1], 0);
    }
    expect(facesAgree(mesh), isTrue);
    expect(plane.doubleSided, isTrue);
    expect(plane.solidParts, [const SolidBox(2, 0.05, 1, y: 0.05)]);
  });

  test('bounds hold the mesh and match it', () {
    for (final shape in [...closed.values.map((e) => e.$1), Plane3DComponent()]) {
      final b = Aabb3();
      shape.boundsInto(b);
      final m = shape.buildMesh().bounds;
      for (final (got, want) in [
        (m.min.x, b.min.x),
        (m.min.y, b.min.y),
        (m.min.z, b.min.z),
        (m.max.x, b.max.x),
        (m.max.y, b.max.y),
        (m.max.z, b.max.z),
      ]) {
        expect(got, closeTo(want, 0.02), reason: shape.shapeName);
      }
    }
  });

  test('a shape is centred on its entity', () {
    for (final shape in [Cube3DComponent(), Sphere3DComponent(), Cylinder3DComponent(), Capsule3DComponent(), Cone3DComponent(), Torus3DComponent(), Ramp3DComponent(), Stairs3DComponent(), Arch3DComponent()]) {
      final b = Aabb3();
      shape.boundsInto(b);
      expect((b.min.x + b.max.x) / 2, closeTo(0, 1e-9), reason: shape.shapeName);
      expect((b.min.y + b.max.y) / 2, closeTo(0, 1e-9), reason: shape.shapeName);
      expect((b.min.z + b.max.z) / 2, closeTo(0, 1e-9), reason: shape.shapeName);
    }
  });

  group('solid parts', () {
    test('primitives are themselves', () {
      expect(Cube3DComponent(width: 2, height: 4, depth: 6).solidParts, [const SolidBox(1, 2, 3)]);
      expect(Sphere3DComponent(radius: 2).solidParts, [const SolidSphere(2)]);
      expect(Cylinder3DComponent(radius: 0.5, height: 3).solidParts, [const SolidCylinder(1.5, 0.5)]);
      expect(Capsule3DComponent(radius: 0.5, height: 3).solidParts, [const SolidCapsule(1, 0.5)]);
      expect(Capsule3DComponent(radius: 0.5, height: 0.5).solidParts, [const SolidSphere(0.5)]);
    });

    test('stairs are a box per step, standing on the ground', () {
      final parts = Stairs3DComponent(width: 1, height: 1, depth: 2, steps: 4).solidParts.cast<SolidBox>();
      expect(parts, hasLength(4));
      for (final (i, box) in parts.indexed) {
        expect(box.y + box.halfY, closeTo(0.5, 1e-9), reason: 'step $i reaches the ground');
        expect(box.halfY * 2, closeTo((i + 1) * 0.25, 1e-9));
      }
    });

    test('round and blocking shapes are hulls: one, or one per piece', () {
      expect(Cone3DComponent(segments: 12).solidParts.single, isA<SolidHull>());
      expect((Cone3DComponent(segments: 12).solidParts.single as SolidHull).length, 13);
      expect(Ramp3DComponent().solidParts.single, isA<SolidHull>());
      expect(Torus3DComponent(segments: 32).solidParts, hasLength(24));
      expect(Torus3DComponent(segments: 8).solidParts, hasLength(8));
      expect(Arch3DComponent(segments: 10).solidParts, hasLength(10));
      expect(Polygon3DComponent().solidParts, hasLength(1), reason: 'a hexagon is convex');
      final l = Polygon3DComponent(
        points: const [Offset(0, 0), Offset(2, 0), Offset(2, 1), Offset(1, 1), Offset(1, 2), Offset(0, 2)],
      );
      expect(l.solidParts, hasLength(2), reason: 'an L is two convex pieces');
      expect(Polygon3DComponent(points: const [Offset(0, 0), Offset(1, 0)]).solidParts, isEmpty);
    });

    test('hull points stay inside the bounds', () {
      for (final shape in [Cone3DComponent(), Ramp3DComponent(), Torus3DComponent(), Arch3DComponent(), Polygon3DComponent()]) {
        final b = Aabb3();
        shape.boundsInto(b);
        for (final part in shape.solidParts.cast<SolidHull>()) {
          for (var i = 0; i < part.points.length; i += 3) {
            expect(part.points[i], inInclusiveRange(b.min.x - 1e-4, b.max.x + 1e-4), reason: shape.shapeName);
            expect(part.points[i + 1], inInclusiveRange(b.min.y - 1e-4, b.max.y + 1e-4), reason: shape.shapeName);
            expect(part.points[i + 2], inInclusiveRange(b.min.z - 1e-4, b.max.z + 1e-4), reason: shape.shapeName);
          }
        }
      }
    });
  });

  group('outlines', () {
    test('triangulate convex and concave outlines, either way round', () {
      const square = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
      expect(Outline.triangulate(square), hasLength(6));
      const l = [(0.0, 0.0), (2.0, 0.0), (2.0, 1.0), (1.0, 1.0), (1.0, 2.0), (0.0, 2.0)];
      for (final outline in [l, l.reversed.toList()]) {
        final t = Outline.triangulate(outline);
        expect(t, hasLength(12));
        var area = 0.0;
        for (var i = 0; i < t.length; i += 3) {
          area += Outline.signedArea2([outline[t[i]], outline[t[i + 1]], outline[t[i + 2]]]) / 2;
        }
        expect(area, closeTo(3, 1e-9), reason: 'every triangle counter-clockwise, covering it');
      }
    });

    test('clean drops repeats and straight corners', () {
      expect(
        Outline.clean([(0.0, 0.0), (0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]),
        [(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0)],
      );
    });

    test('convexity', () {
      expect(Outline.isConvex([(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]), isTrue);
      expect(Outline.isConvex([(0.0, 0.0), (2.0, 0.0), (2.0, 1.0), (1.0, 1.0), (1.0, 2.0), (0.0, 2.0)]), isFalse);
    });
  });

  test('texture coordinates: once per face, or per metre of the world', () {
    double uSpan(ShapeMesh m, bool Function(int i) on) {
      var lo = double.infinity, hi = -double.infinity;
      for (var i = 0; i < m.vertexCount; i++) {
        if (!on(i)) continue;
        lo = math.min(lo, m.uvs[i * 2]);
        hi = math.max(hi, m.uvs[i * 2]);
      }
      return hi - lo;
    }

    final cube = Cube3DComponent(width: 2);
    bool front(ShapeMesh m, int i) => m.normals[i * 3 + 2] == 1;
    final natural = cube.buildMesh();
    expect(uSpan(natural, (i) => front(natural, i)), closeTo(1, 1e-9));
    final metres = cube.buildMesh(const ShapeUv.metresAt(1, 1, 1));
    expect(uSpan(metres, (i) => front(metres, i)), closeTo(2, 1e-6));
    final scaled = cube.buildMesh(const ShapeUv.metresAt(3, 1, 1));
    expect(uSpan(scaled, (i) => front(scaled, i)), closeTo(6, 1e-5));
    final sphere = Sphere3DComponent(radius: 1).buildMesh(const ShapeUv.metresAt(1, 1, 1));
    expect(uSpan(sphere, (_) => true), closeTo(2 * math.pi, 1e-5));
  });

  test('a shape has a key for its mesh and one for its look', () {
    final cube = Cube3DComponent();
    final shape = cube.shapeKey, look = cube.materialKey;
    cube.color = const Color(0xFFFF0000);
    expect(cube.shapeKey, shape);
    expect(cube.materialKey, isNot(look));
    cube.width = 2;
    expect(cube.shapeKey, isNot(shape));
    expect(cube.solidKey, cube.shapeKey);
    final polygon = Polygon3DComponent();
    final key = polygon.shapeKey;
    polygon.points = [...polygon.points];
    expect(polygon.shapeKey, key, reason: 'equal points, equal key');
    polygon.points = [...polygon.points.take(5)];
    expect(polygon.shapeKey, isNot(key));
  });

  test('one shape per entity, found as a Primitive3DComponent', () {
    final world = World();
    final entity = world.createEntity(name: 'box')
      ..addComponent(TransformComponent())
      ..addComponent(Sphere3DComponent());
    expect(entity.getComponent<Primitive3DComponent>(), isA<Sphere3DComponent>());
    expect(entity.components.whereType<SolidShapeSource>().single, isA<Sphere3DComponent>());
  });

  test('every shape saves and loads every field', () {
    final shapes = <Primitive3DComponent>[
      Cube3DComponent(width: 2, height: 3, depth: 4),
      Sphere3DComponent(radius: 2, segments: 12, rings: 6, smooth: false),
      Plane3DComponent(width: 3, depth: 5),
      Cylinder3DComponent(radius: 2, height: 5, segments: 7, smooth: false),
      Capsule3DComponent(radius: 0.4, height: 1.6, segments: 9, rings: 3),
      Cone3DComponent(radius: 2, height: 4, segments: 5),
      Torus3DComponent(radius: 2, tubeRadius: 0.5, segments: 9, sides: 5),
      Ramp3DComponent(width: 2, height: 0.5, depth: 6),
      Stairs3DComponent(steps: 9),
      Arch3DComponent(radius: 3, thickness: 0.5, depth: 2, angle: 2, segments: 7),
      Polygon3DComponent(points: const [Offset(0, 0), Offset(3, 0), Offset(0, 4)], height: 0.25),
    ];
    for (final shape in shapes) {
      shape
        ..color = const Color(0xFF123456)
        ..metallic = 0.5
        ..roughness = 0.25
        ..emission = const Color(0xFF00FF00)
        ..emissionStrength = 3
        ..opacity = 0.5
        ..unlit = true
        ..texture = 'assets/textures/grid.png'
        ..tiling = Vector2(2, 3)
        ..tileInMetres = true
        ..castShadows = false
        ..visible = false;
    }
    final byType = {for (final s in Shape3DDefinitions.all) s.type: s};
    expect(byType, hasLength(11));
    for (final shape in shapes) {
      final schema = byType[shape.runtimeType.toString()]!;
      final json = schema.encodeAny(shape);
      final back = schema.decode(json) as Primitive3DComponent;
      expect(back.runtimeType, shape.runtimeType);
      expect(back.shapeKey, shape.shapeKey, reason: shape.shapeName);
      expect(back.materialKey, shape.materialKey, reason: shape.shapeName);
      expect(back.tileInMetres, isTrue);
      expect(back.castShadows, isFalse);
      expect(back.visible, isFalse);
      expect(schema.hints.dimensions, Dimensions.threeD);
      expect(schema.extent!.boundsInto(back, Aabb3()), isTrue);
    }
  });

  test('the graphics extension registers the shapes', () {
    final context = EngineContext(extensions: [Graphics3D()]);
    for (final type in ['Cube3DComponent', 'Sphere3DComponent', 'Plane3DComponent', 'Polygon3DComponent', 'Arch3DComponent']) {
      expect(context.definitions.definitionByType(type), isNotNull, reason: type);
    }
  });
}
