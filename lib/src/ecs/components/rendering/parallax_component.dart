library;

import '../../ecs.dart';
import '../../../subsystems/parallax/parallax_background.dart';

/// Parallax component — attaches a [ParallaxBackground] to an entity.
///
/// Add this to an entity to associate parallax layer data with the ECS world.
/// The [ParallaxBackground] must also be registered with [ParallaxSystem]
/// (via `engine.parallax.addBackground()`) for it to be rendered.
class ParallaxComponent extends Component {
  /// The parallax background managed by this component.
  ParallaxBackground background;

  /// Create a parallax component.
  ParallaxComponent({required this.background});

  @override
  String toString() => 'Parallax(${background.layers.length} layers)';
}
