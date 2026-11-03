# Rendering & layers

_Graphics_ · How the engine draws your world: the render system, draw order, self-drawing shapes, culling, render hooks and passes, parallax backgrounds and render stats.

Everything a 2D game shows is drawn by one ECS system, `RenderSystem`, inside the `GameWidget` that hosts your engine. You describe what to draw with components; the system sorts it and draws it through the camera once per display frame.

## What the rendering systems do

`EngineConfig(defaultSystems: DefaultSystems.all)` includes `DefaultSystem.rendering`, which adds two systems. Both draw through `engine.cameraSystem.mainCamera`.

| System | Priority | What it draws |
|---|---|---|
| `RenderSystem` | 40 | Every entity's `RenderableComponent`, every level-map layer and every particle emitter, in one sorted list |
| `ParallaxRenderSystem` | 105 | `ParallaxComponent` backgrounds, behind the world |

`DefaultSystems.headless` leaves both out, for servers and tests. Around them, `engine.rendering` (a `RenderingEngine`) owns the frame: the background colour (`backgroundColor`), render hooks, post-processing and frame stats.

Drawing happens once per display frame, between the fixed 60 Hz updates. Moving physics bodies, and their children, are drawn between their last two poses so they stay smooth on a 120 Hz screen; everything else is drawn where it is. See [The engine](/docs/engine) for the loop.

> **Note:** One entity draws one thing. Shapes and sprites are all stored as a `RenderableComponent`, and an entity holds one component of each type, so adding a second shape replaces the first. Put a second drawing on a child entity.

## Shapes that draw themselves

Five components draw themselves, centred on their entity's `TransformComponent`. Lines and polygons take points relative to it.

| Component | Size fields |
|---|---|
| `Rectangle2DComponent` | `width`, `height`, `cornerRadius` |
| `Circle2DComponent` | `radius` |
| `Capsule2DComponent` | `width`, `height`; round at both ends of the longer side |
| `Polygon2DComponent` | `vertices`, a list of `Offset`s closed back to the first |
| `Line2DComponent` | `start` (the entity's position by default), `end`, `roundCaps` |

Each has a `fillStyle` and a `strokeStyle` (a line has only the stroke), `filled`, and a `strokeWidth` in world units. By default a shape is filled white with a translucent white outline one unit wide. The outline is drawn whenever its style is not fully transparent, so pass `strokeStyle: const ShapePaintStyle(color: Colors.transparent)` to remove it.

A `ShapePaintStyle` is a `color` plus an optional `gradient`. With a gradient, the colour tints it through `blendMode` (`BlendMode.modulate` by default, so the default white leaves it as it is). `ShapeGradient.linear` runs from `begin` to `end`, `ShapeGradient.radial` spreads from `center` out to `radius` (a fraction of the shape's shorter side), and `ShapeGradient.sweep` turns round `center`. All three take `colors` and optional `stops`.

```dart lib/scenery.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

void addScenery(World world) {
  // Far behind everything: a gradient sky with no outline.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, -150, 0)),
    Rectangle2DComponent(
      width: 2400,
      height: 700,
      fillStyle: const ShapePaintStyle(
        gradient: ShapeGradient.linear(
          colors: [Color(0xFF14213D), Color(0xFF5B7DB1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      strokeStyle: const ShapePaintStyle(color: Colors.transparent),
    ),
    LayerComponent(layer: LevelLayers.background),
  ], name: 'Sky');

  // The main layer, drawn after main-layer entities with a lower zOrder.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 140, 0)),
    Capsule2DComponent(
      width: 32,
      height: 72,
      fillStyle: const ShapePaintStyle(
        gradient: ShapeGradient.radial(colors: [Colors.white, Colors.teal]),
      ),
    ),
    LayerComponent(zOrder: 10),
  ], name: 'Hero');

  // In front of everything: an outlined triangle.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(220, 120, 0)),
    Polygon2DComponent(
      vertices: const [Offset(0, -30), Offset(26, 15), Offset(-26, 15)],
      filled: false,
      strokeStyle: const ShapePaintStyle(color: Colors.amber),
      strokeWidth: 2,
    ),
    LayerComponent(layer: LevelLayers.foreground),
  ], name: 'Warning');
}

/// Shapes are stored as RenderableComponent: read them back by that type.
void highlight(Entity entity) {
  final shape = entity.getComponent<RenderableComponent>();
  if (shape is Rectangle2DComponent) shape.strokeWidth = 6;
  shape?.renderable.tint = Colors.yellow;
}
```

Every field is read when the shape draws, so change `width`, `radius` or a style at any time and the next frame shows it. To find a shape later, keep the component you created, or ask for `RenderableComponent` and check its type, as `highlight` does: `getComponent<Circle2DComponent>()` finds nothing. The renderable inside also has `opacity`, `tint` and `visible`, which effects such as `FadeEffect` animate (see [Particles, effects & post-processing](/docs/particles)).

## Draw order and layers

`RenderSystem` sorts by layer, then by `zOrder`; lower values draw first, further back. Entities with equal keys keep the order they were found in, so they never swap from one frame to the next. Give an entity a `LayerComponent` to place it:

- `layer`: the coarse order. `LevelLayers` holds the usual values: `background` (-200), `backgroundNear` (-100), `main` (0) and `foreground` (100).
- `zOrder`: the order within a layer.
- `layerId`: the name the editor's layer panel groups by (`main` by default). It does not change the order.
- `visible` and `locked`: used by the editor only; the game ignores them.
- `mapLayer`: on a child of a level map, draws the entity among that map layer's tiles. See [Level maps](/docs/level-maps).

An entity without a `LayerComponent` sorts by its renderable's own `layer` and `zOrder`, which are 0 for the built-in shapes. For a top-down game, set `ySort` on a renderable: it then draws after the rest of its layer and `zOrder`, ordered by world y, so whatever stands lower on screen is drawn in front.

## Batching and culling

Sprites batch on their own: consecutive sprites from one image, drawn at one uniform positive scale, go into a single `Canvas.drawRawAtlas` call. A mirrored or stretched sprite draws by itself, and a batch is flushed whenever the draw order key changes, so batching never changes the order.

`RenderSystem` has two more switches, both off by default. Set them on the default one, for example `engine.world.getSystem<RenderSystem>()?.batchShapes = true`:

- `batchShapes` draws runs of rectangles with square corners and circles in one `Canvas.drawVertices` call, when their fill and outline are plain colours and the entity is fully opaque, untinted and has no shader. Edges are not anti-aliased and a circle becomes a 16- or 24-sided polygon, so use it for many small shapes: bullets, debris, blockouts.
- `cullOffscreen` skips renderables whose bounds lie wholly outside the view. Level-map layers and particle emitters are always drawn, and it is only as good as each renderable's `getBounds`.

For large levels, `ViewCullingSystem` also stops simulating what is far away. Add it yourself with `world.addSystem(ViewCullingSystem(camera: engine.cameraSystem.mainCamera))`; only entities you give a `CullStateComponent` take part, so don't give one to the player. Outside the render area (1.2 times the view by default) an entity's renderable is hidden. Outside the active area (2 times the view) its `CullStateComponent.isActive` turns false and `MovementSystem` and `Physics2DSystem` skip it; check the same flag in your own systems, such as AI. A `hysteresisMargin` (24 units) stops entities on the edge from flickering.

## Drawing your own things

There are three ways in, depending on where the drawing belongs:

- In the world, sorted with everything else: put a `RenderableComponent(renderable: CustomRenderable(onRender: ...))` on an entity. `onRender` draws in the entity's own space, and `getBoundsCallback` gives the bounds that culling uses. `TextRenderable` draws a line of text the same way.
- On the screen: add a callback to `engine.rendering.overlayHooks` (over the world) or `backgroundHooks` (behind it). These `RenderHookChain`s run in screen space, outside the camera transform, in ascending `order`. `GameWidget` adds the world's own drawing at order 0 and the engine adds plugin overlays at 100. `remove` takes a hook out, and `addIfAbsent` never adds one twice.
- After the renderables, in world space: give `RenderSystem` extra `passes`. A `RenderPass` runs inside the camera transform, in ascending `order`. The default list is one `ComponentPainterPass` (order 100), which draws components whose definition has a painter, such as `just_ui_editor`'s world-space text; keep it in your own list.

The default `RenderSystem` is made during `initialize()`, so a game that wants custom passes leaves rendering out of the default set and adds its own:

```dart lib/axes.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Draws the world's x and y axes, inside the camera transform.
class AxesPass extends RenderPass {
  final Paint _paint = Paint()..color = const Color(0x55FFFFFF);

  // Before ComponentPainterPass, which runs at 100.
  @override
  int get order => 50;

  @override
  void render(Canvas canvas, RenderContext context, RenderPassFilter filter) {
    final view = context.camera?.getVisibleBounds();
    if (view == null) return;
    canvas
      ..drawLine(Offset(view.left, 0), Offset(view.right, 0), _paint)
      ..drawLine(Offset(0, view.top), Offset(0, view.bottom), _paint);
  }
}

Future<Engine> startWithAxes() async {
  final engine = Engine(
    config: EngineConfig(
      // Everything but rendering, which this game sets up itself.
      defaultSystems: DefaultSystems.all.difference({DefaultSystem.rendering}),
    ),
  );
  await engine.initialize();
  engine.world.addSystem(
    RenderSystem(
      camera: engine.cameraSystem.mainCamera,
      statsSink: engine.rendering,
      passes: [ComponentPainterPass(), AxesPass()],
    ),
  );
  // Adds ParallaxRenderSystem; the RenderSystem above is kept.
  registerDefaultSystems(
    engine.world,
    engine,
    include: {DefaultSystem.rendering},
  );

  // A crosshair in screen space, over the world (order 0).
  engine.rendering.overlayHooks.add((canvas, size) {
    final c = size.center(Offset.zero);
    final paint = Paint()..color = Colors.white;
    canvas
      ..drawLine(c - const Offset(8, 0), c + const Offset(8, 0), paint)
      ..drawLine(c - const Offset(0, 8), c + const Offset(0, 8), paint);
  }, order: 50);
  return engine;
}
```

## Parallax backgrounds

A `ParallaxComponent` holds a `ParallaxBackground`: a list of `ParallaxLayer`s from back to front. `ParallaxRenderSystem` scrolls it against the camera and draws it in screen space, behind the world. Several backgrounds are ordered by their entity's `LayerComponent`.

Each layer takes a decoded image. `scrollFactorX` and `scrollFactorY` say how far it moves with the camera, from 0 (fixed, like a sky) to 1 (with the world), 0.5 by default; `ParallaxLayer.uniform` takes one `scrollFactor` for both. `velocityX` and `velocityY` auto-scroll it in pixels per second, for drifting clouds, and it also takes a `scale`, `offset`, `opacity`, `tint`, and `repeat` (tile to fill the view, on by default). Parallax backgrounds are not saved in scenes, so add them in code:

```dart
import 'package:just_game_engine/just_game_engine.dart';

Future<void> addBackground(Engine engine) async {
  final assets = engine.assets;
  final sky = (await assets.loadImage('assets/backgrounds/sky.png')).image!;
  final hills = (await assets.loadImage('assets/backgrounds/hills.png')).image!;
  engine.world.createEntityWithComponents([
    ParallaxComponent(
      background: ParallaxBackground(
        layers: [
          ParallaxLayer(image: sky, scrollFactorX: 0, scrollFactorY: 0),
          ParallaxLayer(image: hills, scrollFactorX: 0.3, scrollFactorY: 0.1),
        ],
      ),
    ),
  ], name: 'Background');
}
```

## Render stats

- `engine.rendering.stats` describes the whole last frame: `lastRenderMs`, `drawCalls`, `renderedObjects`, `culledObjects`, `batchedSprites` and `postProcessPasses`. The default `RenderSystem` reports into it; one you make yourself counts only if you pass `statsSink: engine.rendering`.
- `engine.world.getSystem<RenderSystem>()?.stats` holds `drawCalls`, `renderedObjects`, `culledObjects` and `batchedSprites` for the world alone, without the extra passes' drawing. In tests, `RenderSystem.debugDrawOrder()` lists the draw order.
- [Debugging](/docs/debugging) covers the on-screen tools.

## The deprecated legacy path

Adding renderables to the rendering engine directly, as 1.x games did, still works in 2.0 but is deprecated and will be removed in 3.0:

| Deprecated | Use instead |
|---|---|
| `engine.rendering.addRenderable`, `removeRenderable`, `useSpatialIndex` and the other spatial-index members | An entity with a `RenderableComponent`; `cullOffscreen` for culling |
| `engine.parallax`, `ParallaxSystem` | `ParallaxComponent` and `ParallaxRenderSystem` |
| `onRenderOverlay`, `onRenderBackground` | `overlayHooks`, `backgroundHooks` |

> **Warning:** `RenderSystem` now draws particle emitters itself, and `GameWidget` always draws the world. Remove any `engine.world.render` call from your own overlay hook, or the world draws twice. The managed emitters (`addManagedEmitter` and the rest) are gone: an emitter goes on an entity, with `ParticleEmitterComponent` and `ParticleSystem`.
