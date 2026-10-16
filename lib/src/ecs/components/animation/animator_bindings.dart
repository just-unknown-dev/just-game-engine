/// What an animator graph's parameters can be bound to: an entity's own
/// state, read every frame.
library;

import '../../ecs.dart';
import '../core/velocity_component.dart';
import '../gameplay/health_component.dart';

/// Reads an entity's own state into an animator parameter, every frame.
/// Returns a `num` or a `bool`, or null to leave the parameter alone.
typedef AnimatorBinding = Object? Function(Entity entity);

/// The sources a graph's parameter can be bound to, by id.
///
/// The engine registers the ones below; a kit adds its own — a platformer's
/// `grounded` — so a graph can use them without the game writing glue. Each
/// engine has its own (`engine.context.animatorBindings`); [builtIn] holds
/// only the engine's and cannot be changed.
final class AnimatorBindings {
  /// The engine's bindings (unless [withBuiltIns] is false), to add to.
  AnimatorBindings({bool withBuiltIns = true}) : _frozen = false {
    if (withBuiltIns) _sources.addAll(_engine);
  }

  AnimatorBindings._frozen() : _frozen = true {
    _sources.addAll(_engine);
  }

  /// The engine's bindings and nothing else. Read-only: [register] throws.
  static final AnimatorBindings builtIn = AnimatorBindings._frozen();

  final bool _frozen;
  final Map<String, AnimatorBinding> _sources = {};

  static final Map<String, AnimatorBinding> _engine = {
    'velocityX': (e) => e.getComponent<VelocityComponent>()?.velocity.x,
    'velocityY': (e) => e.getComponent<VelocityComponent>()?.velocity.y,
    'speed': (e) => e.getComponent<VelocityComponent>()?.speed,
    'speedX': (e) => e.getComponent<VelocityComponent>()?.velocity.x.abs(),
    'speedY': (e) => e.getComponent<VelocityComponent>()?.velocity.y.abs(),
    'health': (e) => e.getComponent<HealthComponent>()?.health,
    'healthFraction': (e) {
      final h = e.getComponent<HealthComponent>();
      if (h == null) return null;
      return h.maxHealth <= 0 ? 0.0 : h.health / h.maxHealth;
    },
    'alive': (e) {
      final h = e.getComponent<HealthComponent>();
      return h == null ? null : h.health > 0;
    },
  };

  void _check() {
    if (_frozen) {
      throw UnsupportedError(
        "AnimatorBindings.builtIn cannot be changed: register into an engine's "
        '(engine.context.animatorBindings).',
      );
    }
  }

  /// Adds (or replaces) the source called [id].
  void register(String id, AnimatorBinding read) {
    _check();
    _sources[id] = read;
  }

  /// Removes the source called [id], built-in or not; nothing when there is
  /// none. Throws [UnsupportedError] on [builtIn].
  void unregister(String id) {
    _check();
    _sources.remove(id);
  }

  /// The source called [id], or null when none is registered under it (a
  /// parameter bound to it is then left alone).
  AnimatorBinding? of(String id) => _sources[id];

  /// Every id, for an editor's dropdown.
  List<String> get ids => _sources.keys.toList()..sort();
}
