/// The pipeline a virtual camera's state runs through each frame.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset, Size;

import '../../ecs/components/camera/virtual_camera_component.dart';
import '../../ecs/ecs.dart';
import 'camera_brain.dart';
import 'camera_state.dart';

/// Where in the pipeline a stage runs. Within a phase, by [CameraStage.order].
enum CameraStagePhase {
  /// Where the camera *is*: framing a target, riding a path.
  body,

  /// Which way it points — in 2D, its roll.
  aim,

  /// What is laid over the settled shot: handheld noise, impulses.
  noise,

  /// Corrections that must have the last word: confining to the level.
  finalize,
}

/// What one virtual camera remembers between frames.
///
/// Damping is a relationship between this frame and the last, so a stage
/// needs somewhere to keep "the last". Owned by the brain, one per camera,
/// dropped when the camera goes away.
class CameraRigMemory {
  /// False until the camera has produced a state; a stage treats that as
  /// "snap", so a camera's first frame is already on its target.
  bool initialized = false;

  /// The damped camera position the body stage left off at.
  Offset position = Offset.zero;

  /// The smoothed target velocity lookahead uses.
  Offset lookaheadVelocity = Offset.zero;

  /// Where the target was last frame, for a target with no velocity of its
  /// own to read.
  Offset? previousTargetPosition;

  /// Seconds of noise played, so a shot's shake does not restart each frame.
  double noiseTime = 0;

  /// The last state the pipeline produced.
  CameraState? lastState;

  /// Anything else a stage needs to remember, keyed by the stage.
  final Map<Object, Object?> extra = {};

  void reset() {
    initialized = false;
    lookaheadVelocity = Offset.zero;
    previousTargetPosition = null;
    noiseTime = 0;
    lastState = null;
    extra.clear();
  }
}

/// Everything a stage may look at while shaping one camera's state.
class CameraStageContext {
  CameraStageContext({
    required this.brain,
    required this.world,
    required this.entity,
    required this.vcam,
    required this.memory,
    required this.viewportSize,
    required this.snap,
    this.target,
    this.targetPosition,
    this.targetVelocity = Offset.zero,
  });

  final CameraBrain brain;
  final World world;

  /// The virtual camera's entity.
  final Entity entity;
  final VirtualCameraComponent vcam;
  final CameraRigMemory memory;

  /// The output's size in pixels; zero before the first frame is laid out.
  final Size viewportSize;

  /// True when damping must be skipped: the camera's first frame, a camera
  /// that just went live from standby, or the editor evaluating a frozen
  /// game.
  final bool snap;

  /// The entity being followed, if it exists right now.
  final Entity? target;
  final Offset? targetPosition;
  final Offset targetVelocity;

  /// The part of the world in view at [zoom], in world units.
  Size viewAt(double zoom) => zoom <= 0 || viewportSize.isEmpty
      ? Size.zero
      : Size(viewportSize.width / zoom, viewportSize.height / zoom);
}

/// One step of a virtual camera's pipeline, driven by one component type.
///
/// Put a `T` on a virtual camera's entity and this stage runs for it. That
/// is the whole extension story: a kit that wants a camera behaviour of its
/// own writes a component and a stage, registers the stage with
/// [CameraBrain.stages], and the inspector, the picker and the save format
/// already know what to do with the component.
abstract class CameraStage<T extends Component> {
  const CameraStage();

  CameraStagePhase get phase;

  /// Order within [phase]; lower runs first.
  int get order => 0;

  /// The component type this stage runs for.
  Type get componentType => T;

  /// [state] as this stage leaves it.
  CameraState apply(
    CameraStageContext context,
    T component,
    CameraState state,
    double dt,
  );

  /// [apply] for a component typed only as [Component].
  CameraState applyAny(
    CameraStageContext context,
    Component component,
    CameraState state,
    double dt,
  ) => apply(context, component as T, state, dt);

  /// How much of a gap to close this frame so that 99% of it is gone after
  /// [dampTime] seconds — the same at 30 and 144 frames a second.
  static double damp(double dampTime, double dt) {
    if (dampTime <= 0 || dt <= 0) return dampTime <= 0 ? 1 : 0;
    return 1 - math.exp(-_ln100 / dampTime * dt);
  }

  static final double _ln100 = math.log(100);
}

/// Which stage runs for which component.
class CameraStageRegistry {
  final Map<Type, CameraStage> _stages = {};

  /// Registers [stage] for its component type. A second stage for the same
  /// type is refused unless [override] is set — replacing a built-in should
  /// be something a project says out loud.
  void register(CameraStage stage, {bool override = false}) {
    if (!override && _stages.containsKey(stage.componentType)) {
      throw StateError(
        'A camera stage for ${stage.componentType} is already registered',
      );
    }
    _stages[stage.componentType] = stage;
  }

  void registerAll(Iterable<CameraStage> stages, {bool override = false}) {
    for (final stage in stages) {
      register(stage, override: override);
    }
  }

  void unregister(Type componentType) => _stages.remove(componentType);

  CameraStage? stageFor(Component component) => _stages[component.runtimeType];

  /// The stages [entity] carries, with their components, in pipeline order.
  List<(CameraStage, Component)> pipelineOf(Entity entity) {
    final steps = <(CameraStage, Component)>[
      for (final component in entity.components)
        if (_stages[component.runtimeType] case final stage?)
          (stage, component),
    ];
    steps.sort((a, b) {
      final byPhase = a.$1.phase.index.compareTo(b.$1.phase.index);
      return byPhase != 0 ? byPhase : a.$1.order.compareTo(b.$1.order);
    });
    return steps;
  }
}
