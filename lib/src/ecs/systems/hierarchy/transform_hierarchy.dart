library;

import '../../ecs.dart';
import '../../components/core/transform_component.dart';
import '../../components/hierarchy/children_component.dart';
import '../../components/hierarchy/parent_component.dart';
import 'hierarchy_math.dart';

/// Keeps every child's world transform in step with its parent's.
///
/// Every [World] owns one ([World.transformHierarchy]) and runs it once a
/// frame, at [SystemPriorities.hierarchy] — after physics, movement and
/// gameplay have moved things, before the camera frames them and they are
/// drawn. A tool that edits transforms outside the frame (an editor) calls
/// [propagateFrom] to settle a subtree at once.
///
/// For each child, parents first:
///
/// * if its `ParentComponent` still [ParentComponent.needsLocal] — a link
///   read from a file, or just re-parented — or something has written its
///   world transform since the last pass, the local transform is worked out
///   from the world one, and the child stays exactly where it is;
/// * otherwise its world transform is composed from its parent's and its
///   local one ([HierarchyMath]) — so it moves, turns and scales with it.
///
/// Only entities with children are visited, so a world without a hierarchy
/// pays nothing.
class TransformHierarchy {
  TransformHierarchy(this.world);

  /// The world this keeps in step.
  final World world;

  /// Whether the world runs this every frame. Turn off for a world whose
  /// parent links are only organisational.
  bool enabled = true;

  final List<Entity> _stack = [];

  /// Settle every hierarchy in the world.
  void propagate() {
    for (final parent in world.query(const [ChildrenComponent])) {
      if (!_isRoot(parent)) continue;
      _walk(parent);
    }
  }

  /// Settle everything under [entity] — after an edit made outside the
  /// frame, say. [entity] itself is taken as given.
  void propagateFrom(Entity entity) {
    if (!entity.isAlive) return;
    // Its own link first: an edited child must not be pulled back.
    final link = entity.getComponent<ParentComponent>();
    final t = entity.getComponent<TransformComponent>();
    if (link != null && t != null && link.parentId != null) {
      final parent = world.getEntity(link.parentId!);
      final pt = parent?.getComponent<TransformComponent>();
      if (pt != null && link.inheritTransform) {
        HierarchyMath.localFromWorld(pt, t, link);
        link
          ..needsLocal = false
          ..markSeen(t);
      }
    }
    _walk(entity);
  }

  /// Settle [child] as a fresh link: its local transform is worked out from
  /// where it is now. Call after re-parenting.
  void adopt(Entity child) {
    final link = child.getComponent<ParentComponent>();
    if (link == null) return;
    link.invalidateLocal();
    propagateFrom(child);
  }

  bool _isRoot(Entity entity) {
    final link = entity.getComponent<ParentComponent>();
    final parentId = link?.parentId;
    if (parentId == null) return true;
    final parent = world.getEntity(parentId);
    return parent == null || !parent.isActive;
  }

  void _walk(Entity root) {
    _stack
      ..clear()
      ..add(root);
    while (_stack.isNotEmpty) {
      final parent = _stack.removeLast();
      final children = parent.getComponent<ChildrenComponent>();
      if (children == null) continue;
      final pt = parent.getComponent<TransformComponent>();
      for (final id in children.childIds) {
        final child = world.getEntity(id);
        if (child == null || !child.isActive) continue;
        if (pt != null) _settle(parent.id, pt, child);
        _stack.add(child);
      }
    }
  }

  void _settle(EntityId parentId, TransformComponent pt, Entity child) {
    final link = child.getComponent<ParentComponent>();
    final t = child.getComponent<TransformComponent>();
    if (link == null || t == null || link.parentId != parentId) return;
    if (!link.inheritTransform) return;
    if (link.needsLocal || link.movedSinceSeen(t)) {
      HierarchyMath.localFromWorld(pt, t, link);
      link.needsLocal = false;
    } else {
      HierarchyMath.composeWorld(pt, link, t);
    }
    link.markSeen(t);
  }
}
