/// Animation
///
/// The animator graph: the state machine that picks which clip an entity's
/// sprite animation plays. Clips play through the ECS
/// (`SpriteAnimationComponent`), and any field animates with a timeline.
library;

export 'animator/animator_graph.dart';
