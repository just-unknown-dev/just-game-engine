library;

import '../../ecs.dart';
import '../core/euler_rotation.dart';
import '../core/transform_component.dart';
import 'package:just_dart/just_dart.dart';

/// Hangs an entity under a parent: it moves, turns and scales with it.
///
/// The entity's `TransformComponent` stays its **world** transform — what
/// every system reads and writes, and what is saved. This component holds
/// where the entity sits *in its parent's space* ([localPosition],
/// [localRotation], [localScale]), and the world's transform hierarchy
/// (see [TransformHierarchy]) keeps the two in step each frame:
///
/// * when the parent moves, the child's world transform follows from its
///   local one;
/// * when something writes the child's world transform directly — physics,
///   a timeline, gameplay, an editor tool — its local one is worked out
///   again from it, and the child stays where it was put.
///
/// The local values are runtime state, never saved: a scene file holds the
/// world transforms, and the local ones are derived from those when the
/// scene loads ([needsLocal]).
class ParentComponent extends Component {
  /// Parent entity ID (null if root)
  EntityId? parentId;

  /// Where this entity is in its parent's space.
  final Vector3 localPosition;

  /// How it is turned relative to its parent.
  final EulerRotation localRotation;

  /// Its scale relative to its parent's.
  final Vector3 localScale;

  /// Whether this entity follows its parent at all. Off, the link is only
  /// organisational — the child keeps whatever world transform it is given.
  bool inheritTransform;

  /// Whether the local transform still has to be worked out from the world
  /// one — true for a link made without local values, such as one read
  /// from a scene file; the hierarchy clears it on its next pass.
  bool needsLocal;

  /// The world transform the hierarchy last saw on this entity, to tell
  /// whether something else has moved it since.
  final Vector3 seenPosition = Vector3.zero();
  final Vector3 seenEuler = Vector3.zero();
  final Vector3 seenScale = Vector3.zero();

  /// Whether [seenPosition] and friends hold anything yet.
  bool hasSeen = false;

  /// Create a link to [parentId].
  ///
  /// Given no local values, the entity keeps its world transform and its
  /// local one is derived from it ([needsLocal]). Given any, the entity is
  /// placed at them relative to the parent on the next pass.
  ParentComponent({
    this.parentId,
    Vector3? localPosition,
    EulerRotation? localRotation,
    Vector3? localScale,
    this.inheritTransform = true,
  }) : localPosition = localPosition ?? Vector3.zero(),
       localRotation = localRotation ?? EulerRotation(),
       localScale = localScale ?? Vector3(1.0, 1.0, 1.0),
       needsLocal =
           localPosition == null &&
           localRotation == null &&
           localScale == null;

  /// Forget the local transform: the next pass derives it from the world
  /// transform again. Call after re-parenting, or after writing the world
  /// transform where the change must not be mistaken for the parent's.
  void invalidateLocal() {
    needsLocal = true;
    hasSeen = false;
  }

  /// Remember [t] as the world transform the hierarchy has settled.
  void markSeen(TransformComponent t) {
    seenPosition.setFrom(t.position);
    seenEuler.setValues(t.eulerX, t.eulerY, t.angle);
    seenScale.setFrom(t.scale);
    hasSeen = true;
  }

  /// Whether [t] differs from what the hierarchy last settled — i.e.
  /// something other than the hierarchy has moved this entity.
  bool movedSinceSeen(TransformComponent t) =>
      !hasSeen ||
      t.position.x != seenPosition.x ||
      t.position.y != seenPosition.y ||
      t.position.z != seenPosition.z ||
      t.angle != seenEuler.z ||
      t.eulerX != seenEuler.x ||
      t.eulerY != seenEuler.y ||
      t.scale.x != seenScale.x ||
      t.scale.y != seenScale.y ||
      t.scale.z != seenScale.z;

  @override
  String toString() => 'Parent($parentId)';
}
