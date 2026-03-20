part of '../ecs.dart';

/// Unique identifier for an entity
typedef EntityId = int;

/// Base class for all components
///
/// Components are pure data containers with no logic.
/// Override to create custom component types.
///
/// Optionally override [onAttach] and [onDetach] for lifecycle notifications
/// when the component is added to or removed from an entity.
abstract class Component {
  /// Type identifier for this component
  Type get componentType => runtimeType;

  /// Called when this component is added to an entity.
  ///
  /// Override to perform setup that depends on the owning entity.
  /// The default implementation does nothing.
  void onAttach(EntityId entityId) {}

  /// Called when this component is removed from an entity.
  ///
  /// Override to perform cleanup. The default implementation does nothing.
  void onDetach(EntityId entityId) {}
}
