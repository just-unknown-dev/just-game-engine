/// What prefabs keep per engine: where prefab files come from.
library;

import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show PrefabFile;

import '../ecs/engine_context.dart';
import 'prefab_library.dart';

/// Loads a prefab file by path.
typedef PrefabLoader = Future<PrefabFile> Function(String path);

/// The prefab state of one [EngineContext]; read it through
/// [ContextPrefabs].
final class PrefabsContextState {
  PrefabsContextState._(this._context) {
    loader = bundleLoader;
  }

  /// [context]'s state, made the first time it is asked for.
  static PrefabsContextState of(EngineContext context) =>
      context.slot(_key, () => PrefabsContextState._(context));

  static final Object _key = Object();

  final EngineContext _context;

  /// See [ContextPrefabs.prefabs].
  late PrefabLoader loader;

  /// See [ContextPrefabs.prefabLibrary].
  late final PrefabLibrary library = PrefabLibrary(_context);

  /// Reads a prefab file from the context's bundle: the default [loader].
  Future<PrefabFile> bundleLoader(String path) async =>
      PrefabFile.parse(await _context.bundle.loadString(path, cache: false));
}

/// Where an engine's prefab files come from, on its [EngineContext].
extension ContextPrefabs on EngineContext {
  /// Loads prefab files (`*.prefab.json`) for scenes and spawners — see
  /// `PrefabLibrary`. The bundle by default; an authoring tool points it at
  /// the project's files (`overrideLoaders`).
  PrefabLoader get prefabs => PrefabsContextState.of(this).loader;
  set prefabs(PrefabLoader value) =>
      PrefabsContextState.of(this).loader = value;

  /// The prefab files this engine has read, which scenes and spawners make
  /// their instances from; see [PrefabLibrary]. Made the first time it is
  /// asked for.
  PrefabLibrary get prefabLibrary => PrefabsContextState.of(this).library;
}
