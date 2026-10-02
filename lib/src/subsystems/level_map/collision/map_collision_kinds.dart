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
  /// A kind saved as [id] and listed as [label]. Unless said: neither
  /// one-way nor a sensor, merged by [TileMergeMode.area], light blue in the
  /// overlay, and with nothing added to its bodies.
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

  /// How neighbouring tiles of this kind join up into bodies.
  final TileMergeMode merge;

  /// Built as one-way bodies: landed on from above, passed through from
  /// below.
  final bool oneWay;

  /// Built as sensors: they report overlaps and stop nothing.
  final bool sensor;

  /// Adds whatever else a body of this kind needs, once it is built.
  /// `properties` are its tile's own, from its tileset — for a body merged
  /// from several tiles, the first one's. A spike's `damage`, a spring's
  /// `strength`.
  final void Function(Entity body, MapBodySpec spec, TileProperties properties)?
  decorate;
}

/// The collision kinds tiles can use.
///
/// Each engine has its own (`engine.context.collisionKinds`), which a game
/// or kit fills at boot: a tileset names a kind by id, and the system that
/// builds bodies looks it up there. [builtIn] holds only the engine's own
/// ([solid], [oneWay]) and cannot be changed; a fresh registry is the reset.
final class MapCollisionKinds {
  /// The engine's kinds (unless [withBuiltIns] is false), to add to.
  MapCollisionKinds({bool withBuiltIns = true}) : _frozen = false {
    if (withBuiltIns) _kinds.addAll(_engine);
  }

  MapCollisionKinds._frozen() : _frozen = true {
    _kinds.addAll(_engine);
  }

  /// The engine's kinds and nothing else — what a builder uses when given
  /// none. Read-only: [register] throws.
  static final MapCollisionKinds builtIn = MapCollisionKinds._frozen();

  final bool _frozen;

  /// Tiles that stop things from every side, merged into as few boxes as
  /// possible. Saved as `solid`; what a kind nobody registered resolves to.
  static const MapCollisionKind solid = MapCollisionKind(
    id: 'solid',
    label: 'Solid',
  );

  /// Platforms landed on from above and passed through from below, merged
  /// along rows only. Saved as `oneWay`.
  static const MapCollisionKind oneWay = MapCollisionKind(
    id: 'oneWay',
    label: 'One-way',
    color: 0xFF81C784,
    merge: TileMergeMode.rows,
    oneWay: true,
  );

  static const Map<String, MapCollisionKind> _engine = {
    'solid': solid,
    'oneWay': oneWay,
  };

  final Map<String, MapCollisionKind> _kinds = {};

  /// Adds [kind], replacing any of the same id.
  void register(MapCollisionKind kind) {
    if (_frozen) {
      throw UnsupportedError(
        'MapCollisionKinds.builtIn cannot be changed: register into an '
        "engine's (engine.context.collisionKinds).",
      );
    }
    _kinds[kind.id] = kind;
  }

  /// Adds each of [kinds] as [register] does, and throws as it does on
  /// [builtIn].
  void registerAll(Iterable<MapCollisionKind> kinds) {
    for (final k in kinds) {
      register(k);
    }
  }

  /// The kind called [id], or null when nothing registered it.
  MapCollisionKind? byId(String id) => _kinds[id];

  /// The kind called [id], or [solid] — a tile whose kind this game does
  /// not know still stops things.
  MapCollisionKind resolve(String id) => _kinds[id] ?? solid;

  /// Every kind, the engine's first.
  List<MapCollisionKind> get all => List.unmodifiable(_kinds.values);
}
