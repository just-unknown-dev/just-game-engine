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
import 'package:meta/meta.dart' show internal;

import 'linear_color.dart';

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
///
/// What a level no longer uses goes with [retainOnly]; a material made
/// for an entity's own values goes as soon as the last user that counted
/// itself ([hold]) lets go of it ([release]).
final class Material3DLibrary {
  /// A library reading files through [read] and making GPU things with
  /// [uploader].
  Material3DLibrary(this.uploader, this.read);

  /// Makes the GPU materials and uploads the maps.
  final ModelUploader uploader;

  /// Reads a project file's bytes (the editor's own reader while editing).
  final Future<Uint8List> Function(String path) read;

  /// The files as read, by path.
  final Map<String, _Source> _sources = {};

  /// Unsaved edits standing in for files ([preview]).
  final Map<String, Material3DFile> _previews = {};

  /// What each path draws with, once made.
  final Map<String, _Made> _made = {};

  /// The [revision] at which each path last could not be made (its file or
  /// a parent still being read, or unreadable): asked again before
  /// anything changes, the answer is the same.
  final Map<String, int> _unmadeAt = {};

  /// Materials with an entity's values on top, by path and those values;
  /// the least recently asked for first.
  final Map<(String, String), _Overridden> _overridden = {};

  /// The key each of [_overridden]'s materials is kept under.
  final Map<GpuMaterial, (String, String)> _overriddenKeys = Map.identity();

  final Map<(String, bool), _Texture> _textures = {};
  final Set<String> _making = {};
  int _revision = 0;

  /// The most materials with an entity's values kept that no user holds;
  /// past it, the least recently asked for goes.
  static const int maxOverridden = 256;

  /// Goes up whenever a material is read, made again or forgotten.
  int get revision => _revision;

  /// Every material path asked for ([fileOf], [gpuOf]) while it is not
  /// null: the scene renderer sets it while a render provider builds, to
  /// learn which material files that provider draws with.
  @internal
  Set<String>? asked;

  /// The material at [path] as it is drawn: its parents laid under it, an
  /// unsaved edit standing in for a file — reading it the first time asked;
  /// null meanwhile, or when it could not be read ([errorOf]).
  Material3DFile? fileOf(String path) {
    asked?.add(path);
    return _madeOf(path)?.file;
  }

  /// The file at [path] as saved (or as [preview] shows it), not resolved:
  /// a variant's own keys only. Null until read.
  Material3DFile? sourceOf(String path) =>
      _previews[path] ?? _source(path).file;

  /// Why [path] could not be read; null when it was, or still is being.
  Object? errorOf(String path) => _sources[path]?.error;

  /// What is wrong with [path]'s parents — one missing, a loop — for a
  /// person; empty when nothing is, or while they are read.
  List<String> problemsOf(String path) => _madeOf(path)?.problems ?? const [];

  /// [path]'s GPU material, with what of its maps has arrived and
  /// [overrides] (an entity's values, by [Material3DFile.animatableKeys])
  /// on top; null until the file is read, or when it is broken.
  GpuMaterial? gpuOf(String path, {Map<String, Object?> overrides = const {}}) {
    asked?.add(path);
    final made = _madeOf(path);
    if (made == null) return null;
    final shared = made.gpu ??= _make(made, made.file);
    if (overrides.isEmpty) return shared;
    final key = (path, _keyOf(overrides));
    final known = _overridden.remove(key);
    if (known != null) {
      // Asked for again: the most recent now.
      _overridden[key] = known;
      return known.gpu;
    }
    if (_overridden.length >= maxOverridden) _evictOverridden();
    final gpu = _make(made, made.file.withValues(overrides));
    _overridden[key] = _Overridden(gpu);
    _overriddenKeys[gpu] = key;
    return gpu;
  }

  /// Counts one more user of [material], one [gpuOf] made with an entity's
  /// values, until it calls [release]. Any other material is not counted.
  void hold(GpuMaterial material) {
    final key = _overriddenKeys[material];
    if (key == null) return;
    _overridden[key]?.holders++;
  }

  /// One user of [material] (counted by [hold]) stopped drawing it: once
  /// none does, it is let go — made again if asked for again.
  void release(GpuMaterial material) {
    final key = _overriddenKeys[material];
    if (key == null) return;
    final entry = _overridden[key];
    if (entry == null || entry.holders <= 0 || --entry.holders > 0) return;
    _overridden.remove(key);
    _overriddenKeys.remove(material);
  }

  // Full: the least recently asked for that no user holds goes.
  void _evictOverridden() {
    (String, String)? oldest;
    for (final MapEntry(:key, :value) in _overridden.entries) {
      if (value.holders > 0) continue;
      oldest = key;
      break;
    }
    if (oldest == null) return;
    _overriddenKeys.remove(_overridden.remove(oldest)!.gpu);
  }

  void _forgetOverridden(bool Function((String, String) key) test) {
    _overridden.removeWhere((key, value) {
      if (!test(key)) return false;
      _overriddenKeys.remove(value.gpu);
      return true;
    });
  }

  /// Draws [path] as [file] — unsaved edits — until [endPreview]: what uses
  /// it, its variants and the layered materials it is a layer of follow.
  void preview(String path, Material3DFile file) {
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
              ..file = Material3DFile.parse(utf8.decode(bytes))
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
            for (final layer in file.layers.take(Material3DFile.maxLayers)) {
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
    // Could not be made, and nothing has changed since.
    if (_unmadeAt[path] == _revision) return null;
    if (!_making.add(path)) return null; // a layer that holds itself
    try {
      final pending = <String>[];
      // Every file looked for, found or not: a parent that is missing now
      // makes this again once it is there.
      final asked = <String>{};
      Material3DFile? lookup(String p) {
        asked.add(p);
        final preview = _previews[p];
        if (preview != null) return preview;
        final source = _source(p);
        if (source.file == null && source.error == null) pending.add(p);
        return source.file;
      }

      final ResolvedMaterial<Material3DFile> resolved;
      try {
        resolved = MaterialChain.resolve3D(path, lookup);
      } on StateError {
        // The file itself is being read, or could not be.
        _unmadeAt[path] = _revision;
        return null;
      }
      if (pending.isNotEmpty) {
        // A parent is still being read.
        _unmadeAt[path] = _revision;
        return null;
      }
      final file = resolved.value;
      final deps = {...resolved.chain, ...asked};
      final layers = <Material3DFile?>[];
      for (final layer in file.layers.take(Material3DFile.maxLayers)) {
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
    if (gone.isNotEmpty) _forgetOverridden((key) => gone.contains(key.$1));
    _revision++;
  }

  GpuMaterial _make(_Made made, Material3DFile file) {
    final layered = file.kind == Material3DKind.layered;
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
    final texture = (_textures[key] ?? _readMap(key)).texture;
    return texture == null ? null : (texture, GpuSampler.linearRepeat);
  }

  /// Starts reading the map [key] names; [showing] is drawn until it
  /// arrives (what it was, when it is read again).
  _Texture _readMap((String, bool) key, {GpuTexture? showing}) {
    final (path, srgb) = key;
    final entry = _textures[key] = _Texture()..texture = showing;
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
    return entry;
  }

  // A map arrived or went: what draws with it is made again.
  void _textureChanged(String path) {
    final gone = <String>{};
    for (final e in _made.entries) {
      if (e.value.textures.contains(path)) {
        e.value.gpu = null;
        gone.add(e.key);
      }
    }
    if (gone.isNotEmpty) _forgetOverridden((key) => gone.contains(key.$1));
    _revision++;
  }

  /// [file]'s material with every map read first — for a picture of it,
  /// not a scene drawn frame by frame. A variant's parents, its layers'
  /// files and the maps are read through [read] too (or taken from a
  /// [preview]). Throws what reading the file's maps or layers throws; a
  /// parent that cannot be read is skipped.
  Future<GpuMaterial> complete(Material3DFile file) async {
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
      for (final l in resolved.layers.take(Material3DFile.maxLayers))
        await _resolveNow(await _readNow(l)),
    ];
    final maps = resolved.kind == Material3DKind.layered
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

  Future<Material3DFile> _readNow(String path) async =>
      _previews[path] ?? Material3DFile.parse(utf8.decode(await read(path)));

  Future<Material3DFile> _resolveNow(Material3DFile file) async {
    if (!file.isVariant) return file;
    final parents = <String, Material3DFile>{};
    var at = file.parent;
    while (at.isNotEmpty &&
        !parents.containsKey(at) &&
        parents.length < MaterialChain.maxDepth) {
      final Material3DFile parent;
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
      final key = (path, srgb);
      final known = _textures[key];
      if (known != null) _readMap(key, showing: known.texture);
    }
  }

  /// Lets go of every material file no path in [keep] is drawn with — not
  /// one of them, nor a parent or a layer of one — with the maps only they
  /// use and the materials made from them: what a level no longer uses
  /// leaves the GPU. Unsaved previews stay. Returns how many files went.
  int retainOnly(Iterable<String> keep) {
    final needed = <String>{};
    final maps = <String>{};
    void need(String path) {
      if (path.isEmpty || !needed.add(path)) return;
      final file = _previews[path] ?? _sources[path]?.file;
      if (file == null) return;
      maps.addAll([
        file.colorMap,
        file.metalRoughMap,
        file.normalMap,
        file.occlusionMap,
        file.emissionMap,
      ]);
      if (file.isVariant) need(file.parent);
      file.layers.take(Material3DFile.maxLayers).forEach(need);
    }

    keep.forEach(need);
    _previews.keys.toList().forEach(need);
    final before = _sources.length;
    _sources.removeWhere((path, _) => !needed.contains(path));
    _made.removeWhere((path, _) => !needed.contains(path));
    _forgetOverridden((key) => !needed.contains(key.$1));
    _textures.removeWhere((key, _) => !maps.contains(key.$1));
    _unmadeAt.clear();
    _revision++;
    return before - _sources.length;
  }

  /// Lets go of everything, unsaved previews too.
  void clear() {
    _sources.clear();
    _previews.clear();
    _made.clear();
    _unmadeAt.clear();
    _overridden.clear();
    _overriddenKeys.clear();
    _textures.clear();
    _revision++;
  }

  /// [file]'s values as the renderer takes them: colours made linear, the
  /// maps' tiling, offset and turn on each; a layered one's layers tiled as
  /// each layer file says ([layers], read or null).
  static MaterialData dataOf(
    Material3DFile file, {
    List<Material3DFile?> layers = const [],
  }) {
    final color = Color(file.color);
    final (r, g, b) = LinearColor.of(color);
    final (er, eg, eb) = LinearColor.of(Color(file.emission));
    final blend = file.alpha == Material3DAlpha.blend;
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
        Material3DAlpha.opaque => AlphaMode.opaque,
        Material3DAlpha.cutout => AlphaMode.mask,
        Material3DAlpha.blend => AlphaMode.blend,
      },
      alphaCutoff: file.alphaCutoff,
      doubleSided: file.doubleSided,
      unlit: file.unlit,
      uvMode: file.uv == Material3DUv.world ? UvMode.world : UvMode.natural,
      layered: file.kind == Material3DKind.layered,
      layerTiling: (tiling(0), tiling(1), tiling(2), tiling(3)),
    );
  }
}

final class _Source {
  Material3DFile? file;
  Object? error;

  /// Counts reads, so only the newest one lands.
  int ticket = 0;
}

final class _Made {
  _Made(this.file, this.problems, this.deps, this.layers);

  /// What it draws with: resolved, previews shown.
  final Material3DFile file;

  final List<String> problems;

  /// Every file it was made from: its own, its parents, its layers'.
  final Set<String> deps;

  /// Its layers' files, resolved, or null while one is read.
  final List<Material3DFile?> layers;

  /// The maps it draws with.
  final Set<String> textures = {};

  GpuMaterial? gpu;
}

final class _Texture {
  GpuTexture? texture;
}

final class _Overridden {
  _Overridden(this.gpu);

  final GpuMaterial gpu;

  /// How many users count it ([Material3DLibrary.hold]).
  int holders = 0;
}
