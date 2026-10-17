import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:just_dart/just_dart.dart' show Aabb3, Vector2;
import 'package:just_graphics_engine/assets.dart';

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';
import '../../subsystems/assets/assets.dart';

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
    this.material = '',
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

  /// A material file (`*.material.json`) it is drawn with, by path —
  /// shared with everything else drawn with it; empty for its own look,
  /// the fields below. While set, those fields are kept but not used.
  String material;

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

  /// Gives [values] what [shapeKey] is made from, one by one, so a renderer
  /// can tell each frame whether the mesh changed without making a key.
  /// A shape of the engine's gives plain numbers; the default gives
  /// [shapeKey] itself.
  void writeShapeValues(ShapeValues values) => values.addObject(shapeKey);

  /// Gives [values] what [materialKey] is made from, one by one, so a
  /// renderer can tell each frame whether the look changed without making a
  /// key.
  void writeMaterialValues(ShapeValues values) => values
    ..addObject(material)
    ..addInt(color.toARGB32())
    ..add(metallic)
    ..add(roughness)
    ..addInt(emission.toARGB32())
    ..add(emissionStrength)
    ..add(opacity)
    ..addBool(unlit)
    ..addObject(texture)
    ..add(tiling.x)
    ..add(tiling.y)
    ..addBool(doubleSided);

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
    material,
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

/// What a shape's mesh or look was last made from, kept to tell cheaply
/// whether it has changed: a renderer keeps one per shape and each frame
/// gives it the shape's values ([Primitive3D.writeShapeValues],
/// [Primitive3D.writeMaterialValues]) between [begin] and [end]. Numbers
/// are compared in place, so nothing is made while nothing changes.
final class ShapeValues {
  Float64List _numbers = Float64List(16);
  int _numberCount = -1; // Nothing seen yet: the first look differs.
  int _number = 0;
  final List<Object?> _objects = [];
  int _object = 0;
  bool _changed = false;

  /// Starts a frame's look at the values.
  void begin() {
    _number = 0;
    _object = 0;
    _changed = false;
  }

  /// The next number is [v].
  void add(double v) {
    final at = _number++;
    if (at < _numberCount && _numbers[at] == v) return;
    if (at == _numbers.length) {
      _numbers = Float64List(at * 2)..setRange(0, at, _numbers);
    }
    _numbers[at] = v;
    _changed = true;
  }

  /// The next number is [v].
  void addInt(int v) => add(v.toDouble());

  /// The next number is 1 for [v], else 0.
  void addBool(bool v) => add(v ? 1 : 0);

  /// The next value is [v], compared with `==`.
  void addObject(Object? v) {
    final at = _object++;
    if (at < _objects.length) {
      if (_objects[at] == v) return;
      _objects[at] = v;
    } else {
      _objects.add(v);
    }
    _changed = true;
  }

  /// Ends the look: whether anything differs from the last one (always so
  /// the first time).
  bool end() {
    if (_number != _numberCount) {
      _numberCount = _number;
      _changed = true;
    }
    if (_object != _objects.length) {
      _objects.length = _object;
      _changed = true;
    }
    return _changed;
  }
}

/// A [ShapeMesh] as the engine's [ModelGeometry], for picking and colliders.
extension ShapeMeshGeometry on ShapeMesh {
  /// Its triangles alone.
  ModelGeometry get geometry => ModelGeometry(positions, indices);
}
