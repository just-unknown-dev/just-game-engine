import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/assets.dart';

/// A 3-D shape made from its own sizes rather than a model file — the base
/// of `Cube3D`, `Sphere3D`, `Plane3D`, `Cylinder3D`, `Capsule3D`,
/// `Cone3D`, `Torus3D`, `Ramp3D`, `Stairs3D`, `Arch3D` and `Polygon3D`.
///
/// Every shape is centred on its entity, in metres, with +Y down like the
/// rest of the engine. An entity has at most one (as a 2-D entity has one
/// renderable): find it with `entity.getComponent<Primitive3D>()`.
///
/// Each carries its look — a physically based material: [color],
/// [metallic], [roughness], a [emission] glow, [opacity], [unlit], and an
/// optional [texture] repeated [tiling] times (per metre of the world with
/// [tileInMetres]).
///
/// Its shape is also a [SolidShapeSource], so the engine's `Collider3D`
/// set to match the shape takes the same one.
abstract class Primitive3D extends Component implements SolidShapeSource {
  /// A shape with the given look; the defaults are a light grey, slightly
  /// rough, untextured surface.
  Primitive3D({
    this.color = defaultColor,
    this.metallic = 0.0,
    this.roughness = 0.75,
    this.emission = const Color(0xFF000000),
    this.emissionStrength = 1.0,
    this.opacity = 1.0,
    this.unlit = false,
    this.texture = '',
    Vector2? tiling,
    this.tileInMetres = false,
    this.castShadows = true,
    this.visible = true,
  }) : tiling = tiling ?? Vector2(1, 1);

  /// The colour a new shape has.
  static const Color defaultColor = Color(0xFFD5D9DF);

  /// Every shape shares one column: an entity has one shape.
  @override
  Type get componentType => Primitive3D;

  /// Its colour (sRGB, as picked); multiplies the [texture].
  Color color;

  /// How metallic it is, 0–1.
  double metallic;

  /// How rough it is, 0 (a mirror) – 1 (chalk).
  double roughness;

  /// The light it gives off itself (sRGB); black for none.
  Color emission;

  /// How strongly it glows: [emission] times this.
  double emissionStrength;

  /// How opaque it is, 0–1. Below 1 it is drawn blended, after everything
  /// opaque.
  double opacity;

  /// Whether it shows its colour as it is, with no light or shade.
  bool unlit;

  /// An image (asset path) on its surface; empty for none.
  String texture;

  /// How many times the [texture] repeats across a face — or per metre,
  /// with [tileInMetres].
  Vector2 tiling;

  /// Whether [tiling] counts repeats per metre of the world, so a texture
  /// keeps its scale on shapes of any size and scale.
  bool tileInMetres;

  /// Whether it casts shadows (where shadows are on).
  bool castShadows;

  /// Whether it is drawn.
  bool visible;

  /// What it is called: `Cube`.
  String get shapeName;

  /// Equal for as long as its mesh stays the same: its sizes and detail.
  Object get shapeKey;

  /// Its triangles, textured by [uv].
  ShapeMesh buildMesh([ShapeUv uv = ShapeUv.natural]);

  /// Its bounds in its entity's own space into [out].
  void boundsInto(Aabb3 out);

  /// Whether its back faces are drawn too (a plane's).
  bool get doubleSided => false;

  @override
  Object get solidKey => shapeKey;

  /// Equal for as long as its look stays the same.
  Object get materialKey => (
    color.toARGB32(),
    metallic,
    roughness,
    emission.toARGB32(),
    emissionStrength,
    opacity,
    unlit,
    texture,
    tiling.x,
    tiling.y,
    doubleSided,
  );

  /// The smallest size a shape is made at, so a zero gives a tiny shape
  /// rather than none.
  static const double minSize = 0.001;

  /// [v] as a size: positive, at least [minSize].
  static double size(double v) => math.max(v.abs(), minSize);

  /// [v] kept within [lo]..[hi]: a count of segments.
  static int count(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
}

/// A [ShapeMesh] as the engine's [ModelGeometry], for picking and colliders.
extension ShapeMeshGeometry on ShapeMesh {
  /// Its triangles alone.
  ModelGeometry get geometry => ModelGeometry(positions, indices);
}
