# Sprites & animation

_Graphics_ · Show images and atlas regions, play clips from TexturePacker and Aseprite atlases, and let animator graphs pick the clip for you.

Three components put 2D art on screen. `SpriteComponent` shows a still image or one region of an atlas. `SpriteAnimationComponent` plays clips from an atlas. `AnimatorComponent` runs an animator graph: a state machine that picks the clip from the entity's own state, so your game needs no animation code.

The systems behind them come with `DefaultSystem.sprites` (`SpriteLoadSystem` and `SpriteAnimationSystem`) and `DefaultSystem.animation` (`AnimatorSystem`), or add them to any world with `registerSpriteSystems(world)`, which adds the animator and the timeline systems too. Images, atlases and graphs are read through the asset bundle, so list their folders under `flutter: assets:` in `pubspec.yaml` (see [Assets](/docs/assets)).

## Showing an image

`SpriteComponent(spritePath: ...)` shows a whole image, centred on its entity. To show one frame of an atlas instead, set `atlasPath` and `region`; an empty `region` shows the atlas's first. It also takes `flipX`, `flipY` and a `tint`, and `pixelArt: true` samples without smoothing so scaled pixels stay square. That is off by default for `SpriteComponent` and on for `SpriteAnimationComponent`.

Sprites are renderables: order them with a `LayerComponent` like shapes (see [Rendering & layers](/docs/rendering)), and fade or tint them with effects.

## Atlases

An atlas is the JSON a sprite tool exports beside its sheet. The engine recognises the format from the file itself (`AtlasParser.detect`), so you never name it:

| Format | Recognised by | Clips |
|---|---|---|
| Aseprite JSON, hash or array | `meta.app` contains `aseprite` | One per `frameTags` entry |
| TexturePacker JSON array or hash | `frames` is a list or an object | None in the file; register them in code |
| TexturePacker multi-page | A top-level `textures` list | None in the file |
| The engine's grid sheet (tried first) | `meta.frameWidth` and `meta.frameHeight`, and no `frames` | One per `clips` entry; each cell is a region named by its index |

The image path inside the JSON is relative to the JSON file. Aseprite tags play `forward`, `reverse` or `pingpong`, each frame for its own `duration` (milliseconds in the file, seconds in the engine), and loop by default. Trimmed and rotated frames are drawn where and how they belong.

To work with an atlas in code, load it with `SpriteAtlas.fromAsset(path, assets: engine.assets)`. The asset manager caches it, so you get the same atlas the sprite systems use. It lists `regionNames` and `clipNames`, finds them with `getRegion` and `getClip`, and takes extra clips with `registerClip`: an `AtlasAnimationClip` of `AtlasFrame`s, with durations in seconds.

## Playing clips

`SpriteAnimationComponent(atlasPath: ..., clip: 'run')` plays one clip at its authored timing. An empty `clip`, or a name the atlas lacks, plays every region in order, a tenth of a second each.

- `speed`: 1 is as authored, 0 holds the frame, and a negative speed plays backwards.
- `play()`, `pause()`, `stop()` (back to the first frame) and `restart()` control it; `playOnStart: false` waits for `play()`.
- `switchClip('idle')` changes clip and starts it from its first frame. Asking for the clip already playing does nothing unless you pass `restartIfSame: true`, and `loop:` overrides the clip's own looping.
- `isPlaying`, `frameIndex` and `isComplete` say where it is.

`SpriteAnimationSystem.signals` streams `SpriteAnimationSignal`s: the frame events an atlas carries (in its `meta.just` block), and `SpriteAnimationSignal.completed` when a clip that does not loop ends.

## Animator graphs

An `.animator.json` file holds parameters, states and transitions. Put an `AnimatorComponent(graphPath: ...)` beside a `SpriteAnimationComponent` and the graph decides which clip plays. `faceVelocity: true` also flips the sprite to face the way the entity moves, keeping the last direction while it stands still.

```dart lib/hero.dart
import 'package:just_game_engine/just_game_engine.dart';

void addSprites(Engine engine) {
  // `grounded` is not a built-in binding, so teach it to this engine.
  engine.context.animatorBindings.register(
    'grounded',
    (entity) => entity.getComponent<RigidBody2DComponent>()?.isGrounded,
  );

  final world = engine.world;

  // A whole image.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-200, 150, 0)),
    SpriteComponent(spritePath: 'assets/sprites/crate.png'),
  ], name: 'Crate');

  // One region of an atlas: the frame called "hero 0".
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-100, 150, 0)),
    SpriteComponent(
      spritePath: '',
      atlasPath: 'assets/sprites/hero.json',
      region: 'hero 0',
      pixelArt: true,
    ),
  ], name: 'Statue');

  // Animated: the graph picks the clip.
  world.createEntityWithComponents([
    TransformComponent(),
    VelocityComponent(),
    SpriteAnimationComponent(atlasPath: 'assets/sprites/hero.json'),
    AnimatorComponent(
      graphPath: 'assets/sprites/hero.animator.json',
      faceVelocity: true,
    ),
    RigidBody2DComponent(friction: 0, lockRotation: true),
    Collider2DComponent(size: Vector2(28, 32)),
    LayerComponent(zOrder: 10),
  ], name: 'Hero');
}
```

The graph for that hero, assuming its atlas has `idle`, `walk`, `run`, `jump`, `fall` and `attack` tags:

```json assets/sprites/hero.animator.json
{
  "version": 2,
  "atlas": "assets/sprites/hero.json",
  "entry": "idle",
  "parameters": [
    { "name": "speed", "type": "float", "binding": "speedX" },
    { "name": "vy", "type": "float", "binding": "velocityY" },
    { "name": "grounded", "type": "bool", "binding": "grounded" },
    { "name": "attack", "type": "trigger" }
  ],
  "states": [
    { "name": "idle" },
    {
      "name": "move",
      "blend": {
        "type": "1d",
        "parameter": "speed",
        "motions": [
          { "clip": "walk", "threshold": 60 },
          { "clip": "run", "threshold": 240 }
        ]
      }
    },
    { "name": "jump" },
    { "name": "fall" },
    { "name": "attack", "loop": false }
  ],
  "transitions": [
    { "from": "idle", "to": "move", "conditions": [{ "param": "speed", "op": ">", "value": 20 }] },
    { "from": "move", "to": "idle", "conditions": [{ "param": "speed", "op": "<=", "value": 20 }] },
    {
      "from": "*",
      "to": "jump",
      "conditions": [
        { "param": "grounded", "op": "==", "value": false },
        { "param": "vy", "op": "<", "value": 0 }
      ]
    },
    { "from": "jump", "to": "fall", "conditions": [{ "param": "vy", "op": ">=", "value": 0 }] },
    { "from": "fall", "to": "idle", "conditions": [{ "param": "grounded", "op": "==", "value": true }] },
    { "from": "*", "to": "attack", "priority": 1, "conditions": [{ "param": "attack" }] },
    { "from": "attack", "to": "idle", "hasExitTime": true, "exitTime": 1.0 }
  ]
}
```

How it reads:

- Parameters are `float` (the default), `int`, `bool` or `trigger`, with an optional `default`. A `binding` fills one from the entity every frame. The built-in bindings are `velocityX`, `velocityY`, `speed`, `speedX`, `speedY`, `health`, `healthFraction` and `alive`; register more with `engine.context.animatorBindings.register`. A binding nobody registered silently leaves its parameter at the default.
- A state plays the clip of its own name unless it sets `clip`. It can also set `speed`, `loop`, and `timeline`: a `.timeline.json` the entity's `TimelinePlayerComponent` plays from the start on entering the state (see [Timelines](/docs/timelines)).
- A transition fires when all its `conditions` hold. A condition compares a `param` with a `value` by `op` (`>`, `>=`, `<`, `<=`, `==` or `!=`). A trigger condition holds while the trigger is set, and the transition that takes it switches it off again. `"from": "*"` leaves any state, and `hasExitTime` with an `exitTime` from 0 to 1 waits until the clip has played that far.
- Transitions from any state are tried first, then the current state's own, highest `priority` first.
- Set parameters that have no binding from your code with `setFloat`, `setInt`, `setBool`, `setTrigger` and `resetTrigger` on the `AnimatorComponent`. `currentState` and `stateTime` say where it is, and `AnimatorSystem.stateChanges` streams every change.

## Blend trees and crossfades

A state with a `blend` object plays several clips weighted by parameters instead of one: a `"1d"` tree places `motions` at a `threshold` along one `parameter`, and a `"2d"` tree places them at `x` and `y` over `parameter` and `parameterY`. A transition's `duration` crossfades between states. A file that uses either is saved as `"version": 2`.

A sprite can't blend two frames, so on a sprite a blend tree plays its heaviest motion (in the graph above, `walk` up to a speed of 150 and `run` beyond it) and transitions always cut. On a 3D model with an `AnimationPlayerComponent`, blend trees and crossfades really blend; see [3D graphics](/docs/graphics-3d).

## Clips and events in code

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

/// The graph's attack state takes it from here.
void attack(Entity hero) =>
    hero.getComponent<AnimatorComponent>()?.setTrigger('attack');

Future<void> watchAnimation(Engine engine) async {
  // The atlas the sprite systems use: the asset manager caches it.
  final atlas = await SpriteAtlas.fromAsset(
    'assets/sprites/hero.json',
    assets: engine.assets,
  );
  debugPrint('clips: ${atlas.clipNames.join(', ')}');

  // A clip the file does not have, made from its regions.
  atlas.registerClip(
    const AtlasAnimationClip(
      name: 'taunt',
      frames: [
        AtlasFrame(regionName: 'hero 0', duration: 0.2),
        AtlasFrame(regionName: 'hero 4', duration: 0.4),
      ],
      loop: false,
    ),
  );

  final world = engine.world;
  world.getSystem<AnimatorSystem>()?.stateChanges.listen((change) {
    debugPrint('${change.entity.name}: ${change.from} -> ${change.to}');
  });
  world.getSystem<SpriteAnimationSystem>()?.signals.listen((signal) {
    if (signal.name == SpriteAnimationSignal.completed) {
      debugPrint('${signal.entity.name} finished ${signal.clip}');
    }
  });
}
```

## Batching many sprites

`RenderSystem` already batches sprites for you (see [Rendering & layers](/docs/rendering)). When you draw many sprites yourself, for example from a `CustomRenderable`, use a `SpriteBatch`. Make one for an image, `add` each sprite with its `sourceRect` and `position` (and optionally `rotation`, `scale` and a `color`), then `flush(canvas)` draws them all in one `Canvas.drawRawAtlas` call and empties the batch. Its `filterQuality` is `FilterQuality.none` by default, which keeps pixel art crisp.

## Easing

An `EasingFunction` is `double Function(double t)`: progress from 0 to 1 in, eased progress out. The engine's curves are static functions on `Easings`: `linear`; the `easeIn`, `easeOut` and `easeInOut` versions of `Quad`, `Cubic`, `Quart`, `Sine` and `Expo`; and `easeInElastic`, `easeOutElastic`, `easeInBounce` and `easeOutBounce`.

The same curves are named in two other places:

- Effects take an `EasingType`, such as `EasingType.easeOutCubic`, and `type.transform(t)` evaluates one. It names every curve except the quartic ones and `easeInOutExpo`.
- Timeline keys name a curve in `"e"`, looked up in `engine.context.easings`: the `EasingType` names except `easeInSine` and `easeOutSine`. Add your own with `engine.context.easings.register('name', curve)`.

Coming from 1.x: the top-level `easeInQuad` and friends are now `Easings.easeInQuad`, and `typedef Easing` is now `EasingFunction`.
