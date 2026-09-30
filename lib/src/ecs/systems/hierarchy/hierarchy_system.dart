library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Former home of parent → child transform propagation.
///
/// Every [World] now keeps its hierarchy in step by itself
/// ([World.transformHierarchy], run at [SystemPriorities.hierarchy]), so
/// there is nothing to register. This system only asks the world's
/// hierarchy for one more pass, which changes nothing.
@Deprecated(
  'Every World keeps its hierarchy in step itself '
  '(World.transformHierarchy); remove this system.',
)
class HierarchySystem extends System {
  @override
  int get priority => SystemPriorities.hierarchy;
  @override
  List<Type> get requiredComponents => [TransformComponent, ParentComponent];

  @override
  void update(double deltaTime) => world.transformHierarchy.propagate();
}
