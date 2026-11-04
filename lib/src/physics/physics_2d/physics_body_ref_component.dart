/// Component that links an ECS entity to a subsystem [PhysicsBody].
///
/// Attach this component to any entity that also has a [TransformComponent]
/// and should be driven by the subsystem [PhysicsEngine].
/// `Physics2DSystem` keeps them in sync each frame.
library;

import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

/// Links an entity to a subsystem [PhysicsBody] for automatic position sync.
class PhysicsBodyRefComponent extends Component {
  /// A link to [body]. `Physics2DSystem` attaches one when it adds an
  /// entity's body to the physics engine.
  PhysicsBodyRefComponent(this._body);

  PhysicsBody _body;

  /// The subsystem physics body managed by [PhysicsEngine]. When
  /// `Physics2DSystem` makes an entity's body again — its shape, scale or
  /// sensor flag changed — this same component names the new one, so the
  /// entity's structure (and every query over it) stays as it was.
  PhysicsBody get body => _body;

  /// The body made in its place; `Physics2DSystem` only.
  @internal
  set body(PhysicsBody value) => _body = value;

  @override
  String toString() => 'PhysicsBodyRef(body: $body)';
}
