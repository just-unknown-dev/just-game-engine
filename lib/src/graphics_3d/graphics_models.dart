import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetBundle, AssetManifest;
import 'package:just_dart/just_dart.dart' show Aabb3, JustMatrix4, Vector3;
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/renderer.dart';

import '../subsystems/assets/assets.dart';

/// The models a game's scenes use, each loaded once per asset path: read
/// from [bundle], parsed, uploaded with [uploader].
final class GraphicsModels {
  /// A cache loading through [bundle] and uploading with [uploader].
  GraphicsModels(this.bundle, this.uploader);

  /// Where model files are read from.
  final AssetBundle bundle;

  /// Uploads parsed models.
  final ModelUploader uploader;

  final Map<String, _Entry> _entries = {};

  /// Called each time a model finishes loading, and when one is to be
  /// loaded again ([reload]).
  final List<void Function(String path)> listeners = [];

  /// Reads a file in place of [bundle] when it returns bytes; null falls
  /// back to the bundle. An editor sets it to read the project's files,
  /// which the bundle — a snapshot from when the app was built — may not
  /// have yet.
  Future<Uint8List?> Function(String path)? readOverride;

  /// Forgets the model at [path] so the next use loads it again (its file
  /// or its cooked copy changed), and tells [listeners].
  void reload(String path) {
    if (_entries.remove(path) == null) return;
    for (final listener in List.of(listeners)) {
      listener(path);
    }
  }

  /// Every path asked for so far.
  Iterable<String> get paths => _entries.keys;

  /// The model at [path] once it has loaded; null before that (the first
  /// call starts loading it) or when it failed to load.
  GpuModel? get(String path) => _entry(path).model;

  /// The parsed data of the model at [path], once loaded.
  ModelData? dataOf(String path) => _entry(path).model?.data;

  /// Why the model at [path] did not load, or null.
  Object? errorOf(String path) => _entries[path]?.error;

  /// Loads the model at [path], or returns the load already under way.
  Future<GpuModel> load(String path) => _entry(path).future;

  _Entry _entry(String path) => _entries.putIfAbsent(path, () {
    final entry = _Entry();
    entry.future = _load(path).then(
      (model) {
        entry.model = model;
        for (final listener in List.of(listeners)) {
          listener(path);
        }
        return model;
      },
      onError: (Object error) {
        entry.error = error;
        debugPrint('just_game_engine: could not load "$path": $error');
        throw error;
      },
    );
    // A failure is reported once, here; callers polling [get] see null.
    entry.future.ignore();
    return entry;
  });

  Future<GpuModel> _load(String path) async {
    // A cooked copy beside the file wins: nothing to parse or decode.
    final cooked = await _readCooked(path);
    if (cooked != null) {
      return uploader.upload(CookedModel.read(cooked, name: path));
    }
    final bytes = await _read(path);
    final folder = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/') + 1)
        : '';
    final data = await loadModelData(
      bytes,
      name: path,
      fetch: (uri) => _read('$folder$uri'),
    );
    return uploader.upload(data);
  }

  Future<Uint8List?> _readCooked(String path) async {
    if (path.toLowerCase().endsWith(ModelImportSettings.cookedExtension)) {
      return null;
    }
    final cookedPath = ModelImportSettings.cookedOf(path);
    try {
      // The bundle is only asked for a copy its manifest lists: on the web a
      // missing asset is a failed request the browser console reports.
      final bytes =
          await readOverride?.call(cookedPath) ??
          (await _bundleMayHave(cookedPath)
              ? await _fromBundle(cookedPath)
              : null);
      return bytes != null && CookedModel.isCooked(bytes) ? bytes : null;
    } on Object {
      return null;
    }
  }

  Future<Set<String>?>? _bundleAssets;

  /// False only when the bundle's asset manifest is readable and lacks
  /// [path].
  Future<bool> _bundleMayHave(String path) async {
    final assets = await (_bundleAssets ??= AssetManifest.loadFromAssetBundle(
      bundle,
    ).then<Set<String>?>((m) => m.listAssets().toSet(), onError: (_) => null));
    return assets == null || assets.contains(path);
  }

  /// The bytes of the file at [path], through [readOverride] or [bundle].
  Future<Uint8List> read(String path) => _read(path);

  Future<Uint8List> _read(String path) async {
    final override = readOverride;
    if (override != null) {
      final bytes = await override(path);
      if (bytes != null) return bytes;
    }
    return _fromBundle(path);
  }

  Future<Uint8List> _fromBundle(String path) async {
    final data = await bundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

final class _Entry {
  late Future<GpuModel> future;
  GpuModel? model;
  Object? error;
}

/// The engine's view of a model loaded by just_graphics_engine: its bounds
/// and triangles in engine axes (+Y down), for picking and mesh colliders.
final class GraphicsModelAsset extends ModelAsset {
  /// The model at [path], loaded through [models].
  GraphicsModelAsset(super.path, this.models);

  /// Where it is loaded.
  final GraphicsModels models;

  final Aabb3 _bounds = Aabb3();
  final Map<String, ModelGeometry?> _geometry = {};
  List<String> _meshNames = const [];
  ModelData? _data;

  @override
  Aabb3 get bounds => _bounds;

  @override
  List<String> get meshNames => _meshNames;

  /// Reads the model again — after [GraphicsModels.reload] — so its
  /// bounds, mesh names and triangles are the new file's.
  Future<void> reload() async {
    _geometry.clear();
    await load();
  }

  @override
  Future<void> load() async {
    final model = await models.load(path);
    _data = model.data;
    model.data.bounds.transformInto(gltfToEngine, _bounds);
    _meshNames = [
      for (var i = 0; i < model.data.meshes.length; i++)
        model.data.meshes[i].name ?? 'mesh $i',
    ];
    markAsLoaded();
  }

  @override
  ModelGeometry? geometryOf(String meshName) {
    final data = _data;
    if (data == null) return null;
    return _geometry.putIfAbsent(meshName, () {
      final index = _meshNames.indexOf(meshName);
      if (index < 0) return null;
      return trianglesOf(data, mesh: index);
    });
  }

  /// The triangles of [data] in engine axes (+Y down), placed by its nodes
  /// in its rest pose: of mesh [mesh] alone, or of every mesh when null.
  /// Null when there are none.
  static ModelGeometry? trianglesOf(ModelData data, {int? mesh}) {
    final positions = <double>[];
    final indices = <int>[];
    final point = Vector3.zero();
    data.forEachNode((node, modelFromNode) {
      final index = data.nodes[node].mesh;
      if (index == null || index >= data.meshes.length) return;
      if (mesh != null && index != mesh) return;
      final m = gltfToEngine.multiplied(modelFromNode);
      for (final p in data.meshes[index].primitives) {
        final base = positions.length ~/ 3;
        for (var v = 0; v < p.vertexCount; v++) {
          final o = v * kVertexFloats;
          point.setValues(p.vertices[o], p.vertices[o + 1], p.vertices[o + 2]);
          m.transformPointInto(point, point);
          positions.addAll([point.x, point.y, point.z]);
        }
        indices.addAll(p.indices.map((i) => i + base));
      }
    });
    if (indices.isEmpty) return null;
    return ModelGeometry(
      Float32List.fromList(positions),
      Uint32List.fromList(indices),
    );
  }

  @override
  void unload() {
    _data = null;
    _geometry.clear();
    markAsUnloaded();
  }

  @override
  int getMemoryUsage() => 0;
}

/// Creates [GraphicsModelAsset]s for the engine's asset manager.
final class GraphicsModelLoader extends AssetLoader {
  /// A loader using [models].
  GraphicsModelLoader(this.models);

  /// Where models are loaded.
  final GraphicsModels models;

  @override
  Asset createAsset(String path) => GraphicsModelAsset(path, models);
}
