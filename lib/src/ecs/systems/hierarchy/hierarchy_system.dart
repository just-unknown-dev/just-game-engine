library;

import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

/// Parent-child system - Updates child transforms based on parents.
///
/// Uses a topological (parent-first) traversal so that deep hierarchies produce
/// correct world-space transforms regardless of entity creation order.
class HierarchySystem extends System {
  @override
  int get priority => SystemPriorities.hierarchy;
  @override
  List<Type> get requiredComponents => [TransformComponent, ParentComponent];

  /// Reusable buffers — avoid per-frame allocation.
  final List<Entity> _roots = [];
  final List<Entity> _stack = [];

  @override
  void update(double deltaTime) {
    _roots.clear();
    _stack.clear();

    // 1. Identify root entities (no parent, or parent not found/inactive).
    //    Also apply their own transforms first.
    for (final entity in entities) {
      if (!entity.isActive) continue;
      final parent = entity.getComponent<ParentComponent>()!;
      if (parent.parentId == null) {
        _roots.add(entity);
        continue;
      }
      final parentEntity = world.getEntity(parent.parentId!);
      if (parentEntity == null ||
          !parentEntity.isActive ||
          !parentEntity.hasComponent<TransformComponent>()) {
        _roots.add(entity);
      }
    }

    // 2. BFS / iterative depth-first from roots through children.
    _stack.addAll(_roots);
    while (_stack.isNotEmpty) {
      final entity = _stack.removeLast();
      final transform = entity.getComponent<TransformComponent>()!;
      final parentComp = entity.getComponent<ParentComponent>()!;

      // Apply parent transform if this entity has a valid parent.
      if (parentComp.parentId != null) {
        final parentEntity = world.getEntity(parentComp.parentId!);
        if (parentEntity != null && parentEntity.isActive) {
          final parentTransform = parentEntity
              .getComponent<TransformComponent>();
          if (parentTransform != null) {
            transform.position =
                parentTransform.position + parentComp.localOffset;
            transform.rotation =
                parentTransform.rotation + parentComp.localRotation;
          }
        }
      }

      // Push children onto the stack so they are processed after this entity.
      final children = entity.getComponent<ChildrenComponent>();
      if (children != null) {
        for (final childId in children.childIds) {
          final child = world.getEntity(childId);
          if (child != null && child.isActive) {
            _stack.add(child);
          }
        }
      }
    }
  }
}
