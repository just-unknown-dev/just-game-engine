/// The 2-D material files the scene draws with, read once each.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import '../../ecs/base/engine_context.dart';
import 'material_2d_shader.dart';

/// The 2-D material files (`*.material2d.json`) an engine's entities are
/// drawn with ([Material2D]), and the shader that draws them.
///
/// Files are read in the background through the context's
/// `material2DText` seam (the bundle, or an editor's project files): [fileOf]
/// is null until a file — and, for a variant, each parent — is read, and
/// [revision] goes up whenever what one draws as changes. A variant is drawn
/// with its parents laid under it ([MaterialChain]); an editor shows
/// unsaved edits by [preview].
///
/// One per engine: [of].
final class Material2DLibrary {
  /// A library reading files through [read], and the images they name (a
  /// normal map) through [readImage].
  Material2DLibrary(this.read, {this.readImage});

  /// The library of [context]'s engine, reading through its seams.
  static Material2DLibrary of(EngineContext context) => context.slot(
    Material2DLibrary,
    () => Material2DLibrary(
      (path) => context.material2DText(path),
      readImage: (path) => context.sprites.loadImage(path),
    ),
  );

  /// Reads a project file's text.
  final Future<String> Function(String path) read;

  /// Reads an image a material names; null reads none.
  final Future<ui.Image> Function(String path)? readImage;

  final Map<String, _Image> _images = {};

  final Map<String, _Source> _sources = {};
  final Map<String, Material2DFile> _previews = {};
  final Map<String, _Made> _made = {};
  int _revision = 0;

  final _Program _sprites = _Program(Material2DShader.asset);
  final _Program _screen = _Program(Material2DShader.screenAsset);
  final _Program _normals = _Program(Material2DShader.normalsAsset);
  final _Program _lighting = _Program(Material2DShader.lightingAsset);
  final _Program _shadows = _Program(Material2DShader.shadowsAsset);

  /// Goes up whenever a material is read, previewed or forgotten.
  int get revision => _revision;

  /// The material at [path] as it is drawn: its parents laid under it, an
  /// unsaved edit standing in for a file — reading it the first time asked;
  /// null meanwhile, or when it could not be read ([errorOf]).
  Material2DFile? fileOf(String path) => _madeOf(path)?.file;

  /// The file at [path] as saved (or as [preview] shows it), not resolved.
  Material2DFile? sourceOf(String path) =>
      _previews[path] ?? _source(path).file;

  /// Why [path] could not be read; null when it was, or still is being.
  Object? errorOf(String path) => _sources[path]?.error;

  /// What is wrong with [path]'s parents — one missing, a loop — for a
  /// person; empty when nothing is, or while they are read.
  List<String> problemsOf(String path) => _madeOf(path)?.problems ?? const [];

  /// Draws [path] as [file] — unsaved edits — until [endPreview]; its
  /// variants follow.
  void preview(String path, Material2DFile file) {
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

  /// Reads [path] again after it changed on disk; what it was is drawn
  /// until it arrives.
  void reload(String path) {
    final source = _sources[path];
    if (source != null) _load(path, source);
    final image = _images[path];
    if (image != null) _loadImage(path, image);
  }

  /// The image at [path] a material names — a normal map — reading it the
  /// first time asked; null meanwhile, or when it cannot be read.
  ui.Image? imageOf(String path) {
    if (path.isEmpty || readImage == null) return null;
    final known = _images[path];
    if (known != null) return known.image;
    final entry = _images[path] = _Image();
    _loadImage(path, entry);
    return null;
  }

  void _loadImage(String path, _Image entry) {
    final ticket = ++entry.ticket;
    unawaited(
      readImage!(path).then(
        (image) {
          if (!identical(_images[path], entry) || ticket != entry.ticket) {
            image.dispose();
            return;
          }
          entry.image?.dispose();
          entry.image = image;
          _revision++;
        },
        onError: (Object error) {
          debugPrint(
            'just_game_engine: no image $path for a 2-D material: $error',
          );
        },
      ),
    );
  }

  /// Lets go of every file, unsaved previews too.
  void clear() {
    _sources.clear();
    _previews.clear();
    _made.clear();
    for (final i in _images.values) {
      i.image?.dispose();
    }
    _images.clear();
    _revision++;
  }

  /// The shader sprites, shapes and tile layers are drawn through; null
  /// until it is loaded — asking the first time loads it — or when it could
  /// not be ([programError]).
  ui.FragmentProgram? get program => _sprites.get(this);

  /// The shader a screen material ([Material2DKind.screen]) is drawn
  /// through; null until it is loaded.
  ui.FragmentProgram? get screenProgram => _screen.get(this);

  /// The shader a 2-D material's normals are drawn through, for lighting.
  ui.FragmentProgram? get normalsProgram => _normals.get(this);

  /// The shader a lit frame is drawn through ([Lighting2D]).
  ui.FragmentProgram? get lightingProgram => _lighting.get(this);

  /// The shader 2-D shadows are found with.
  ui.FragmentProgram? get shadowsProgram => _shadows.get(this);

  /// Why [program] could not be loaded; null when it was, or still is being.
  Object? get programError => _sprites.error;

  /// Loads one of the engine's shaders: by the package's asset key in a
  /// game, by the plain one when the engine is the app (its own tests).
  static Future<ui.FragmentProgram> loadProgram([
    String asset = Material2DShader.asset,
  ]) async {
    try {
      return await ui.FragmentProgram.fromAsset(
        'packages/just_game_engine/$asset',
      );
    } on Object {
      return ui.FragmentProgram.fromAsset(asset);
    }
  }

  _Source _source(String path) {
    final known = _sources[path];
    if (known != null) return known;
    final source = _sources[path] = _Source();
    _load(path, source);
    return source;
  }

  void _load(String path, _Source source) {
    final ticket = ++source.ticket;
    bool current() =>
        identical(_sources[path], source) && ticket == source.ticket;
    unawaited(
      read(path).then(
        (text) {
          if (!current()) return;
          try {
            source
              ..file = Material2DFile.parse(text)
              ..error = null;
          } on FormatException catch (e) {
            source
              ..file = null
              ..error = e;
            debugPrint(
              'just_game_engine: the 2-D material $path is broken: ${e.message}',
            );
          }
          // A variant's parent is read now, not when it is next asked for.
          final parent = source.file?.parent ?? '';
          if (parent.isNotEmpty) _source(parent);
          _changed(path);
        },
        onError: (Object error) {
          if (!current()) return;
          source
            ..file = null
            ..error = error;
          debugPrint('just_game_engine: no 2-D material $path: $error');
          _changed(path);
        },
      ),
    );
  }

  _Made? _madeOf(String path) {
    final known = _made[path];
    if (known != null) return known;
    final pending = <String>[];
    Material2DFile? lookup(String p) {
      final preview = _previews[p];
      if (preview != null) return preview;
      final source = _source(p);
      if (source.file == null && source.error == null) pending.add(p);
      return source.file;
    }

    final ResolvedMaterial<Material2DFile> resolved;
    try {
      resolved = MaterialChain.resolve2D(path, lookup);
    } on StateError {
      return null;
    }
    if (pending.isNotEmpty) return null;
    return _made[path] = _Made(resolved.value, resolved.problems, {
      ...resolved.chain,
    });
  }

  void _changed(String path) {
    _made.removeWhere((key, made) => key == path || made.deps.contains(path));
    _revision++;
  }
}

/// One of the shaders, loaded the first time it is asked for.
final class _Program {
  _Program(this.asset);

  final String asset;
  ui.FragmentProgram? program;
  Future<void>? loading;
  Object? error;

  ui.FragmentProgram? get(Material2DLibrary library) {
    if (program == null && loading == null) {
      loading = Material2DLibrary.loadProgram(asset).then(
        (p) {
          program = p;
          library._revision++;
        },
        onError: (Object e) {
          error = e;
          debugPrint('just_game_engine: the shader $asset did not load: $e');
        },
      );
    }
    return program;
  }
}

final class _Image {
  ui.Image? image;
  int ticket = 0;
}

final class _Source {
  Material2DFile? file;
  Object? error;
  int ticket = 0;
}

final class _Made {
  _Made(this.file, this.problems, this.deps);

  final Material2DFile file;
  final List<String> problems;
  final Set<String> deps;
}
