part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Entity Prefab — reusable entity blueprints
// ════════════════════════════════════════════════════════════════════════════

/// A factory function that creates a fresh [Component] instance.
typedef ComponentFactory = Component Function();

/// A reusable entity blueprint that can be instantiated many times.
///
/// Prefabs define a list of component factories. Each call to
/// [World.instantiate] creates a new entity with fresh component instances
/// produced by those factories.
///
/// ```dart
/// final bulletPrefab = EntityPrefab(
///   name: 'Bullet',
///   factories: [
///     () => TransformComponent(),
///     () => VelocityComponent(velocity: Offset(500, 0)),
///     () => SpriteComponent(spritePath: 'bullet.png'),
///     () => LifetimeComponent(duration: 2.0),
///   ],
/// );
///
/// // Spawn 100 bullets efficiently:
/// for (var i = 0; i < 100; i++) {
///   world.instantiate(bulletPrefab);
/// }
/// ```
class EntityPrefab {
  /// Optional display name for debugging.
  final String? name;

  /// Component factories — each produces a fresh component per instantiation.
  final List<ComponentFactory> factories;

  /// Create a prefab with the given component [factories].
  const EntityPrefab({this.name, required this.factories});
}
