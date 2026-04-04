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
import '../system_priorities.dart';

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

  /// Internal registry: entity id → registered [PostProcessPass].
  ///
  /// Used to detect additions / removals and avoid duplicate registration.
  final Map<EntityId, PostProcessPass> _registeredPasses = {};

  /// Create a [PostProcessSystem].
  ///
  /// [renderingEngine] — The [RenderingEngine] to drive.
  /// [getTime]         — Optional elapsed-time provider. Pass
  ///                     `() => engine.time.totalTime` for animated shaders.
  PostProcessSystem(this._renderingEngine, {double Function()? getTime})
    : _getTime = getTime;

  @override
  int get priority => SystemPriorities.postProcess;

  @override
  List<Type> get requiredComponents => [ShaderComponent];

  // ── Per-frame synchronisation ───────────────────────────────────────────

  @override
  void update(double deltaTime) {
    // Advance the rendering engine's time cursor so shaders receive a
    // meaningful elapsed-time value.
    if (_getTime != null) {
      _renderingEngine.elapsedSeconds = _getTime();
    }

    // ── Collect currently active post-process entity IDs ─────────────────
    final activeIds = <EntityId>{};

    for (final entity in world.query([ShaderComponent])) {
      if (!entity.isActive) continue;

      final comp = entity.getComponent<ShaderComponent>()!;
      if (!comp.isPostProcess) continue;

      activeIds.add(entity.id);

      final existing = _registeredPasses[entity.id];
      if (existing == null) {
        // New post-process entity — create and register a pass.
        final pass = PostProcessPass(
          shader: comp.shader,
          passOrder: comp.passOrder,
          enabled: comp.enabled,
          setUniforms: comp.setUniforms,
        );
        _registeredPasses[entity.id] = pass;
        _renderingEngine.addPostProcessPass(pass);
      } else {
        // Sync mutable properties every frame (cheap assignments).
        existing.passOrder = comp.passOrder;
        existing.enabled = comp.enabled;
        existing.setUniforms = comp.setUniforms;
      }
    }

    // ── Remove passes for entities that are no longer active ─────────────
    final staleIds = _registeredPasses.keys
        .where((id) => !activeIds.contains(id))
        .toList();

    for (final id in staleIds) {
      _renderingEngine.removePostProcessPass(_registeredPasses[id]!);
      _registeredPasses.remove(id);
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void onRemovedFromWorld() {
    // Clean up all registered passes when the system is removed.
    for (final pass in _registeredPasses.values) {
      _renderingEngine.removePostProcessPass(pass);
    }
    _registeredPasses.clear();
  }

  @override
  void dispose() {
    onRemovedFromWorld();
  }
}
