/// Animation
///
/// The animator graph: the state machine that picks which clip an entity's
/// sprite animation plays. Clips play through the ECS
/// (`SpriteAnimationComponent`), and any field animates with a timeline.
library;

export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show
        AnimatorParameterType,
        AnimatorParameter,
        AnimatorOp,
        AnimatorCondition,
        AnimatorState,
        AnimatorTransition,
        AnimatorGraph,
        AnimatorBlendType,
        AnimatorBlendMotion,
        AnimatorBlendTree;
export 'animator_component.dart';
export 'animation_targets.dart';
export 'animator_bindings.dart';
export 'animator_system.dart';
export 'animation_context.dart' show ContextAnimation, AnimatorGraphLoader;
export 'animation_definitions.dart';
