/// Things an entity draws besides its one [RenderableComponent].
library;

import 'dart:ui';

import '../../ecs.dart';
import '../../serialization/component_definition.dart' show RenderContext;

/// One drawable an entity owns, sorted into the same draw order as every
/// renderable in the world.
///
/// An entity has at most one `RenderableComponent`, and it sorts as one
/// thing. A tile map has a background layer that belongs behind the player
/// and a foreground layer that belongs in front of it: two draw positions
/// for one entity. Items give it that without spawning an entity per layer —
/// entities would be saved, listed in the editor's tree and pickable.
///
/// Items sort by `(layer << 20) + zOrder`, then [subOrder], exactly as a
/// `LayerComponent` does, and draw inside the camera transform. The canvas is **not**
/// translated to the owner: an item places itself, usually from the owner's
/// transform.
abstract class RenderItem {
  /// Coarse draw layer; see `LevelLayers` for the conventional values.
  int get layer;

  /// Order within [layer]; lower draws first.
  int get zOrder => 0;

  /// Order among what shares [layer] and [zOrder]; lower draws first. A map
  /// layer's items use it to keep the entities on a layer between that
  /// layer's tiles and the next one's.
  int get subOrder => 0;

  /// Whether to draw this frame. An invisible item costs one call.
  bool get visible => true;

  /// Draws the item in world space for [owner].
  void render(Canvas canvas, RenderContext context, Entity owner);
}

/// The [RenderItem]s an entity draws. Runtime only: whatever creates the
/// items (a loading system, usually) attaches this, and nothing saves it.
class RenderItemsComponent extends Component {
  RenderItemsComponent([List<RenderItem>? items]) : items = items ?? [];

  /// The items, in no particular order: the render system sorts them.
  final List<RenderItem> items;

  @override
  String toString() => 'RenderItems(${items.length})';
}
