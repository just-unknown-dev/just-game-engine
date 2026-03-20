library;

import '../../ecs.dart';
import '../../components/components.dart';

/// Parent-child system - Updates child transforms based on parents
class HierarchySystem extends System {
  @override
  List<Type> get requiredComponents => [TransformComponent, ParentComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final parent = entity.getComponent<ParentComponent>()!;

      if (parent.parentId != null) {
        final parentEntity = world.getEntity(parent.parentId!);
        if (parentEntity != null && parentEntity.isActive) {
          final parentTransform = parentEntity
              .getComponent<TransformComponent>();
          if (parentTransform != null) {
            // Apply parent transform
            transform.position = parentTransform.position + parent.localOffset;
            transform.rotation =
                parentTransform.rotation + parent.localRotation;
          }
        }
      }
    });
  }
}
