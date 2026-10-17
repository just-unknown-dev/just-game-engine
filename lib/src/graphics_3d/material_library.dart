import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import 'graphics_shapes.dart';

export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show MaterialAlpha, MaterialChain, MaterialFile, MaterialKind, MaterialUv;

/// The material files (`*.material.json`) the scene's shapes and models
/// draw with, read once each and made into GPU materials.
///
/// Everything arrives in the background: [gpuOf] is null until the file
/// (and, for a variant, every parent) is read, and the material is made
/// again as each of its maps arrives — [revision] goes up each time, so
/// whoever draws with one asks again. Colour and glow maps are read as
/// sRGB, the others as plain numbers; a layered material's layers are each
/// layer file's colour map.
///
/// A variant is drawn with its parents laid under it ([MaterialChain]); an
/// editor shows unsaved edits by [preview]; an entity's own values go on
/// top through [gpuOf]'s `overrides`. Only what uses a file is made again
/// when it changes.
final class MaterialLibrary {
  /// A library reading files through [read] and making GPU things with
  /// [uploader].
  MaterialLibrary(this.uploader, this.read);

  final ModelUploader uploader;

  /// Reads a project file's bytes (the editor's own reader while editing).
  final Future<Uint8List> Function(String path) read;

  /// The files as read, by path.
  final Map<String, _Source> _sources = {};

  /// Unsaved edits standing in for files ([preview]).
  final Map<String, MaterialFile> _previews = {};

  /// What each path draws with, once made.
  final Map<String, _Made> _made = {};

  /// Materials with an entity's values on top, by path and those values.
  final Map<(String, String), GpuMaterial> _overridden = {};

  final Map<(String, bool), _Texture> _textures = {};
  final Set<String> _making = {};
  int _revision = 0;

  /// The most overridden materials kept before they are all let go.
  static const int maxOverridden = 256;

  /// Goes up whenever a material is read, made again or forgotten.
  int get revision => _revision;

  /// The material at [path] as it is drawn: its parents laid under it, an
  /// unsaved edit standing in for a file — reading it the first time asked;
  /// null meanwhile, or when it could not be read ([errorOf]).
  MaterialFile? fileOf(String path) => _madeOf(path)?.file;

  /// The file at [path] as saved (or as [preview] shows it), not resolved:
  /// a variant's own keys only. Null until read.
  MaterialFile? sourceOf(String path) => _previews[path] ?? _source(path).file;

  /// Why [path] could not be read; null when it was, or still is being.
  Object? errorOf(String path) => _sources[path]?.error;

  /// What is wrong with [path]'s parents — one missing, a loop — for a
  /// person; empty when nothing is, or while they are read.
  List<String> problemsOf(String path) => _madeOf(path)?.problems ?? const [];

  /// [path]'s GPU material, with what of its maps has arrived and
  /// [overrides] (an entity's values, by [MaterialFile.animatableKeys])
  /// on top; null until the file is read, or when it is broken.
  GpuMaterial? gpuOf(String path, {Map<String, Object?> overrides = const {}}) {
    final made = _madeOf(path);
    if (made == null) return null;
    final shared = made.gpu ??= _make(made, made.file);
    if (overrides.isEmpty) return shared;
    final key = (path, _keyOf(overrides));
    final known = _overridden[key];
    if (known != null) return known;
    if (_overridden.length >= maxOverridden) _overridden.clear();
    return _overridden[key] = _make(made, made.file.withValues(overrides));
  }

  /// Draws [path] as [file] — unsaved edits — until [endPreview]: what uses
  /// it, its variants and the layered materials it is a layer of follow.
  void preview(String path, MaterialFile file) {
    if (_previews[path] == file) return;
    _previews[path] = file;
    _changed(path);
  }

  /// [path] drawn as saved again.
  void endPreview(String path) {
    if (_previews.remove(path) != null) _changed(path);
  }

  /// Whether [path] is drawn from an unsaved edit.
  bool isPreviewing(String path) => _previews.containsKey(path);

  static String _keyOf(Map<String, Object?> overrides) {
    final keys = overrides.keys.toList()..sort();
    return jsonEncode([
      for (final k in keys) [k, overrides[k]],
    ]);
  }

  _Source _source(String path) {
    final known = _sources[path];
    if (known != null) return known;
    final source = _sources[path] = _Source();
    _load(path, source);
    return source;
  }

  // Reads [path] into [source]. What it held stays until the new read
  // arrives, so a file saved again does not flicker to its users' own look.
  void _load(String path, _Source source) {
    final ticket = ++source.ticket;
    bool current() =>
        identical(_sources[path], source) && ticket == source.ticket;
    unawaited(
      read(path).then(
        (bytes) {
          if (!current()) return;
          try {
            source
              ..file = MaterialFile.parse(utf8.decode(bytes))
              ..error = null;
          } on FormatException catch (e) {
            source
              ..file = null
              ..error = e;
            debugPrint(
              'just_game_engine: the material $path is broken: ${e.message}',
            );
          }
          // A variant's parent and a layered one's layers are read now, not
          // when they are next asked for.
          final file = source.file;
          if (file != null) {
            if (file.isVariant) _source(file.parent);
            for (final layer in file.layers.take(MaterialFile.maxLayers)) {
              _source(layer);
            }
          }
          _changed(path);
        },
        onError: (Object error) {
          if (!current()) return;
          source
            ..file = null
            ..error = error;
          debugPrint('just_game_engine: no material $path: $error');
          _changed(path);
        },
      ),
    );
  }

  _Made? _madeOf(String path) {
    final known = _made[path];
    if (known != null) return known;
    if (!_making.add(path)) return null; // a layer that holds itself
    try {
      final pending = <String>[];
      MaterialFile? lookup(String p) {
        final preview = _previews[p];
        if (preview != null) return preview;
        final source = _source(p);
        if (source.file == null && source.error == null) pending.add(p);
        return source.file;
      }

      final ResolvedMaterial<MaterialFile> resolved;
      try {
        resolved = MaterialChain.resolve3D(path, lookup);
      } on StateError {
        return null; // the file itself is being read, or could not be
      }
      if (pending.isNotEmpty) return null; // a parent is still being read
      final file = resolved.value;
      final deps = {...resolved.chain};
      final layers = <MaterialFile?>[];
      for (final layer in file.layers.take(MaterialFile.maxLayers)) {
        final made = _madeOf(layer);
        layers.add(made?.file);
        deps
          ..add(layer)
          ..addAll(made?.deps ?? const {});
      }
      return _made[path] = _Made(file, resolved.problems, deps, layers);
    } finally {
      _making.remove(path);
    }
  }

  // [path] changed (read, previewed, reloaded): what used it is made again.
  void _changed(String path) {
    final gone = [
      for (final e in _made.entries)
        if (e.key == path || e.value.deps.contains(path)) e.key,
    ];
    for (final p in gone) {
      _made.remove(p);
    }
    if (gone.isNotEmpty) {
      _overridden.removeWhere((key, _) => gone.contains(key.$1));
    }
    _revision++;
  }

  GpuMaterial _make(_Made made, MaterialFile file) {
    final layered = file.kind == MaterialKind.layered;
    final List<(GpuTexture, GpuSampler)?> maps;
    if (layered) {
      maps = [
        for (var i = 0; i < 4; i++)
          i < made.layers.length
              ? _map(made, made.layers[i]?.colorMap ?? '', srgb: true)
              : null,
      ];
    } else {
      maps = [
        _map(made, file.colorMap, srgb: true),
        _map(made, file.metalRoughMap, srgb: false),
        _map(made, file.normalMap, srgb: false),
        _map(made, file.occlusionMap, srgb: false),
        _map(made, file.emissionMap, srgb: true),
      ];
    }
    return uploader.material(dataOf(file, layers: made.layers), maps: maps);
  }

  (GpuTexture, GpuSampler)? _map(
    _Made made,
    String path, {
    required bool srgb,
  }) {
    if (path.isEmpty) return null;
    made.textures.add(path);
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
              _textureChanged(path);
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

  // A map arrived or went: what draws with it is made again.
  void _textureChanged(String path) {
    for (final e in _made.entries) {
      if (e.value.textures.contains(path)) {
        e.value.gpu = null;
        _overridden.removeWhere((key, _) => key.$1 == e.key);
      }
    }
    _revision++;
  }

  /// [file]'s material with every map read first — for a picture of it,
  /// not a scene drawn frame by frame. A variant's parents, its layers'
  /// files and the maps are read through [read] too (or taken from a
  /// [preview]). Throws what reading the file's maps or layers throws; a
  /// parent that cannot be read is skipped.
  Future<GpuMaterial> complete(MaterialFile file) async {
    Future<(GpuTexture, GpuSampler)?> map(
      String path, {
      required bool srgb,
    }) async {
      if (path.isEmpty) return null;
      final texture = await uploader.uploadImage(await read(path), srgb: srgb);
      return texture == null ? null : (texture, GpuSampler.linearRepeat);
    }

    final resolved = await _resolveNow(file);
    final layers = [
      for (final l in resolved.layers.take(MaterialFile.maxLayers))
        await _resolveNow(await _readNow(l)),
    ];
    final maps = resolved.kind == MaterialKind.layered
        ? [
            for (var i = 0; i < 4; i++)
              i < layers.length
                  ? await map(layers[i].colorMap, srgb: true)
                  : null,
          ]
        : [
            await map(resolved.colorMap, srgb: true),
            await map(resolved.metalRoughMap, srgb: false),
            await map(resolved.normalMap, srgb: false),
            await map(resolved.occlusionMap, srgb: false),
            await map(resolved.emissionMap, srgb: true),
          ];
    return uploader.material(dataOf(resolved, layers: layers), maps: maps);
  }

  Future<MaterialFile> _readNow(String path) async =>
      _previews[path] ?? MaterialFile.parse(utf8.decode(await read(path)));

  Future<MaterialFile> _resolveNow(MaterialFile file) async {
    if (!file.isVariant) return file;
    final parents = <String, MaterialFile>{};
    var at = file.parent;
    while (at.isNotEmpty &&
        !parents.containsKey(at) &&
        parents.length < MaterialChain.maxDepth) {
      final MaterialFile parent;
      try {
        parent = await _readNow(at);
      } on Object {
        break;
      }
      parents[at] = parent;
      at = parent.parent;
    }
    const self = '\u0000';
    return MaterialChain.resolve3D(
      self,
      (p) => p == self ? file : parents[p],
    ).value;
  }

  /// Reads [path] again — a material file, or a map one uses — after it
  /// changed on disk. What it was is drawn until it arrives.
  void reload(String path) {
    final source = _sources[path];
    if (source != null) _load(path, source);
    for (final srgb in const [true, false]) {
      if (_textures.remove((path, srgb)) != null) _textureChanged(path);
    }
  }

  /// Lets go of everything, unsaved previews too.
  void clear() {
    _sources.clear();
    _previews.clear();
    _made.clear();
    _overridden.clear();
    _textures.clear();
    _revision++;
  }

  /// [file]'s values as the renderer takes them: colours made linear, the
  /// maps' tiling, offset and turn on each; a layered one's layers tiled as
  /// each layer file says ([layers], read or null).
  static MaterialData dataOf(
    MaterialFile file, {
    List<MaterialFile?> layers = const [],
  }) {
    final color = Color(file.color);
    final (r, g, b) = GraphicsShapes.linear(color);
    final (er, eg, eb) = GraphicsShapes.linear(Color(file.emission));
    final blend = file.alpha == MaterialAlpha.blend;
    final alpha = color.a * (blend ? file.opacity.clamp(0.0, 1.0) : 1);
    TextureRef ref(int slot) => TextureRef(
      slot,
      scale: (file.tilingX, file.tilingY),
      offset: (file.offsetX, file.offsetY),
      rotation: file.rotation * math.pi / 180,
    );
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
      occlusionStrength: file.occlusionStrength,
      emissive: (er, eg, eb),
      emissiveTexture: file.emissionMap.isEmpty ? null : ref(4),
      emissiveStrength: file.emissionStrength,
      alphaMode: switch (file.alpha) {
        MaterialAlpha.opaque => AlphaMode.opaque,
        MaterialAlpha.cutout => AlphaMode.mask,
        MaterialAlpha.blend => AlphaMode.blend,
      },
      alphaCutoff: file.alphaCutoff,
      doubleSided: file.doubleSided,
      unlit: file.unlit,
      uvMode: file.uv == MaterialUv.world ? UvMode.world : UvMode.natural,
      layered: file.kind == MaterialKind.layered,
      layerTiling: (tiling(0), tiling(1), tiling(2), tiling(3)),
    );
  }
}

final class _Source {
  MaterialFile? file;
  Object? error;

  /// Counts reads, so only the newest one lands.
  int ticket = 0;
}

final class _Made {
  _Made(this.file, this.problems, this.deps, this.layers);

  /// What it draws with: resolved, previews shown.
  final MaterialFile file;

  final List<String> problems;

  /// Every file it was made from: its own, its parents, its layers'.
  final Set<String> deps;

  /// Its layers' files, resolved, or null while one is read.
  final List<MaterialFile?> layers;

  /// The maps it draws with.
  final Set<String> textures = {};

  GpuMaterial? gpu;
}

final class _Texture {
  GpuTexture? texture;
}
