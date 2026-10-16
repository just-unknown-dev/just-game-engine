/// Post-Process System
///
/// Synchronises [ShaderComponent] entities (marked [ShaderComponent.isPostProcess]
/// = true) with the [RenderingEngine]'s post-process pass list so the correct
/// shaders wrap the full scene each frame.
library;

import '../../../ecs/ecs.dart';
import '../../../ecs/components/components.dart';
import '../../../subsystems/rendering/rendering_engine.dart';
import '../../../subsystems/post_processing/post_process_pass.dart';
import '../../base/system_priorities.dart';

/// Manages fullscreen post-process shader passes on behalf of the ECS world.
///
/// Add this system to [World] once, passing a reference to the engine's
/// [RenderingEngine] and an optional elapsed-time provider. It then
/// automatically mirrors every active [ShaderComponent] with
/// [ShaderComponent.isPostProcess] = `true` as a [PostProcessPass] on the
/// [RenderingEngine], ordering and enabling passes to match the components.
///
/// ### Registration
///
/// ```dart
/// world.addSystem(PostProcessSystem(
///   engine.rendering,
///   getTime: () => engine.time.totalTime,
/// ));
/// ```
///
/// ### Adding a fullscreen pass
///
/// ```dart
/// final program = await FragmentProgram.fromAsset('shaders/chromatic.frag');
///
/// final vfxEntity = world.createEntity();
/// world.addComponent(vfxEntity, ShaderComponent(
///   program: program,
///   isPostProcess: true,
///   passOrder: 1,
///   setUniforms: (shader, w, h, t) {
///     shader.setFloat(0, w);
///     shader.setFloat(1, h);
///     shader.setFloat(2, t);
///   },
/// ));
/// ```
///
/// ### Disabling a pass at runtime
///
/// ```dart
/// entity.getComponent<ShaderComponent>()!.enabled = false;
/// ```
///
/// ### Multiple chained passes
///
/// Passes are ordered by [ShaderComponent.passOrder] (ascending).
/// The lowest order is applied closest to the raw scene (innermost);
/// the highest order composites last (outermost, visible to the viewer).
///
/// ```
/// passOrder = 0   →  bloom          (innermost: applied to raw scene)
/// passOrder = 1   →  chromatic      (applied to bloom output)
/// passOrder = 2   →  vignette       (outermost: applied to everything)
/// ```
class PostProcessSystem extends System {
  /// The [RenderingEngine] whose post-process pass list this system drives.
  final RenderingEngine _renderingEngine;

  /// Optional provider for the current engine time in seconds.
  ///
  /// When non-null, [PostProcessSystem.update] writes the returned value to
  /// [RenderingEngine.elapsedSeconds] each frame so shaders that receive a
  /// `time` uniform stay animated.
  ///
  /// Example: `getTime: () => engine.time.totalTime`.
  final double Function()? _getTime;

  /// Internal registry: entity id → the pass registered for it, and the
  /// frame it was last seen in.
  ///
  /// Used to detect additions / removals and avoid duplicate registration.
  final Map<EntityId, _Registered> _registeredPasses = {};

  /// Counts updates, to tell which passes an update saw.
  int _frame = 0;

  static const List<Type> _query = [ShaderComponent];

  /// Create a [PostProcessSystem].
  ///
  /// `renderingEngine` — The [RenderingEngine] to drive.
  /// [getTime]         — Optional elapsed-time provider. Pass
  ///                     `() => engine.time.totalTime` for animated shaders.
  PostProcessSystem(this._renderingEngine, {double Function()? getTime})
    : _getTime = getTime;

  @override
  int get priority => SystemPriorities.postProcess;

  @override
  List<Type> get requiredComponents => const [ShaderComponent];

  // ── Per-frame synchronisation ───────────────────────────────────────────

  @override
  void update(double deltaTime) {
    // Advance the rendering engine's time cursor so shaders receive a
    // meaningful elapsed-time value.
    if (_getTime != null) {
      _renderingEngine.elapsedSeconds = _getTime();
    }
    _frame++;

    for (final entity in world.query(_query)) {
      if (!entity.isActive) continue;

      final comp = entity.getComponent<ShaderComponent>()!;
      if (!comp.isPostProcess) continue;

      final shader = comp.shader;
      var registered = _registeredPasses[entity.id];
      // A pass holds its shader for good. The entity's component — or its
      // shader — being another one than the pass was made for means the
      // component was replaced (and the old shader disposed with it): the
      // old pass goes, and one is made for what is there now.
      if (registered != null && !identical(registered.pass.shader, shader)) {
        _renderingEngine.removePostProcessPass(registered.pass);
        registered = null;
      }
      if (registered == null) {
        final pass = PostProcessPass(
          shader: shader,
          passOrder: comp.passOrder,
          enabled: comp.enabled,
          setUniforms: comp.setUniforms,
        );
        _registeredPasses[entity.id] = registered = _Registered(pass);
        _renderingEngine.addPostProcessPass(pass);
      } else {
        // Sync mutable properties every frame (cheap assignments). The
        // rendering engine re-sorts when a pass order changes.
        registered.pass
          ..passOrder = comp.passOrder
          ..enabled = comp.enabled
          ..setUniforms = comp.setUniforms;
      }
      registered.seen = _frame;
    }

    // ── Remove passes for entities that are gone, switched off, or no
    // longer carry a post-process shader ─────────────────────────────────
    _registeredPasses.removeWhere((_, registered) {
      if (registered.seen == _frame) return false;
      _renderingEngine.removePostProcessPass(registered.pass);
      return true;
    });
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void onRemovedFromWorld() {
    // Clean up all registered passes when the system is removed.
    for (final registered in _registeredPasses.values) {
      _renderingEngine.removePostProcessPass(registered.pass);
    }
    _registeredPasses.clear();
  }

  @override
  void dispose() {
    onRemovedFromWorld();
  }
}

/// A pass registered for an entity, and the update that last saw it.
class _Registered {
  _Registered(this.pass);
  final PostProcessPass pass;
  int seen = 0;
}
