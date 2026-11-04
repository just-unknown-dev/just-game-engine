import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_dart/just_dart.dart' show Vector3;
import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show Material3DUv;
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import 'materials/linear_color.dart';
import 'materials/material_3d_library.dart';
import 'shapes/primitive_3d_component.dart';

/// The GPU side of the shapes ([Primitive3DComponent]): meshes made from their sizes
/// and materials from their looks, uploaded once and shared by every shape
/// alike — twenty equal crates are one mesh and one material, drawn in one
/// instanced draw.
///
/// Textures load in the background; a shape draws in its colour until its
/// texture arrives. What no shape has used for a while is let go — never
/// what [inUse] says is on screen, nor a texture such a material holds.
/// A renderer that counts its users ([hold], [release]) has what it stops
/// using let go at once: a shape whose size animates keeps one mesh, not
/// one a frame.
final class Graphics3DShapes {
  /// Shapes uploaded with [uploader], their textures read by [read]; what is
  /// drawn now is told by [inUse].
  Graphics3DShapes(this.uploader, this.read, {this.inUse, this.library});

  /// Where meshes and materials go.
  final ModelUploader uploader;

  /// The bytes of an asset (a texture).
  final Future<Uint8List> Function(String path) read;

  /// The material files a shape may be drawn with ([Primitive3DComponent.material]);
  /// without one, every shape is drawn with its own look.
  final Material3DLibrary? library;

  /// The meshes and materials drawn now, asked for only when old ones are
  /// let go: these are kept however long ago they were asked for. A
  /// renderer asks [meshFor] and [materialFor] only when a shape changes,
  /// so what stays on screen unchanged would otherwise look unused.
  final Iterable<Object> Function()? inUse;

  final Map<Object, _Entry<GpuPrimitive>> _meshes = {};
  final Map<Object, _Entry<GpuMaterial>> _materials = {};
  final Map<String, _Texture> _textures = {};
  int _frame = 0;

  // The key each mesh and material made here is held under.
  final Map<GpuPrimitive, Object> _meshKeys = Map.identity();
  final Map<GpuMaterial, Object> _materialKeys = Map.identity();

  // Released by their last holder: let go as the frame ends unless asked
  // for again in it.
  final List<_Entry<Object>> _released = [];

  /// Frames something stays unused before it is let go.
  static const int keepFrames = 300;

  /// Changes when a texture arrives: materials asked for before should be
  /// asked for again.
  int get revision => _revision + (library?.revision ?? 0);
  int _revision = 0;

  /// How many meshes and materials are held.
  (int meshes, int materials, int textures) get counts =>
      (_meshes.length, _materials.length, _textures.length);

  /// [shape]'s mesh, for an entity scaled by [scale] (which counts only
  /// for a texture tiled per metre); null when it has no triangles.
  GpuPrimitive? meshFor(Primitive3DComponent shape, Vector3 scale) {
    final uv = tilesInMetres(shape) ? _metres(scale) : ShapeUv.natural;
    final key = (shape.shapeKey, uv.key);
    final known = _meshes[key];
    if (known != null) {
      known.used = _frame;
      return known.value;
    }
    final mesh = shape.buildMesh(uv);
    if (mesh.triangleCount == 0) return null;
    final gpu = uploader.uploadPrimitive(mesh.toPrimitive());
    _meshes[key] = _Entry(gpu, _frame, key: key);
    _meshKeys[gpu] = key;
    return gpu;
  }

  /// Counts one more user of [thing] — a mesh from [meshFor], or a
  /// material from [materialFor] — until it calls [release].
  void hold(Object thing) {
    final entry = _entryOf(thing);
    if (entry != null) {
      entry.holders++;
    } else if (thing is GpuMaterial) {
      library?.hold(thing);
    }
  }

  /// One user of [thing] (counted by [hold]) stopped drawing it: once none
  /// does, it is let go as the frame ends — unless asked for again in it —
  /// rather than after [keepFrames]. Asked for later, it is made again.
  void release(Object thing) {
    final entry = _entryOf(thing);
    if (entry == null) {
      if (thing is GpuMaterial) library?.release(thing);
      return;
    }
    if (entry.holders > 0 && --entry.holders == 0) _released.add(entry);
  }

  _Entry<Object>? _entryOf(Object thing) {
    if (thing is GpuPrimitive) {
      final key = _meshKeys[thing];
      return key == null ? null : _meshes[key];
    }
    if (thing is GpuMaterial) {
      final key = _materialKeys[thing];
      return key == null ? null : _materials[key];
    }
    return null;
  }

  /// How [shape]'s texture is laid out at [scale], drawn with its own look.
  static ShapeUv uvFor(Primitive3DComponent shape, Vector3 scale) {
    if (!shape.tileInMetres || shape.texture.isEmpty) return ShapeUv.natural;
    return _metres(scale);
  }

  // Rounded, so a scale animating by a hair does not make a mesh a frame.
  static ShapeUv _metres(Vector3 scale) {
    double q(double v) => (v.abs() * 1000).roundToDouble() / 1000;
    return ShapeUv.metresAt(q(scale.x), q(scale.y), q(scale.z));
  }

  /// Whether [shape]'s maps repeat per metre of the world, so its mesh is
  /// made for its scale: its own texture tiled per metre, or a material
  /// file laid out in metres.
  bool tilesInMetres(Primitive3DComponent shape) {
    if (shape.material.isNotEmpty) {
      return library?.fileOf(shape.material)?.uv == Material3DUv.metres;
    }
    return shape.tileInMetres && shape.texture.isNotEmpty;
  }

  /// [shape]'s material: its material file's once that is read (its own
  /// look meanwhile), with [overrides] (its entity's own values,
  /// [MaterialOverrides3DComponent]) on top; else its own look, with its texture once
  /// that has loaded.
  GpuMaterial materialFor(
    Primitive3DComponent shape, {
    Map<String, Object?> overrides = const {},
  }) {
    final file = shape.material;
    if (file.isNotEmpty) {
      final shared = library?.gpuOf(file, overrides: overrides);
      if (shared != null) return shared;
    }
    final key = shape.materialKey;
    final known = _materials[key];
    if (known != null) {
      known.used = _frame;
      return known.value;
    }
    final path = shape.texture;
    final texture = path.isEmpty ? null : _texture(path);
    final material = uploader.material(
      materialDataOf(shape),
      baseColor: texture == null ? null : (texture, GpuSampler.linearRepeat),
    );
    _materials[key] = _Entry(material, _frame, key: key, texture: path);
    _materialKeys[material] = key;
    return material;
  }

  /// [shape]'s look as a glTF-style material: colours made linear, blended
  /// when it is not opaque, its texture (as texture 0) repeated
  /// [Primitive3DComponent.tiling] times.
  static MaterialData materialDataOf(Primitive3DComponent shape) {
    final (r, g, b) = LinearColor.of(shape.color);
    final (er, eg, eb) = LinearColor.of(shape.emission);
    final alpha = shape.opacity.clamp(0.0, 1.0) * shape.color.a;
    return MaterialData(
      name: shape.shapeName,
      baseColor: (r, g, b, alpha),
      metallic: shape.metallic.clamp(0.0, 1.0),
      roughness: shape.roughness.clamp(0.0, 1.0),
      emissive: (er, eg, eb),
      emissiveStrength: math.max(shape.emissionStrength, 0.0),
      alphaMode: alpha < 1 ? AlphaMode.blend : AlphaMode.opaque,
      doubleSided: shape.doubleSided,
      unlit: shape.unlit,
      baseColorTexture: shape.texture.isEmpty
          ? null
          : TextureRef(0, scale: (shape.tiling.x, shape.tiling.y)),
    );
  }

  GpuTexture? _texture(String path) {
    final known = _textures[path];
    if (known != null) return known.texture;
    final entry = _textures[path] = _Texture();
    unawaited(
      read(path)
          .then((bytes) => uploader.uploadImage(bytes))
          .then(
            (texture) {
              if (!identical(_textures[path], entry)) return;
              if (texture == null) {
                debugPrint(
                  'just_game_engine: could not decode the texture $path',
                );
                return;
              }
              entry.texture = texture;
              // Materials made without it are made again, with it.
              _forgetMaterials((m) => m.texture == path);
              _revision++;
            },
            onError: (Object error) {
              if (identical(_textures[path], entry)) {
                debugPrint('just_game_engine: no texture $path: $error');
              }
            },
          ),
    );
    return null;
  }

  /// Reads [path]'s texture again (it changed on disk). What it was is
  /// drawn until the new one arrives; then the materials made with it are
  /// made again.
  void reloadTexture(String path) {
    final known = _textures[path];
    if (known == null) return;
    final shown = known.texture;
    if (shown == null) {
      // Still being read the first time: read afresh.
      _textures.remove(path);
      _forgetMaterials((m) => m.texture == path);
      _revision++;
      return;
    }
    final entry = _textures[path] = _Texture()..texture = shown;
    unawaited(
      read(path)
          .then((bytes) => uploader.uploadImage(bytes))
          .then(
            (texture) {
              if (!identical(_textures[path], entry) || texture == null) {
                return;
              }
              entry.texture = texture;
              _forgetMaterials((m) => m.texture == path);
              _revision++;
            },
            onError: (Object error) {
              if (identical(_textures[path], entry)) {
                debugPrint('just_game_engine: no texture $path: $error');
              }
            },
          ),
    );
  }

  void _forgetMaterials(bool Function(_Entry<GpuMaterial> m) test) {
    _materials.removeWhere((_, m) {
      if (!test(m)) return false;
      _materialKeys.remove(m.value);
      return true;
    });
  }

  /// A frame has been drawn: lets go of what its last holder released in
  /// it ([release]) and nothing asked for again; now and then, of what has
  /// not been used for [keepFrames] frames and is not [inUse].
  void endFrame() {
    for (final e in _released) {
      if (e.holders > 0 || e.used >= _frame) continue;
      if (identical(_meshes[e.key]?.value, e.value)) {
        _meshes.remove(e.key);
        _meshKeys.remove(e.value);
      } else if (identical(_materials[e.key]?.value, e.value)) {
        _materials.remove(e.key);
        _materialKeys.remove(e.value);
      }
    }
    _released.clear();
    _frame++;
    if (_frame % 120 != 0) return;
    final old = _frame - keepFrames;
    final live = Set<Object>.identity()..addAll(inUse?.call() ?? const []);
    _meshes.removeWhere((_, e) {
      if (e.used >= old || live.contains(e.value)) return false;
      _meshKeys.remove(e.value);
      return true;
    });
    _forgetMaterials((e) => e.used < old && !live.contains(e.value));
    // What a kept material shows stays, so it can be reloaded.
    final textured = {for (final m in _materials.values) m.texture};
    _textures.removeWhere(
      (path, t) => t.texture != null && !textured.contains(path),
    );
  }

  /// Lets go now, however recently used, of every mesh, material and
  /// texture that nothing [inUse] draws and no user holds ([hold]): asked
  /// for again, it is made again.
  void releaseUnused() {
    final live = Set<Object>.identity()..addAll(inUse?.call() ?? const []);
    _meshes.removeWhere((_, e) {
      if (e.holders > 0 || live.contains(e.value)) return false;
      _meshKeys.remove(e.value);
      return true;
    });
    _forgetMaterials((e) => e.holders <= 0 && !live.contains(e.value));
    final textured = {for (final m in _materials.values) m.texture};
    _textures.removeWhere((path, _) => !textured.contains(path));
    _released.clear();
  }

  /// Lets go of everything.
  void clear() {
    _meshes.clear();
    _materials.clear();
    _meshKeys.clear();
    _materialKeys.clear();
    _released.clear();
    _textures.clear();
    _revision++;
  }
}

final class _Entry<T extends Object> {
  _Entry(this.value, this.used, {required this.key, this.texture = ''});

  final T value;
  int used;

  /// What it is held under.
  final Object key;

  /// How many users count it ([Graphics3DShapes.hold]).
  int holders = 0;

  /// The texture a material was made for.
  final String texture;
}

final class _Texture {
  GpuTexture? texture;
}
