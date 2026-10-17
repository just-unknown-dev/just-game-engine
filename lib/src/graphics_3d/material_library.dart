import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import 'graphics_shapes.dart';

export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show MaterialFile, MaterialKind, MaterialUv;

/// The material files (`*.material.json`) the scene's shapes and models
/// draw with, read once each and made into GPU materials.
///
/// Everything arrives in the background: [gpuOf] is null until the file
/// is read, and the material is made again as each of its maps arrives —
/// [revision] goes up each time, so whoever draws with one asks again.
/// Colour and glow maps are read as sRGB, the others as plain numbers; a
/// layered material's layers are each layer file's colour map.
final class MaterialLibrary {
  /// A library reading files through [read] and making GPU things with
  /// [uploader].
  MaterialLibrary(this.uploader, this.read);

  final ModelUploader uploader;

  /// Reads a project file's bytes (the editor's own reader while editing).
  final Future<Uint8List> Function(String path) read;

  final Map<String, _Entry> _entries = {};
  final Map<(String, bool), _Texture> _textures = {};
  int _revision = 0;

  /// Goes up whenever a material is read, made again or forgotten.
  int get revision => _revision;

  /// The material file at [path], once read — reading it the first time
  /// asked; null meanwhile, or when it could not be read ([errorOf]).
  MaterialFile? fileOf(String path) => _entry(path).file;

  /// Why [path] could not be read; null when it was, or still is being.
  Object? errorOf(String path) => _entries[path]?.error;

  /// [path]'s GPU material, with what of its maps has arrived; null until
  /// the file is read, or when it is broken.
  GpuMaterial? gpuOf(String path) {
    final entry = _entry(path);
    final file = entry.file;
    if (file == null) return null;
    return entry.gpu ??= _make(file);
  }

  _Entry _entry(String path) {
    final known = _entries[path];
    if (known != null) return known;
    final entry = _entries[path] = _Entry();
    unawaited(
      read(path).then(
        (bytes) {
          if (!identical(_entries[path], entry)) return;
          try {
            entry.file = MaterialFile.parse(utf8.decode(bytes));
          } on FormatException catch (e) {
            entry.error = e;
            debugPrint('just_game_engine: the material $path is broken: ${e.message}');
          }
          _revision++;
        },
        onError: (Object error) {
          if (!identical(_entries[path], entry)) return;
          entry.error = error;
          debugPrint('just_game_engine: no material $path: $error');
          _revision++;
        },
      ),
    );
    return entry;
  }

  GpuMaterial _make(MaterialFile file) {
    final layered = file.kind == MaterialKind.layered;
    final List<(GpuTexture, GpuSampler)?> maps;
    if (layered) {
      maps = [
        for (var i = 0; i < 4; i++)
          i < file.layers.length ? _map(fileOf(file.layers[i])?.colorMap ?? '', srgb: true) : null,
      ];
    } else {
      maps = [
        _map(file.colorMap, srgb: true),
        _map(file.metalRoughMap, srgb: false),
        _map(file.normalMap, srgb: false),
        _map(file.occlusionMap, srgb: false),
        _map(file.emissionMap, srgb: true),
      ];
    }
    return uploader.material(dataOf(file, layers: [for (final l in file.layers) fileOf(l)]), maps: maps);
  }

  (GpuTexture, GpuSampler)? _map(String path, {required bool srgb}) {
    if (path.isEmpty) return null;
    final key = (path, srgb);
    final known = _textures[key];
    if (known != null) {
      final texture = known.texture;
      return texture == null ? null : (texture, GpuSampler.linearRepeat);
    }
    final entry = _textures[key] = _Texture();
    unawaited(
      read(path)
          .then((bytes) => uploader.uploadImage(bytes, srgb: srgb))
          .then(
            (texture) {
              if (!identical(_textures[key], entry)) return;
              if (texture == null) {
                debugPrint('just_game_engine: could not decode the map $path');
                return;
              }
              entry.texture = texture;
              _remake();
            },
            onError: (Object error) {
              if (identical(_textures[key], entry)) {
                debugPrint('just_game_engine: no map $path: $error');
              }
            },
          ),
    );
    return null;
  }

  // A map arrived: every material is made again, with what it has now.
  void _remake() {
    for (final e in _entries.values) {
      e.gpu = null;
    }
    _revision++;
  }

  /// [file]'s material with every map read first — for a picture of it,
  /// not a scene drawn frame by frame. Its layers' files and maps are read
  /// through [read] too. Throws what reading or parsing throws.
  Future<GpuMaterial> complete(MaterialFile file) async {
    Future<(GpuTexture, GpuSampler)?> map(String path, {required bool srgb}) async {
      if (path.isEmpty) return null;
      final texture = await uploader.uploadImage(await read(path), srgb: srgb);
      return texture == null ? null : (texture, GpuSampler.linearRepeat);
    }

    final layers = [
      for (final l in file.layers.take(MaterialFile.maxLayers))
        MaterialFile.parse(utf8.decode(await read(l))),
    ];
    final maps = file.kind == MaterialKind.layered
        ? [
            for (var i = 0; i < 4; i++)
              i < layers.length ? await map(layers[i].colorMap, srgb: true) : null,
          ]
        : [
            await map(file.colorMap, srgb: true),
            await map(file.metalRoughMap, srgb: false),
            await map(file.normalMap, srgb: false),
            await map(file.occlusionMap, srgb: false),
            await map(file.emissionMap, srgb: true),
          ];
    return uploader.material(dataOf(file, layers: layers), maps: maps);
  }

  /// Reads [path] again — a material file, or a map one uses — after it
  /// changed on disk.
  void reload(String path) {
    var changed = _entries.remove(path) != null;
    for (final srgb in const [true, false]) {
      if (_textures.remove((path, srgb)) != null) changed = true;
    }
    if (!changed) return;
    _remake();
  }

  /// Lets go of everything.
  void clear() {
    _entries.clear();
    _textures.clear();
    _revision++;
  }

  /// [file]'s values as the renderer takes them: colours made linear, the
  /// maps' tiling on each; a layered one's layers tiled as each layer file
  /// says ([layers], read or null).
  static MaterialData dataOf(MaterialFile file, {List<MaterialFile?> layers = const []}) {
    final color = Color(file.color);
    final (r, g, b) = GraphicsShapes.linear(color);
    final (er, eg, eb) = GraphicsShapes.linear(Color(file.emission));
    final alpha = color.a * file.opacity;
    final scale = (file.tilingX, file.tilingY);
    TextureRef ref(int slot) => TextureRef(slot, scale: scale);
    double tiling(int i) => i < layers.length ? (layers[i]?.tilingX ?? 1) : 1;
    return MaterialData(
      baseColor: (r, g, b, alpha),
      baseColorTexture: ref(0),
      metallic: file.metallic,
      roughness: file.roughness,
      metallicRoughnessTexture: file.metalRoughMap.isEmpty ? null : ref(1),
      normalTexture: file.normalMap.isEmpty ? null : ref(2),
      normalScale: file.normalScale,
      occlusionTexture: file.occlusionMap.isEmpty ? null : ref(3),
      emissive: (er, eg, eb),
      emissiveTexture: file.emissionMap.isEmpty ? null : ref(4),
      emissiveStrength: file.emissionStrength,
      alphaMode: alpha < 1 ? AlphaMode.blend : AlphaMode.opaque,
      doubleSided: file.doubleSided,
      unlit: file.unlit,
      uvMode: file.uv == MaterialUv.world ? UvMode.world : UvMode.natural,
      layered: file.kind == MaterialKind.layered,
      layerTiling: (tiling(0), tiling(1), tiling(2), tiling(3)),
    );
  }
}

final class _Entry {
  MaterialFile? file;
  Object? error;
  GpuMaterial? gpu;
}

final class _Texture {
  GpuTexture? texture;
}
