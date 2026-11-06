/// Component that links an ECS entity to a subsystem [Physics2DBody].
///
/// Attach this component to any entity that also has a [TransformComponent]
/// and should be driven by the subsystem [Physics2DEngine].
/// `Physics2DSystem` keeps them in sync each frame.
library;

import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

/// Links an entity to a subsystem [Physics2DBody] for automatic position sync.
class Physics2DBodyRefComponent extends Component {
  /// A link to [body]. `Physics2DSystem` attaches one when it adds an
  /// entity's body to the physics engine.
  Physics2DBodyRefComponent(this._body);

  Physics2DBody _body;

  /// The subsystem physics body managed by [Physics2DEngine]. When
  /// `Physics2DSystem` makes an entity's body again — its shape, scale or
  /// sensor flag changed — this same component names the new one, so the
  /// entity's structure (and every query over it) stays as it was.
  Physics2DBody get body => _body;

  /// The body made in its place; `Physics2DSystem` only.
  @internal
  set body(Physics2DBody value) => _body = value;

  @override
  String toString() => 'Physics2DBodyRef(body: $body)';
}
