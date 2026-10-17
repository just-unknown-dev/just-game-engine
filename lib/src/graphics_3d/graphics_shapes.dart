import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_dart/just_dart.dart' show Vector3;
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import 'material_library.dart';
import 'shapes/primitive_3d.dart';

/// The GPU side of the shapes ([Primitive3D]): meshes made from their sizes
/// and materials from their looks, uploaded once and shared by every shape
/// alike — twenty equal crates are one mesh and one material, drawn in one
/// instanced draw.
///
/// Textures load in the background; a shape draws in its colour until its
/// texture arrives. What no shape has used for a while is let go — never
/// what [inUse] says is on screen, nor a texture such a material holds.
final class GraphicsShapes {
  /// Shapes uploaded with [uploader], their textures read by [read]; what is
  /// drawn now is told by [inUse].
  GraphicsShapes(this.uploader, this.read, {this.inUse, this.library});

  /// Where meshes and materials go.
  final ModelUploader uploader;

  /// The bytes of an asset (a texture).
  final Future<Uint8List> Function(String path) read;

  /// The material files a shape may be drawn with ([Primitive3D.material]);
  /// without one, every shape is drawn with its own look.
  final MaterialLibrary? library;

  /// The meshes and materials drawn now, asked for only when old ones are
  /// let go: these are kept however long ago they were asked for. A
  /// renderer asks [meshFor] and [materialFor] only when a shape changes,
  /// so what stays on screen unchanged would otherwise look unused.
  final Iterable<Object> Function()? inUse;

  final Map<Object, _Entry<GpuPrimitive>> _meshes = {};
  final Map<Object, _Entry<GpuMaterial>> _materials = {};
  final Map<String, _Texture> _textures = {};
  int _frame = 0;

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
  GpuPrimitive? meshFor(Primitive3D shape, Vector3 scale) {
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
    _meshes[key] = _Entry(gpu, _frame);
    return gpu;
  }

  /// How [shape]'s texture is laid out at [scale], drawn with its own look.
  static ShapeUv uvFor(Primitive3D shape, Vector3 scale) {
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
  bool tilesInMetres(Primitive3D shape) {
    if (shape.material.isNotEmpty) {
      return library?.fileOf(shape.material)?.uv == MaterialUv.metres;
    }
    return shape.tileInMetres && shape.texture.isNotEmpty;
  }

  /// [shape]'s material: its material file's once that is read (its own
  /// look meanwhile), with [overrides] (its entity's own values,
  /// [MaterialOverrides3D]) on top; else its own look, with its texture once
  /// that has loaded.
  GpuMaterial materialFor(
    Primitive3D shape, {
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
    _materials[key] = _Entry(material, _frame, texture: path);
    return material;
  }

  /// [shape]'s look as a glTF-style material: colours made linear, blended
  /// when it is not opaque, its texture (as texture 0) repeated
  /// [Primitive3D.tiling] times.
  static MaterialData materialDataOf(Primitive3D shape) {
    final (r, g, b) = linear(shape.color);
    final (er, eg, eb) = linear(shape.emission);
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
              _materials.removeWhere((_, m) => m.texture == path);
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

  /// Forgets [path]'s texture so it is read again (it changed on disk).
  void reloadTexture(String path) {
    if (_textures.remove(path) == null) return;
    _materials.removeWhere((_, m) => m.texture == path);
    _revision++;
  }

  /// A frame has been drawn: now and then, lets go of what has not been
  /// used for [keepFrames] frames and is not [inUse].
  void endFrame() {
    _frame++;
    if (_frame % 120 != 0) return;
    final old = _frame - keepFrames;
    final live = Set<Object>.identity()..addAll(inUse?.call() ?? const []);
    _meshes.removeWhere((_, e) => e.used < old && !live.contains(e.value));
    _materials.removeWhere((_, e) => e.used < old && !live.contains(e.value));
    // What a kept material shows stays, so it can be reloaded.
    final textured = {for (final m in _materials.values) m.texture};
    _textures.removeWhere(
      (path, t) => t.texture != null && !textured.contains(path),
    );
  }

  /// Lets go of everything.
  void clear() {
    _meshes.clear();
    _materials.clear();
    _textures.clear();
    _revision++;
  }

  /// sRGB [c] as linear RGB.
  static (double, double, double) linear(Color c) =>
      (_toLinear(c.r), _toLinear(c.g), _toLinear(c.b));

  static double _toLinear(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

final class _Entry<T> {
  _Entry(this.value, this.used, {this.texture = ''});

  final T value;
  int used;

  /// The texture a material was made for.
  final String texture;
}

final class _Texture {
  GpuTexture? texture;
}
