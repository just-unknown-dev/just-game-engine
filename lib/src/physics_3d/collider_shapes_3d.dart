import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_physics_engine/physics_3d.dart';

import '../ecs/components/shapes/solid_shape.dart';
import '../subsystems/assets/asset_management.dart';
import 'physics_components_3d.dart';

/// Where mesh and convex-hull colliders get their triangles.
abstract interface class ColliderGeometry3D {
  /// The triangles of [model]'s mesh [meshName] (every mesh merged when it
  /// is empty), in the model's space; null while they are not there yet —
  /// the model still loading — or when there are none. The system asks
  /// again each step until it gets them.
  ModelGeometry? geometryOf(String model, String meshName);
}

/// Triangles from the engine's loaded [ModelAsset]s. A model not loaded yet
/// is loaded through [assets] (a renderer such as just_graphics_engine
/// registers the loader for [AssetType.model]).
final class AssetColliderGeometry3D implements ColliderGeometry3D {
  /// Geometry from [assets].
  AssetColliderGeometry3D(this.assets);

  /// The engine's assets.
  final AssetManager assets;

  final Set<String> _requested = {};
  final Map<String, ModelGeometry?> _merged = {};
  final Map<String, Object> _mergedFrom = {};

  @override
  ModelGeometry? geometryOf(String model, String meshName) {
    if (model.isEmpty) return null;
    final asset = assets.get<ModelAsset>(model);
    if (asset == null) {
      if (_requested.add(model) && assets.hasLoader(AssetType.model)) {
        assets
            .load<ModelAsset>(model, AssetType.model)
            .then(
              (_) {},
              onError: (Object error) =>
                  debugPrint('Physics3D: no collider from $model: $error'),
            );
      }
      return null;
    }
    if (meshName.isNotEmpty) return asset.geometryOf(meshName);
    if (identical(_mergedFrom[model], asset)) return _merged[model];
    _mergedFrom[model] = asset;
    return _merged[model] = merge([
      for (final name in asset.meshNames) ?asset.geometryOf(name),
    ]);
  }

  /// Forgets what it kept of [model] — its meshes merged, that it was asked
  /// for — so the next ask reads the model's triangles again (it was loaded
  /// again; [ColliderShapes3D.forgetModel] calls this).
  void forget(String model) {
    _requested.remove(model);
    _merged.remove(model);
    _mergedFrom.remove(model);
  }

  /// [parts] as one geometry; null when there are none.
  static ModelGeometry? merge(List<ModelGeometry> parts) {
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.single;
    final positions = Float32List(
      parts.fold(0, (n, p) => n + p.positions.length),
    );
    final indices = Uint32List(parts.fold(0, (n, p) => n + p.indices.length));
    var vertexBase = 0, p = 0, i = 0;
    for (final part in parts) {
      positions.setAll(p, part.positions);
      for (final index in part.indices) {
        indices[i++] = index + vertexBase;
      }
      p += part.positions.length;
      vertexBase += part.positions.length ~/ 3;
    }
    return ModelGeometry(positions, indices);
  }
}

/// Turns [Collider3D]s into physics-engine [Shape3D]s, following the entity's
/// scale. Mesh and hull shapes are kept by model, mesh and scale, height
/// fields by their heights and scale, and shapes matching an entity's look
/// by that look's key and scale, so every body asking for the same one gets
/// the same lists — and the physics engine shares one native shape between
/// them. Each kind keeps its most recently used few ([modelLimit],
/// [fieldLimit], [solidLimit]); a shape dropped is made again when next
/// asked for.
final class ColliderShapes3D {
  /// Shapes whose triangles come from [geometry].
  ColliderShapes3D({this.geometry});

  /// Where mesh and hull colliders get their triangles; without it they
  /// make no shape.
  final ColliderGeometry3D? geometry;

  final Map<(ColliderShape3D, String, String, double, double, double), Shape3D>
  _models = {};
  final Map<(List<double>, int, double, double, double), Shape3D> _fields = {};
  final Map<(Object, double, double, double), Shape3D?> _solids = {};

  /// How many mesh and hull shapes are kept before the least recently used
  /// go: each holds a scaled copy of its model's triangles.
  static const int modelLimit = 64;

  /// How many height-field shapes are kept before the least recently used
  /// go.
  static const int fieldLimit = 16;

  /// How many shapes matching a look are kept before the least recently
  /// used go.
  static const int solidLimit = 256;

  /// How many shapes it keeps now, of every kind.
  int get length => _models.length + _fields.length + _solids.length;

  /// The smallest size a primitive gets, so a zero scale makes a tiny shape
  /// rather than an invalid one.
  static const double minExtent = 0.001;

  /// [collider]'s shape at [entityScale]; null while its triangles are not
  /// there yet, or when it cannot make one — a collider matching the shape
  /// of an entity with none ([source] null).
  Shape3D? build(
    Collider3D collider,
    Vector3 entityScale, {
    SolidShapeSource? source,
  }) {
    final sx = collider.scale.x * entityScale.x;
    final sy = collider.scale.y * entityScale.y;
    final sz = collider.scale.z * entityScale.z;
    final ax = sx.abs(), ay = sy.abs(), az = sz.abs();
    final Shape3D? shape = switch (collider.shape) {
      ColliderShape3D.box => BoxShape3D(
        math.max(collider.size.x * ax / 2, minExtent),
        math.max(collider.size.y * ay / 2, minExtent),
        math.max(collider.size.z * az / 2, minExtent),
      ),
      ColliderShape3D.sphere => SphereShape3D(
        math.max(collider.radius * math.max(ax, math.max(ay, az)), minExtent),
      ),
      ColliderShape3D.capsule => _capsule(collider, ax, ay, az),
      ColliderShape3D.cylinder => CylinderShape3D(
        math.max(collider.height * ay / 2, minExtent),
        math.max(collider.radius * math.max(ax, az), minExtent),
      ),
      ColliderShape3D.convexHull ||
      ColliderShape3D.mesh => _model(collider, sx, sy, sz),
      ColliderShape3D.heightField => _heightField(collider, ax, ay),
      ColliderShape3D.matchShape =>
        source == null ? null : _solid(source, sx, sy, sz),
    };
    if (shape == null) return null;
    return _place(shape, collider, entityScale);
  }

  static Shape3D _capsule(Collider3D c, double ax, double ay, double az) {
    final radius = math.max(c.radius * math.max(ax, az), minExtent);
    final halfHeight = c.height * ay / 2 - radius;
    // Too short for a straight part: a ball.
    return halfHeight <= 1e-4
        ? SphereShape3D(radius)
        : CapsuleShape3D(halfHeight, radius);
  }

  Shape3D? _model(Collider3D c, double sx, double sy, double sz) {
    final key = (c.shape, c.model, c.meshName, sx, sy, sz);
    final known = _used(_models, key);
    if (known != null) return known;
    final source = geometry?.geometryOf(c.model, c.meshName);
    if (source == null || source.positions.isEmpty) return null;
    final positions = Float32List(source.positions.length);
    for (var i = 0; i < positions.length; i += 3) {
      positions[i] = source.positions[i] * sx;
      positions[i + 1] = source.positions[i + 1] * sy;
      positions[i + 2] = source.positions[i + 2] * sz;
    }
    final Shape3D shape;
    if (c.shape == ColliderShape3D.convexHull) {
      shape = ConvexHullShape3D(positions);
    } else {
      final indices = Uint32List.fromList(source.indices);
      // A mirror turns triangles inside out; turn them back.
      if (sx * sy * sz < 0) {
        for (var i = 0; i + 2 < indices.length; i += 3) {
          final t = indices[i + 1];
          indices[i + 1] = indices[i + 2];
          indices[i + 2] = t;
        }
      }
      shape = MeshShape3D(positions, indices);
    }
    return _keep(_models, key, shape, modelLimit);
  }

  Shape3D? _solid(SolidShapeSource source, double sx, double sy, double sz) {
    final key = (source.solidKey, sx, sy, sz);
    if (_solids.containsKey(key)) {
      // The most recently used now.
      final known = _solids.remove(key);
      return _solids[key] = known;
    }
    final parts = [
      for (final part in source.solidParts) ?solidPart(part, sx, sy, sz),
    ];
    return _keep(_solids, key, switch (parts.length) {
      0 => null,
      1 => parts.single,
      _ => CompoundShape3D(parts),
    }, solidLimit);
  }

  /// [part] scaled by ([sx], [sy], [sz]) as a physics-engine shape, placed where
  /// it is; null for a hull of too few points.
  static Shape3D? solidPart(SolidPart part, double sx, double sy, double sz) {
    final ax = sx.abs(), ay = sy.abs(), az = sz.abs();
    Shape3D at(Shape3D shape, double x, double y, double z) =>
        x == 0 && y == 0 && z == 0
        ? shape
        : TransformedShape3D(shape, x: x * sx, y: y * sy, z: z * sz);
    switch (part) {
      case SolidBox(
        :final halfX,
        :final halfY,
        :final halfZ,
        :final x,
        :final y,
        :final z,
      ):
        return at(
          BoxShape3D(
            math.max(halfX * ax, minExtent),
            math.max(halfY * ay, minExtent),
            math.max(halfZ * az, minExtent),
          ),
          x,
          y,
          z,
        );
      case SolidSphere(:final radius, :final x, :final y, :final z):
        return at(
          SphereShape3D(
            math.max(radius * math.max(ax, math.max(ay, az)), minExtent),
          ),
          x,
          y,
          z,
        );
      case SolidCapsule(
        :final halfHeight,
        :final radius,
        :final x,
        :final y,
        :final z,
      ):
        final r = math.max(radius * math.max(ax, az), minExtent);
        final half = (halfHeight + radius) * ay - r;
        return at(
          half <= 1e-4 ? SphereShape3D(r) : CapsuleShape3D(half, r),
          x,
          y,
          z,
        );
      case SolidCylinder(
        :final halfHeight,
        :final radius,
        :final x,
        :final y,
        :final z,
      ):
        return at(
          CylinderShape3D(
            math.max(halfHeight * ay, minExtent),
            math.max(radius * math.max(ax, az), minExtent),
          ),
          x,
          y,
          z,
        );
      case SolidHull(:final points):
        if (points.length < 12) return null;
        final scaled = Float32List(points.length);
        for (var i = 0; i < points.length; i += 3) {
          scaled[i] = points[i] * sx;
          scaled[i + 1] = points[i + 1] * sy;
          scaled[i + 2] = points[i + 2] * sz;
        }
        return ConvexHullShape3D(scaled);
    }
  }

  Shape3D? _heightField(Collider3D c, double ax, double ay) {
    final n = c.heightFieldSize;
    if (n < 4 || c.heights.length < n * n) return null;
    final key = (c.heights, n, c.cellSize, ax, ay);
    final known = _used(_fields, key);
    if (known != null) return known;
    final heights = Float32List(n * n);
    for (var i = 0; i < heights.length; i++) {
      heights[i] = c.heights[i] * ay;
    }
    return _keep(
      _fields,
      key,
      HeightFieldShape3D(heights, n, math.max(c.cellSize * ax, minExtent)),
      fieldLimit,
    );
  }

  /// [cache]'s shape for [key], made the most recently used; null when it
  /// has none.
  static V? _used<K, V>(Map<K, V> cache, K key) {
    if (!cache.containsKey(key)) return null;
    final value = cache.remove(key) as V;
    cache[key] = value;
    return value;
  }

  /// Keeps [value] in [cache] for [key], dropping the least recently used
  /// beyond [limit].
  static V _keep<K, V>(Map<K, V> cache, K key, V value, int limit) {
    cache[key] = value;
    while (cache.length > limit) {
      cache.remove(cache.keys.first);
    }
    return value;
  }

  static Shape3D _place(Shape3D shape, Collider3D c, Vector3 entityScale) {
    final o = c.offset;
    final r = c.rotation;
    if (o.x == 0 && o.y == 0 && o.z == 0 && r.x == 0 && r.y == 0 && r.z == 0) {
      return shape;
    }
    final q = Quaternion.euler(r.x, r.y, r.z);
    return TransformedShape3D(
      shape,
      x: o.x * entityScale.x,
      y: o.y * entityScale.y,
      z: o.z * entityScale.z,
      qx: q.x,
      qy: q.y,
      qz: q.z,
      qw: q.w,
    );
  }

  /// Forgets the shapes made from [model], and what [geometry] kept of it
  /// when that is an [AssetColliderGeometry3D]: after the model was loaded
  /// again, its colliders take its new triangles
  /// (`PhysicsSystem3D.reloadModel` calls this).
  void forgetModel(String model) {
    _models.removeWhere((key, _) => key.$2 == model);
    final source = geometry;
    if (source is AssetColliderGeometry3D) source.forget(model);
  }

  /// Forgets every shape it made.
  void clear() {
    _models.clear();
    _fields.clear();
    _solids.clear();
  }
}
