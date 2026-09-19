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
class LayerComponent extends Component {
  LayerComponent({
    this.layerId = 'main',
    this.layer = 0,
    this.zOrder = 0,
    this.visible = true,
    this.locked = false,
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
