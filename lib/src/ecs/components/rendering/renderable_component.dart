library;

import '../../ecs.dart';
import '../../../subsystems/rendering/impl/renderable.dart';

/// Renderable component - Links to a Renderable object
class RenderableComponent extends Component {
  /// The renderable object
  Renderable renderable;

  /// Whether to sync transform with entity
  bool syncTransform;

  /// Create a renderable component
  RenderableComponent({required this.renderable, this.syncTransform = true});

  /// Every renderable shares one archetype key, so `RenderSystem`'s single
  /// query finds rectangles, sprites and a game's own subclasses alike.
  ///
  /// This used to be overridden on each built-in shape and forgotten on
  /// every subclass, which was then silently never drawn.
  @override
  Type get componentType => RenderableComponent;

  @override
  String toString() => 'Renderable(${renderable.runtimeType})';
}
