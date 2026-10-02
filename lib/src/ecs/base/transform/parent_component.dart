library;

import 'dart:typed_data';

import 'package:just_dart/just_dart.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs.dart';
import 'euler_rotation.dart';
import 'transform_component.dart';

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
///
/// The world keeps the other end of the link: while this component is on
/// an entity, the parent it names lists the entity in its
/// `ChildrenComponent` — made for it when it has none — and a child that
/// leaves (unlinked, re-linked, the component removed, the entity
/// destroyed) is taken off the list. The transform hierarchy walks those
/// lists, so a link with no list would do nothing.
class ParentComponent extends Component {
  EntityId? _parentId;

  /// Parent entity ID (null if root). Changing it on an entity moves the
  /// entity from the old parent's `ChildrenComponent` to the end of the
  /// new one's.
  EntityId? get parentId => _parentId;
  set parentId(EntityId? value) {
    final old = _parentId;
    if (old == value) return;
    _parentId = value;
    _onRelink?.call(old, value);
  }

  /// Told by the world when [parentId] changes while this is on an entity.
  void Function(EntityId? from, EntityId? to)? _onRelink;

  /// For the world: calls [onRelink] with the old and new parent each time
  /// [parentId] changes, until set to null.
  @internal
  void bindRelink(void Function(EntityId? from, EntityId? to)? onRelink) =>
      _onRelink = onRelink;

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

  /// The rotation last seen, in radians: `eulerX`, `eulerY` and `angle` of
  /// the world transform as x, y, z.
  final Vector3 seenEuler = Vector3.zero();

  /// The world scale last seen.
  final Vector3 seenScale = Vector3.zero();

  /// Whether [seenPosition] and friends hold anything yet.
  bool hasSeen = false;

  /// Whether the next hierarchy pass places the entity by its local
  /// transform rather than reading one from its world transform: a link
  /// made with local values that no pass has settled yet.
  bool get placesByLocal => !needsLocal && !hasSeen;

  /// Create a link to [parentId].
  ///
  /// Given no local values, the entity keeps its world transform and its
  /// local one is derived from it ([needsLocal]) — how a scene file's
  /// links load. Given any (the others take their defaults: no offset, no
  /// turn, a scale of 1), the entity is placed at them relative to the
  /// parent on the next pass of the hierarchy ([placesByLocal]): its world
  /// transform is composed from the parent's and these, whatever it was.
  ParentComponent({
    EntityId? parentId,
    Vector3? localPosition,
    EulerRotation? localRotation,
    Vector3? localScale,
    this.inheritTransform = true,
  }) : _parentId = parentId,
       localPosition = localPosition ?? Vector3.zero(),
       localRotation = localRotation ?? EulerRotation(),
       localScale = localScale ?? Vector3(1.0, 1.0, 1.0),
       needsLocal =
           localPosition == null && localRotation == null && localScale == null;

  /// Forget the local transform: the next pass derives it from the world
  /// transform again. Call after re-parenting, or after writing the world
  /// transform where the change must not be mistaken for the parent's.
  void invalidateLocal() {
    needsLocal = true;
    hasSeen = false;
    _composed = false;
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

  // ── What the last compose was made from ────────────────────────────────
  //
  // A 2-D child whose parent has not moved, and whose local transform has
  // not changed, would be composed into exactly the world transform it
  // already has; the hierarchy skips it. Planar only: there a compose reads
  // nothing but these values.

  final Float64List _from = Float64List(14);
  bool _composed = false;

  /// Whether composing this entity under [parent] now would read exactly
  /// what the last compose did — so it would write what is already there.
  /// For the transform hierarchy.
  @internal
  bool composedFrom(TransformComponent parent) {
    if (!_composed || !parent.isPlanar || !localRotation.isPlanar) {
      return false;
    }
    final p = parent.position, s = parent.scale;
    return _same(_from[0], p.x) &&
        _same(_from[1], p.y) &&
        _same(_from[2], p.z) &&
        _same(_from[3], parent.angle) &&
        _same(_from[4], s.x) &&
        _same(_from[5], s.y) &&
        _same(_from[6], s.z) &&
        _same(_from[7], localPosition.x) &&
        _same(_from[8], localPosition.y) &&
        _same(_from[9], localPosition.z) &&
        _same(_from[10], localRotation.z) &&
        _same(_from[11], localScale.x) &&
        _same(_from[12], localScale.y) &&
        _same(_from[13], localScale.z);
  }

  /// Remember [parent] and the local transform as what this entity was
  /// just composed from. For the transform hierarchy.
  @internal
  void markComposed(TransformComponent parent) {
    _composed = parent.isPlanar && localRotation.isPlanar;
    if (!_composed) return;
    final p = parent.position, s = parent.scale;
    _from
      ..[0] = p.x
      ..[1] = p.y
      ..[2] = p.z
      ..[3] = parent.angle
      ..[4] = s.x
      ..[5] = s.y
      ..[6] = s.z
      ..[7] = localPosition.x
      ..[8] = localPosition.y
      ..[9] = localPosition.z
      ..[10] = localRotation.z
      ..[11] = localScale.x
      ..[12] = localScale.y
      ..[13] = localScale.z;
  }

  /// The local transform was just worked out again: the next pass must
  /// compose. For the transform hierarchy.
  @internal
  void forgetComposed() => _composed = false;

  /// Equal to the bit: 0.0 and -0.0 differ, as they would in a compose.
  static bool _same(double a, double b) =>
      a == b && (a != 0.0 || a.isNegative == b.isNegative);

  @override
  String toString() => 'Parent($parentId)';
}
