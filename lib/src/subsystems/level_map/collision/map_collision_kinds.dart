/// The kinds of collision a tile can have, and what each one builds.
library;

import '../../../ecs/ecs.dart';
import '../tile_properties.dart';
import 'tile_collision_builder.dart';

/// How a kind's tiles join up into bodies.
enum TileMergeMode {
  /// Neighbouring whole-cell tiles become as few boxes as possible: along
  /// rows first, then rows of the same span stacked into one. Fewest bodies,
  /// and the fewest seams for a character to catch on.
  area,

  /// Joined along rows only — one-way platforms, whose top is what matters.
  rows,

  /// One body per tile — tiles that act on their own, like a block that
  /// crumbles.
  none,
}

/// What a tile's collision *kind* means at runtime.
///
/// The engine knows `solid` and `oneWay`. A game adds its own — a kit's
/// `hazard`, `bouncy` or `crumbling` — with [decorate] giving each body the
/// components that make it behave so. The editor lists every registered
/// kind in the tileset editor and colours the collision overlay by [color].
class MapCollisionKind {
  const MapCollisionKind({
    required this.id,
    required this.label,
    this.color = 0xFF4FC3F7,
    this.merge = TileMergeMode.area,
    this.oneWay = false,
    this.sensor = false,
    this.decorate,
  });

  /// What a tileset saves, e.g. `'solid'`.
  final String id;

  /// What the editor shows.
  final String label;

  /// ARGB, for the editor's collision overlay.
  final int color;

  final TileMergeMode merge;

  /// Built as one-way bodies: landed on from above, passed through from
  /// below.
  final bool oneWay;

  /// Built as sensors: they report overlaps and stop nothing.
  final bool sensor;

  /// Adds whatever else a body of this kind needs, once it is built.
  /// [properties] are its tile's own, from its tileset — for a body merged
  /// from several tiles, the first one's. A spike's `damage`, a spring's
  /// `strength`.
  final void Function(Entity body, MapBodySpec spec, TileProperties properties)?
  decorate;
}

/// The collision kinds tiles can use.
///
/// Process-wide, like the other runtime registries a game fills at boot
/// (timeline track kinds, UI widgets): a tileset names a kind by id, and the
/// system that builds bodies looks it up here.
abstract final class MapCollisionKinds {
  static const MapCollisionKind solid = MapCollisionKind(
    id: 'solid',
    label: 'Solid',
  );

  static const MapCollisionKind oneWay = MapCollisionKind(
    id: 'oneWay',
    label: 'One-way',
    color: 0xFF81C784,
    merge: TileMergeMode.rows,
    oneWay: true,
  );

  static final Map<String, MapCollisionKind> _kinds = {
    solid.id: solid,
    oneWay.id: oneWay,
  };

  /// Adds [kind], replacing any of the same id.
  static void register(MapCollisionKind kind) => _kinds[kind.id] = kind;

  static void registerAll(Iterable<MapCollisionKind> kinds) {
    for (final k in kinds) {
      register(k);
    }
  }

  /// The kind called [id], or null when nothing registered it.
  static MapCollisionKind? byId(String id) => _kinds[id];

  /// The kind called [id], or [solid] — a tile whose kind this game does
  /// not know still stops things.
  static MapCollisionKind resolve(String id) => _kinds[id] ?? solid;

  /// Every kind, the engine's first.
  static List<MapCollisionKind> get all => List.unmodifiable(_kinds.values);

  /// Back to only the engine's own. For tests.
  static void reset() {
    _kinds
      ..clear()
      ..[solid.id] = solid
      ..[oneWay.id] = oneWay;
  }
}
