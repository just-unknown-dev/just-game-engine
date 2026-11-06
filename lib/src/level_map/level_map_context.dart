/// What level maps keep per engine: the collision kinds a tile can have,
/// and the tilesets and map files loaded so far.
library;

import '../ecs/engine_context.dart';
import 'collision/map_collision_kinds.dart';
import 'tile_assets.dart';

/// The level-map state of one [EngineContext]; read it through
/// [ContextLevelMap].
final class LevelMapContextState implements ContextResource {
  LevelMapContextState._(this._context)
    : collisionKinds = MapCollisionKinds(withBuiltIns: _context.withBuiltIns) {
    tiles = TileAssets(readText: bundleText, collisionKinds: collisionKinds);
  }

  /// [context]'s state, made the first time it is asked for.
  static LevelMapContextState of(EngineContext context) =>
      context.slot(_key, () => LevelMapContextState._(context));

  static final Object _key = Object();

  final EngineContext _context;

  /// See [ContextLevelMap.collisionKinds].
  final MapCollisionKinds collisionKinds;

  /// See [ContextLevelMap.tiles].
  late final TileAssets tiles;

  /// Reads a file from the context's bundle: the default
  /// [TileAssets.readText].
  Future<String> bundleText(String path) =>
      _context.bundle.loadString(path, cache: false);

  @override
  void dispose() => tiles.dispose();
}

/// An engine's level-map state, on its [EngineContext].
extension ContextLevelMap on EngineContext {
  /// The collision kinds a tile can have; `solid` and `oneWay` are always
  /// there.
  MapCollisionKinds get collisionKinds =>
      LevelMapContextState.of(this).collisionKinds;

  /// Tilesets and map files, and what was loaded of them. Its
  /// [TileAssets.readText] reads the bundle by default; an authoring tool
  /// points it at the project's files (`overrideLoaders`).
  TileAssets get tiles => LevelMapContextState.of(this).tiles;
}
