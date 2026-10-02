library;

import 'dart:math' as math;

import '../../ecs.dart';
import 'transform_component.dart';
import 'children_component.dart';
import 'parent_component.dart';
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
///   That includes a link just made with local values: its first pass
///   places the child at them.
///
/// Only entities with children are visited, so a world without a hierarchy
/// pays nothing. A parent's turn is worked out once for all its children,
/// and a 2-D child is not composed again while neither it, its parent nor
/// its local transform has changed — what it would be given is what it
/// already has.
class TransformHierarchy {
  /// The hierarchy of [world], enabled. The world makes its own; there is
  /// rarely a reason to make another.
  TransformHierarchy(this.world);

  /// The world this keeps in step.
  final World world;

  /// Whether the world runs this every frame. Turn off for a world whose
  /// parent links are only organisational.
  bool enabled = true;

  final List<Entity> _stack = [];

  // The cosine and sine of the angle of the parent being settled, worked
  // out on its first child that needs them.
  double _cos = 1.0;
  double _sin = 0.0;
  bool _haveTrig = false;

  void _trigOf(TransformComponent parent) {
    if (_haveTrig) return;
    _haveTrig = true;
    if (!parent.isPlanar) {
      _cos = 1.0;
      _sin = 0.0;
      return;
    }
    final a = parent.angle;
    _cos = math.cos(a);
    _sin = math.sin(a);
  }

  /// Settle every hierarchy in the world.
  void propagate() {
    for (final parent in world.query(const [ChildrenComponent])) {
      if (!_isRoot(parent)) continue;
      _walk(parent);
    }
  }

  /// Settle everything under [entity] — after an edit made outside the
  /// frame, say. [entity] itself is taken as given — unless its link was
  /// just made with local values ([ParentComponent.placesByLocal]), which
  /// place it under its parent.
  void propagateFrom(Entity entity) {
    if (!entity.isAlive) return;
    // Its own link first: an edited child must not be pulled back.
    final link = entity.getComponent<ParentComponent>();
    final t = entity.getComponent<TransformComponent>();
    if (link != null && t != null && link.parentId != null) {
      final parent = world.getEntity(link.parentId!);
      final pt = parent?.getComponent<TransformComponent>();
      if (pt != null && link.inheritTransform) {
        if (link.placesByLocal) {
          HierarchyMath.composeWorld(pt, link, t);
          link
            ..markSeen(t)
            ..markComposed(pt);
        } else {
          HierarchyMath.localFromWorld(pt, t, link);
          link
            ..needsLocal = false
            ..forgetComposed()
            ..markSeen(t);
        }
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
      _haveTrig = false;
      for (final id in children.childIds) {
        final child = world.getEntity(id);
        if (child == null || !child.isActive) continue;
        if (pt != null) _settle(parent.id, pt, child);
        // A leaf has nothing to walk: no need to stack it.
        if (child.hasComponent<ChildrenComponent>()) _stack.add(child);
      }
    }
  }

  void _settle(EntityId parentId, TransformComponent pt, Entity child) {
    final link = child.getComponent<ParentComponent>();
    final t = child.getComponent<TransformComponent>();
    if (link == null || t == null || link.parentId != parentId) return;
    if (!link.inheritTransform) return;
    // A link made with local values has nothing seen yet, and is placed by
    // them (the compose below); one made without derives them first.
    if (link.needsLocal || (!link.placesByLocal && link.movedSinceSeen(t))) {
      _trigOf(pt);
      HierarchyMath.localFromWorldWith(pt, t, link, _cos, _sin);
      link
        ..needsLocal = false
        ..forgetComposed()
        ..markSeen(t);
    } else if (!link.composedFrom(pt)) {
      _trigOf(pt);
      HierarchyMath.composeWorldWith(pt, link, t, _cos, _sin);
      link
        ..markSeen(t)
        ..markComposed(pt);
    }
  }
}
