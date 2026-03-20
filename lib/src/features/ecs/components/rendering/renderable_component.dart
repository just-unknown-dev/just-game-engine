library;

import '../../ecs.dart';
import '../../../rendering/renderable.dart';

/// Renderable component - Links to a Renderable object
class RenderableComponent extends Component {
  /// The renderable object
  Renderable renderable;

  /// Whether to sync transform with entity
  bool syncTransform;

  /// Create a renderable component
  RenderableComponent({required this.renderable, this.syncTransform = true});

  @override
  String toString() => 'Renderable(${renderable.runtimeType})';
}
