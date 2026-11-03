part of '../asset_management.dart';

/// A 3-D model, as the engine sees one: its bounds and, for picking and
/// mesh colliders, its triangles. Drawing it is someone else's business.
///
/// The engine has no model loader of its own. A renderer package registers
/// one for [AssetType.model] (`AssetManager.registerLoader`) that returns a
/// subclass, which also holds whatever the renderer needs to draw it.
abstract class ModelAsset extends Asset {
  /// A model to be loaded from [path].
  ModelAsset(String path) : super(path, AssetType.model);

  /// The model's bounds in its own space, after any axis correction made on
  /// import; empty until loaded.
  Aabb3 get bounds;

  /// The names of its meshes, in a stable order.
  List<String> get meshNames;

  /// The triangles of the mesh called [meshName] in model space, or null
  /// when it has none or keeps them only on the GPU.
  ModelGeometry? geometryOf(String meshName);
}

/// Triangles on the CPU: three indices per triangle into [positions].
final class ModelGeometry {
  /// Triangles over [positions] (x, y, z per vertex).
  const ModelGeometry(this.positions, this.indices);

  /// Vertex positions, three floats each.
  final Float32List positions;

  /// Three vertex indices per triangle.
  final Uint32List indices;

  /// How many triangles there are.
  int get triangleCount => indices.length ~/ 3;
}
