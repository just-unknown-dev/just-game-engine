/// Cameras whose shot comes from their children.
library;

import 'package:flutter/animation.dart' show Curves;

import '../../ecs/ecs.dart';
import 'camera_brain.dart';
import 'camera_stage.dart';
import 'camera_state.dart';

/// Everything a manager may look at while choosing among its children.
class CameraManagerContext {
  CameraManagerContext({
    required this.brain,
    required this.world,
    required this.entity,
    required this.memory,
    required this.children,
    required this.dt,
    required this.snap,
    required CameraState? Function(Entity child) stateOfChild,
  }) : _stateOfChild = stateOfChild;

  final CameraBrain brain;
  final World world;

  /// The manager's entity.
  final Entity entity;
  final CameraRigMemory memory;

  /// The manager's enabled child cameras, in hierarchy order.
  final List<Entity> children;
  final double dt;
  final bool snap;

  final CameraState? Function(Entity child) _stateOfChild;

  /// Runs [child]'s own pipeline (once a frame) and returns its state.
  CameraState? stateOf(Entity child) => _stateOfChild(child);

  Entity? childNamed(String name) {
    if (name.isEmpty) return null;
    for (final child in children) {
      if (child.name == name) return child;
    }
    return null;
  }
}

/// Turns one component type into a camera made of child cameras.
///
/// Registered with [CameraBrain.managers], the same way a stage is: a kit
/// with its own idea of how to choose a shot writes a component and one of
/// these.
abstract class CameraManager<T extends Component> {
  const CameraManager();

  Type get componentType => T;

  /// The shot to show, or null to fall back to the manager entity's own.
  CameraState? evaluate(CameraManagerContext context, T component);

  CameraState? evaluateAny(CameraManagerContext context, Component component) =>
      evaluate(context, component as T);
}

/// Which manager runs for which component.
class CameraManagerRegistry {
  final Map<Type, CameraManager> _managers = {};

  void register(CameraManager manager, {bool override = false}) {
    if (!override && _managers.containsKey(manager.componentType)) {
      throw StateError(
        'A camera manager for ${manager.componentType} is already registered',
      );
    }
    _managers[manager.componentType] = manager;
  }

  void registerAll(Iterable<CameraManager> managers) {
    for (final manager in managers) {
      register(manager);
    }
  }

  void unregister(Type componentType) => _managers.remove(componentType);

  /// The manager [entity] carries, with its component, or null.
  (CameraManager, Component)? managerOf(Entity entity) {
    if (_managers.isEmpty) return null;
    for (final component in entity.components) {
      final manager = _managers[component.runtimeType];
      if (manager != null) return (manager, component);
    }
    return null;
  }
}

/// Blends from whichever child a manager was showing to the one it shows
/// now. Kept in the manager's memory, so it starts fresh when the manager
/// does.
class CameraChildBlender {
  EntityId? _showing;
  CameraState? _from;
  CameraState? _last;
  double _elapsed = 0;
  double _duration = 0;

  EntityId? get showing => _showing;

  /// What to show for [child], whose own state this frame is [state].
  CameraState show(
    EntityId child,
    CameraState state, {
    required double blend,
    required double dt,
    required bool snap,
  }) {
    if (_showing != child) {
      final from = _last;
      _showing = child;
      if (snap || from == null || blend <= 0) {
        _from = null;
      } else {
        _from = from;
        _elapsed = 0;
        _duration = blend;
      }
    }
    var out = state;
    final from = _from;
    if (from != null) {
      _elapsed += dt;
      final t = (_elapsed / _duration).clamp(0.0, 1.0);
      if (snap || t >= 1) {
        _from = null;
      } else {
        out = CameraState.lerp(from, state, Curves.easeInOut.transform(t));
      }
    }
    return _last = out;
  }
}
