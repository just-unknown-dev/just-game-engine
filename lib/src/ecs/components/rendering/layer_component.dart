library;

import '../../ecs.dart';

/// Draw order and editor grouping for an entity.
///
/// The ECS render path draws in archetype/query order, which is effectively
/// arbitrary — this gives it a stable, authorable sort key. `RenderSystem`
/// sorts by ([layer], [zOrder]) so a background rectangle reliably stays
/// behind the player and a foreground one in front.
///
/// [layerId] is the human-facing name the level designer's layer panel groups
/// by; [layer] is what actually sorts.
///
/// An entity that is a child of a level map can belong to one of the map's
/// layers ([mapLayer]). It then draws with that layer — just above its tiles,
/// below the next layer's — and is hidden with it; `LevelMapSystem` keeps
/// [layerId], [layer] and [zOrder] following the layer.
class LayerComponent extends Component {
  LayerComponent({
    this.layerId = 'main',
    this.layer = 0,
    this.zOrder = 0,
    this.visible = true,
    this.locked = false,
    this.mapLayer,
  });

  /// Name of the layer this entity belongs to, e.g. 'background', 'main',
  /// 'foreground'. Editor-facing grouping only.
  String layerId;

  /// Coarse draw order. Lower draws first (further back).
  int layer;

  /// Fine draw order within [layer].
  int zOrder;

  /// Editor-only visibility toggle. Hiding a layer must not change what the
  /// level does, only what the author sees.
  bool visible;

  /// Editor-only: excluded from viewport picking, so a finished background
  /// cannot be dragged by accident while working on top of it.
  bool locked;

  /// The id of the layer of its parent's level map it belongs to; null for
  /// an entity on no map layer. Only means something on a child of an
  /// entity with a `LevelMapComponent`.
  int? mapLayer;

  /// Runtime only: its place among what shares its ([layer], [zOrder]) —
  /// after its map layer's tiles, before the next layer's. Set by
  /// `LevelMapSystem`; 0 for an entity on no map layer.
  int subOrder = 0;

  /// Runtime only: its map layer is hidden, so it is not drawn. Set by
  /// `LevelMapSystem`.
  bool hiddenByMap = false;
}

/// Conventional [LayerComponent.layer] values.
///
/// Plain constants rather than an enum because the field is an int the author
/// can set to anything — these are the defaults the prefabs and the layer
/// panel use.
abstract final class LevelLayers {
  /// Far background decoration, usually with parallax.
  static const int background = -200;

  /// Near background decoration.
  static const int backgroundNear = -100;

  /// Level geometry, enemies and the player.
  static const int main = 0;

  /// Drawn over the player.
  static const int foreground = 100;
}
