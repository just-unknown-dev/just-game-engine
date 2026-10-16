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
///
/// Children switched off — themselves or with a parent
/// ([Entity.isActiveInHierarchy]) — are kept in step too, as a transform
/// is in Unity: a subtree switched back on is where its parent now is, and
/// a scene saved meanwhile keeps every child's place.
///
/// When a parent's previous pose was captured for render interpolation
/// since the last pass (`TransformComponent.captureCount` — a physics
/// step), a child placed by its local transform gets its previous pose
/// from the parent's too, so a renderer draws the two moving together
/// between steps instead of the child jumping a step at a time.
///
/// Links never loop: the world refuses a parent that would make an entity
/// its own ancestor. Only children whose `ParentComponent` names the
/// parent whose list they are on are walked.
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

  // The same for the parent's previous angle.
  double _prevCos = 1.0;
  double _prevSin = 0.0;
  bool _havePrevTrig = false;

  void _prevTrigOf(TransformComponent parent) {
    if (_havePrevTrig) return;
    _havePrevTrig = true;
    final a = parent.prevAngle;
    _prevCos = math.cos(a);
    _prevSin = math.sin(a);
  }

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

  /// Settle every hierarchy in the world — switched off or not.
  void propagate() {
    for (final archetype in world.queryArchetypes(const [ChildrenComponent])) {
      for (var row = 0; row < archetype.length; row++) {
        final parent = archetype.entityAt(row);
        if (_isRoot(parent)) _walk(parent);
      }
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

  /// Whether [entity] heads a hierarchy: it has no parent in the world.
  bool _isRoot(Entity entity) {
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    if (parentId == null) return true;
    final parent = world.getEntity(parentId);
    return parent == null || identical(parent, entity);
  }

  void _walk(Entity root) {
    _stack
      ..clear()
      ..add(root);
    // Each entity is settled at most once in a tree; more means the links
    // loop (which the world does not let them), and the walk stops.
    var budget = world.entityCount;
    while (_stack.isNotEmpty) {
      final parent = _stack.removeLast();
      final children = parent.getComponent<ChildrenComponent>();
      if (children == null) continue;
      final pt = parent.getComponent<TransformComponent>();
      _haveTrig = false;
      _havePrevTrig = false;
      for (final id in children.childIds) {
        final child = world.getEntity(id);
        if (child == null || identical(child, parent)) continue;
        // On the list, but linked to another parent or none: not this
        // parent's to settle, or to walk.
        if (child.getComponent<ParentComponent>()?.parentId != parent.id) {
          continue;
        }
        if (--budget < 0) return;
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
    // The parent's previous pose was captured since the last pass, and the
    // child's was not by anything else: the child's follows from it.
    final seenParent = link.parentCaptures;
    final parentCaptured =
        seenParent != -1 &&
        seenParent != pt.captureCount &&
        link.ownCaptures == t.captureCount;
    // A link made with local values has nothing seen yet, and is placed by
    // them (the compose below); one made without derives them first.
    if (link.needsLocal || (!link.placesByLocal && link.movedSinceSeen(t))) {
      _trigOf(pt);
      HierarchyMath.localFromWorldWith(pt, t, link, _cos, _sin);
      link
        ..needsLocal = false
        ..forgetComposed()
        ..markSeen(t);
    } else {
      if (!link.composedFrom(pt)) {
        _trigOf(pt);
        HierarchyMath.composeWorldWith(pt, link, t, _cos, _sin);
        link
          ..markSeen(t)
          ..markComposed(pt);
      }
      if (parentCaptured) {
        if (pt.previousIsPlanar) _prevTrigOf(pt);
        HierarchyMath.composePreviousWith(pt, link, t, _prevCos, _prevSin);
      }
    }
    link
      ..parentCaptures = pt.captureCount
      ..ownCaptures = t.captureCount;
  }
}
