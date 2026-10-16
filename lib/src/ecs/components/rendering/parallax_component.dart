library;

import '../../ecs.dart';
import '../../../subsystems/parallax/parallax_background.dart';

/// Parallax component — a [ParallaxBackground] drawn behind the world.
///
/// `ParallaxRenderSystem` (one of the engine's default systems, in
/// `DefaultSystem.rendering`) scrolls it against the camera and draws it in
/// screen space, before the world. Several are ordered by the entity's
/// `LayerComponent`. Nothing else is needed — the background is not also
/// added to `engine.parallax`, which is deprecated.
class ParallaxComponent extends Component {
  /// The parallax background managed by this component.
  ParallaxBackground background;

  /// Create a parallax component.
  ParallaxComponent({required this.background});

  @override
  String toString() => 'Parallax(${background.layers.length} layers)';
}
