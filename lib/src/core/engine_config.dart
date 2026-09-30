/// How an [Engine] is built.
library;

import '../subsystems/rendering/rendering_engine.dart';

/// Choices made once, when an [Engine] initializes.
///
/// ```dart
/// await Engine().initialize(
///   config: EngineConfig(createRendering: MyRenderingEngine.new),
/// );
/// ```
class EngineConfig {
  const EngineConfig({this.createRendering});

  /// Makes the rendering engine — a subclass of [RenderingEngine] that draws
  /// some other way, say. Null makes the standard one. To draw the world
  /// with another backend *alongside* the canvas, add a `SceneRenderer`
  /// instead.
  final RenderingEngine Function()? createRendering;
}
