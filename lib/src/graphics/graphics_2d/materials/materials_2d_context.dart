/// What 2-D materials keep per engine: where their files come from, and the
/// library of them.
library;

import '../../../assets/text_reader.dart';
import '../../../ecs/engine_context.dart';
import '../../../sprites/sprites_context.dart';
import 'material_2d_library.dart';

/// The 2-D material state of one [EngineContext]; read it through
/// [ContextMaterials2D]. Released with the context: its library lets go of
/// what it holds.
final class Materials2DContextState implements ContextResource {
  Materials2DContextState._(this._context) {
    reader = bundleText;
  }

  /// [context]'s state, made the first time it is asked for.
  static Materials2DContextState of(EngineContext context) =>
      context.slot(_key, () => Materials2DContextState._(context));

  static final Object _key = Object();

  final EngineContext _context;

  /// See [ContextMaterials2D.material2DText].
  late TextReader reader;

  /// See [ContextMaterials2D.material2DLibrary].
  Material2DLibrary get library => _library ??= Material2DLibrary(
    (path) => reader(path),
    readImage: (path) => _context.sprites.loadImage(path),
    // Whose an image is depends on the loader that read it, which an
    // authoring tool may swap: asked as each is read.
    ownsImages: () => _context.sprites.callerDisposesImages,
  );
  Material2DLibrary? _library;

  /// Reads a file from the context's bundle: the default [reader].
  Future<String> bundleText(String path) =>
      _context.bundle.loadString(path, cache: false);

  @override
  void dispose() => _library?.dispose();
}

/// Where an engine's 2-D material files come from, and the library that
/// reads them, on its [EngineContext].
extension ContextMaterials2D on EngineContext {
  /// Reads 2-D material files (`*.material2d.json`) for `Material2DLibrary`.
  /// The bundle by default; an authoring tool points it at the project's
  /// files (`overrideLoaders`).
  TextReader get material2DText => Materials2DContextState.of(this).reader;
  set material2DText(TextReader value) =>
      Materials2DContextState.of(this).reader = value;

  /// The engine's 2-D material files and shaders, read through
  /// [material2DText] and `sprites`; made the first time it is asked for.
  Material2DLibrary get material2DLibrary =>
      Materials2DContextState.of(this).library;
}
