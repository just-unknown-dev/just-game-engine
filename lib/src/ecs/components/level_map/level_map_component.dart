/// The level's map.
library;

import '../../../subsystems/level_map/level_map_data.dart';
import '../../../subsystems/level_map/level_map_runtime.dart';
import '../../ecs.dart';

/// Puts a map in the level — its tile layers — at its entity's position. A
/// scene has one: its Level Map. What is placed on a layer of it is a child
/// of its entity naming the layer (`LayerComponent.mapLayer`).
///
/// The map is either kept in the scene ([inline], the default — one save,
/// one undo history, a level that is one file) or in a `.map.json` of
/// its own named by [mapPath], so one map can serve several scenes. A
/// `.tmx` or `.tmj` path loads a Tiled map directly.
///
/// The map's layers sort among the level's other drawing by their own
/// layer settings, so one entity's background layer draws behind the
/// player and its foreground layer in front. Only the entity's position is
/// used; the map is not rotated or scaled with it.
class LevelMapComponent extends Component {
  LevelMapComponent({this.mapPath = '', this.inline});

  /// A `.map.json` (or, from before, `.tilemap.json`), `.tmx` or `.tmj`;
  /// empty to use [inline].
  String mapPath;

  /// The map, kept in the scene. Ignored while [mapPath] is set.
  LevelMapData? inline;

  /// What the running game made of the map: its loaded tilesets, what it
  /// has changed, its drawing. Never saved; rebuilt whenever the map it was
  /// made for is replaced.
  LevelMapRuntime? runtime;

  /// Whether the map comes from a file.
  bool get usesFile => mapPath.trim().isNotEmpty;

  @override
  String toString() =>
      'LevelMap(${usesFile ? mapPath : 'inline, ${inline?.layers.length ?? 0} layers'})';
}
