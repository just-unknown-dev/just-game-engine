/// What 2-D materials keep per engine: where their files come from.
library;

import '../assets/text_reader.dart';
import '../ecs/engine_context.dart';

/// The 2-D material state of one [EngineContext]; read it through
/// [ContextMaterials2D].
final class Materials2DContextState {
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

  /// Reads a file from the context's bundle: the default [reader].
  Future<String> bundleText(String path) =>
      _context.bundle.loadString(path, cache: false);
}

/// Where an engine's 2-D material files come from, on its [EngineContext].
extension ContextMaterials2D on EngineContext {
  /// Reads 2-D material files (`*.material2d.json`) for `Material2DLibrary`.
  /// The bundle by default; an authoring tool points it at the project's
  /// files (`overrideLoaders`).
  TextReader get material2DText => Materials2DContextState.of(this).reader;
  set material2DText(TextReader value) =>
      Materials2DContextState.of(this).reader = value;
}
