/// Picks the live virtual camera and blends the output toward it.
library;

import 'package:flutter/painting.dart' show Offset, Size;

import '../../components/components.dart';
import '../../ecs.dart';
import '../../../subsystems/camera/camera_impulse.dart';
import 'camera_manager.dart';
import 'camera_stage.dart';
import '../../../subsystems/camera/camera_state.dart';
import '../../../subsystems/camera/camera_system.dart';
import 'camera_targets.dart';
import 'managers/built_in_managers.dart';
import 'stages/dolly_stage.dart';
import 'stages/extension_stages.dart';
import 'stages/framing_stage.dart';
import 'stages/group_framing_stage.dart';

/// A blend in progress.
class ActiveCameraBlend {
  ActiveCameraBlend._({
    required this.blend,
    required this.fromId,
    required CameraState fromSnapshot,
  }) : _fromSnapshot = fromSnapshot;

  /// How long the blend takes and how it eases.
  final CameraBlend blend;

  /// The camera being blended from, while it still exists. Null when the
  /// blend started from a blend — then it leaves from a frozen shot.
  final EntityId? fromId;

  // The last shot seen from the camera being left: the blend keeps leaving
  // from here if that camera goes away mid-blend.
  CameraState _fromSnapshot;

  /// Seconds into the blend.
  double elapsed = 0;

  /// 0 → 1, before easing.
  double get progress =>
      blend.isCut ? 1 : (elapsed / blend.duration).clamp(0.0, 1.0);

  /// Whether the blend has run its full duration; the brain drops it on
  /// the frame this turns true.
  bool get isComplete => progress >= 1;
}

/// Decides what the camera shows.
///
/// Every frame it finds the virtual cameras in the world, runs each live
/// one's stage pipeline to get its [CameraState], picks the enabled one with
/// the highest priority, and blends the [output] camera toward it. With no
/// virtual camera in the world it does nothing at all, so a game that moves
/// the output camera by hand is left alone.
class CameraBrain {
  /// A brain driving [output], with the engine's stages (group framing,
  /// framing, dolly, noise, impulse listener, confiner) and managers
  /// (state-driven, blend list, mixer) already registered.
  CameraBrain(this.output) {
    stages.registerAll(const [
      GroupFramingStage(),
      FramingStage(),
      DollyStage(),
      NoiseStage(),
      ImpulseListenerStage(),
      ConfinerStage(),
    ]);
    managers.registerAll(const [
      StateDrivenManager(),
      BlendListManager(),
      MixerManager(),
    ]);
  }

  /// The camera everything renders through.
  final Camera output;

  /// The stage that runs for each component type. Register a kit's own here.
  final CameraStageRegistry stages = CameraStageRegistry();

  /// The manager that runs for each component type: cameras whose shot
  /// comes from their child cameras.
  final CameraManagerRegistry managers = CameraManagerRegistry();

  /// Looks up follow targets and named entities for this frame; stages and
  /// managers resolve through it.
  final CameraTargetResolver targets = CameraTargetResolver();

  /// The impulses in the air; cameras with a listener feel them.
  final CameraImpulseBus impulses = CameraImpulseBus();

  /// False makes the brain think without acting: it still evaluates and
  /// [liveState] stays current, but [output] is left alone. An editor sets
  /// this while authoring, so its own pan and zoom own the view and it can
  /// still draw what the game camera *would* show.
  bool driveOutput = true;

  /// The blend between two cameras no [blendTable] rule names.
  CameraBlend defaultBlend = const CameraBlend();

  /// Blends for particular pairs of cameras, by entity name; empty by
  /// default, so every change of camera uses [defaultBlend].
  CameraBlendTable blendTable = CameraBlendTable();

  /// Forces this camera live whatever its priority, for looking through one
  /// shot while working on it. Ignored once the entity is gone.
  EntityId? soloEntity;

  /// Used for framing when [output] has not been laid out yet (a test, a
  /// headless run).
  Size? viewportOverride;

  /// Called when a different camera goes live. `from` is null for the first;
  /// it is the camera that was live even when that camera has just been
  /// switched off or destroyed — which is why the cut happened.
  void Function(Entity? from, Entity to)? onCameraActivated;

  final Map<EntityId, CameraRigMemory> _memory = {};
  final Map<EntityId, CameraState> _states = {};
  final Map<EntityId, int> _activation = {};
  int _activationCounter = 0;

  // Which frame each managed child last ran in, so two managers sharing a
  // child — or one asking twice — run its pipeline once.
  final Map<EntityId, int> _ranAt = {};
  int _frame = 0;

  Entity? _live;
  CameraState? _liveState;
  ActiveCameraBlend? _blend;

  /// The virtual camera that is live, or null when the world has none.
  Entity? get liveCamera => _live;

  /// What the brain wants on screen this frame, blend included.
  CameraState? get liveState => _liveState;

  /// The blend into [liveCamera] in progress, or null when none is.
  ActiveCameraBlend? get activeBlend => _blend;

  /// Whether the last [evaluate] found an enabled virtual camera to show;
  /// false again after [reset].
  bool get hasCameras => _live != null;

  /// The last state [camera]'s own pipeline produced, blend excluded — what
  /// an editor draws a standby camera's frame from.
  CameraState? stateOf(Entity camera) => _states[camera.id];

  /// Puts [camera] ahead of every other camera of the same priority.
  void activate(Entity camera) => _activation[camera.id] = ++_activationCounter;

  /// Something happened that cameras should feel.
  void emitImpulse(CameraImpulse impulse) => impulses.emit(impulse);

  /// Emits the impulse [source] is authored with, from where it is. False
  /// when it has no `CameraImpulseSourceComponent` or no position.
  bool emitImpulseFrom(Entity source) {
    final authored = source.getComponent<CameraImpulseSourceComponent>();
    final at = CameraTargetResolver.positionOf(source);
    if (authored == null || at == null) return false;
    impulses.emit(
      CameraImpulse(
        position: at,
        amplitude: authored.amplitude,
        duration: authored.duration,
        radius: authored.radius,
        channel: authored.channel,
      ),
    );
    return true;
  }

  /// Forgets everything: call when the world's entities are replaced.
  void reset() {
    impulses.clear();
    _memory.clear();
    _states.clear();
    _activation.clear();
    _ranAt.clear();
    _live = null;
    _liveState = null;
    _blend = null;
  }

  /// One frame of camera thinking.
  ///
  /// [snap] skips damping and blends: every camera jumps to where it wants to
  /// be. That is what an editor asks for while the game is frozen, and what a
  /// game asks for after teleporting the player.
  void evaluate(World world, double dt, {bool snap = false}) {
    targets.beginFrame(world);
    impulses.update(dt);

    _frame++;
    final all = <Entity>[
      for (final entity in world.query([
        TransformComponent,
        VirtualCameraComponent,
      ]))
        if (entity.isActive &&
            entity.getComponent<VirtualCameraComponent>()!.enabled)
          entity,
    ];
    // A manager's children are its own business: the brain sees only the
    // manager, at the manager's priority.
    final managed = <EntityId>{};
    for (final entity in all) {
      if (managers.managerOf(entity) == null) continue;
      for (final child in _childrenOf(world, entity)) {
        managed.add(child.id);
      }
    }
    final cameras = managed.isEmpty
        ? all
        : [
            for (final entity in all)
              if (!managed.contains(entity.id)) entity,
          ];
    _forgetAllBut(cameras, managed);
    if (cameras.isEmpty) {
      _live = null;
      _liveState = null;
      _blend = null;
      return;
    }
    for (final camera in cameras) {
      _activation.putIfAbsent(camera.id, () => ++_activationCounter);
    }

    final next = _pick(cameras);
    // The camera that was live, even if it has just been switched off or
    // destroyed: a blend rule naming it, and onCameraActivated, still see
    // where the cut came from.
    final previous = _live;
    if (!identical(next, previous)) {
      _goLive(next, previous, cameras, snap: snap);
    }

    // Live, outgoing and always-on cameras run every frame; the rest run
    // once, so there is a frame to draw for them.
    final outgoing = _blend?.fromId;
    for (final camera in cameras) {
      final vcam = camera.getComponent<VirtualCameraComponent>()!;
      final memory = _memory.putIfAbsent(camera.id, CameraRigMemory.new);
      final runs =
          snap ||
          identical(camera, _live) ||
          camera.id == outgoing ||
          vcam.standbyUpdate == CameraStandbyUpdate.always ||
          !memory.initialized;
      if (!runs) continue;
      _states[camera.id] = _run(world, camera, vcam, memory, dt, snap);
    }

    var state = _states[next.id]!;
    final blend = _blend;
    if (blend != null) {
      blend.elapsed += dt;
      if (snap || blend.isComplete) {
        _blend = null;
      } else {
        final from =
            (blend.fromId == null ? null : _states[blend.fromId]) ??
            blend._fromSnapshot;
        blend._fromSnapshot = from;
        state = CameraState.lerp(
          from,
          state,
          blend.blend.curve.transform(blend.progress),
        );
      }
    }
    _liveState = state;
    if (driveOutput) output.apply(state);
  }

  Entity _pick(List<Entity> cameras) {
    final solo = soloEntity;
    if (solo != null) {
      for (final camera in cameras) {
        if (camera.id == solo) return camera;
      }
    }
    var best = cameras.first;
    for (final camera in cameras.skip(1)) {
      final a = camera.getComponent<VirtualCameraComponent>()!.priority;
      final b = best.getComponent<VirtualCameraComponent>()!.priority;
      if (a > b ||
          (a == b && _activation[camera.id]! > _activation[best.id]!)) {
        best = camera;
      }
    }
    return best;
  }

  void _goLive(
    Entity next,
    Entity? previous,
    List<Entity> cameras, {
    required bool snap,
  }) {
    final from = _liveState;
    // A camera that was not running has stale damping: its first live frame
    // starts from its target, not from wherever it was last.
    final vcam = next.getComponent<VirtualCameraComponent>()!;
    if (vcam.standbyUpdate == CameraStandbyUpdate.never) {
      _memory[next.id]?.reset();
    }
    final blend = blendTable.resolve(previous?.name, next.name) ?? defaultBlend;
    if (snap || from == null || blend.isCut) {
      _blend = null;
    } else {
      // Leaving mid-blend there is no single camera to keep following, and
      // a camera switched off or destroyed has nothing more to show: either
      // way, leave from exactly what is on screen.
      final followFrom =
          _blend == null &&
          previous != null &&
          cameras.any((camera) => identical(camera, previous));
      _blend = ActiveCameraBlend._(
        blend: blend,
        fromId: followFrom ? previous.id : null,
        fromSnapshot: from,
      );
    }
    _live = next;
    onCameraActivated?.call(previous, next);
  }

  CameraState _run(
    World world,
    Entity camera,
    VirtualCameraComponent vcam,
    CameraRigMemory memory,
    double dt,
    bool snap,
  ) {
    final transform = camera.getComponent<TransformComponent>()!;
    final target = vcam.hasTarget
        ? targets.resolveTarget(vcam.follow, owner: camera)
        : null;
    final context = CameraStageContext(
      brain: this,
      world: world,
      entity: camera,
      vcam: vcam,
      memory: memory,
      viewportSize: viewportOverride ?? output.viewportSize,
      snap: snap,
      target: target,
      targetPosition: target == null
          ? null
          : CameraTargetResolver.positionOf(target),
      targetVelocity: target == null
          ? Offset.zero
          : CameraTargetResolver.velocityOf(target) ?? Offset.zero,
    );
    var state = CameraState(
      position: transform.position.toOffset(),
      zoom: vcam.zoom,
      rotation: transform.angle + vcam.dutch,
      z: transform.position.z,
      pitch: transform.eulerX,
      yaw: transform.eulerY,
      lens: vcam.lens,
    );
    // A manager's shot is whatever its children make it; its own stages —
    // a confiner, say — then apply whichever child is showing.
    if (managers.managerOf(camera) case (final manager, final component)) {
      state =
          manager.evaluateAny(
            CameraManagerContext(
              brain: this,
              world: world,
              entity: camera,
              memory: memory,
              children: _childrenOf(world, camera),
              dt: dt,
              snap: snap,
              stateOfChild: (child) => _stateOfChild(world, child, dt, snap),
            ),
            component,
          ) ??
          state;
    }
    for (final (stage, component) in stages.pipelineOf(camera)) {
      state = stage.applyAny(context, component, state, dt);
    }
    memory.initialized = true;
    return state;
  }

  /// The enabled child cameras of [manager], in hierarchy order.
  List<Entity> _childrenOf(World world, Entity manager) {
    final ids = manager.getComponent<ChildrenComponent>()?.childIds;
    if (ids == null || ids.isEmpty) return const [];
    return [
      for (final id in ids)
        if (world.getEntity(id) case final child?
            when child.isActive &&
                child.hasComponent<TransformComponent>() &&
                (child.getComponent<VirtualCameraComponent>()?.enabled ??
                    false))
          child,
    ];
  }

  CameraState? _stateOfChild(World world, Entity child, double dt, bool snap) {
    final vcam = child.getComponent<VirtualCameraComponent>();
    if (vcam == null) return null;
    final ranAt = _ranAt[child.id];
    if (ranAt == _frame) return _states[child.id];
    _ranAt[child.id] = _frame;
    final memory = _memory.putIfAbsent(child.id, CameraRigMemory.new);
    // A child that sat out a frame — its manager was on standby, or showed
    // another child — has stale damping, like a camera coming off standby:
    // it starts again from its target.
    if (ranAt != null && ranAt != _frame - 1) memory.reset();
    return _states[child.id] = _run(world, child, vcam, memory, dt, snap);
  }

  void _forgetAllBut(List<Entity> cameras, Set<EntityId> managed) {
    if (_memory.isEmpty && _states.isEmpty && _activation.isEmpty) return;
    final alive = {for (final camera in cameras) camera.id, ...managed};
    _ranAt.removeWhere((id, _) => !alive.contains(id));
    _memory.removeWhere((id, _) => !alive.contains(id));
    _states.removeWhere((id, _) => !alive.contains(id));
    _activation.removeWhere((id, _) => !alive.contains(id));
    if (soloEntity != null && !alive.contains(soloEntity)) soloEntity = null;
    // The live camera is kept even when it is gone: the next pick needs to
    // know what it is cutting away from.
  }
}
