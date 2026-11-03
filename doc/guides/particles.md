# Particles, effects & post-processing

_Graphics_ · Particle emitters and presets, deterministic tick-based effects that replay and serialize, and fragment-shader passes over the frame.

Three tools for things that burst, move and glow: particle emitters, tick-based effects that play the same on every machine, and fragment-shader passes over the frame.

## Particle emitters

A `ParticleEmitterComponent` puts a `ParticleEmitter` on an entity. `ParticleSystemECS` (priority 48) updates every emitter, keeps it at its entity (`syncPositionFromTransform`, on by default) and, with `removeEntityWhenComplete`, destroys the entity once the emitter has finished. `RenderSystem` draws emitters in layer order, like any renderable.

`ParticleSystemECS` is not a default system, so add it once. Emitters are not saved in scenes either: add them in code.

`ParticleEffects` has ready-made emitters, each taking the `position` to start at: `explosion`, `fire`, `smoke`, `sparkle`, `rain`, `snow`, `portal`, `magic`, `bloodSplatter`, `dustKick`, `electricSparks`, `waterSplash`, `healAura`, `confetti` and `lavaEmbers`. Some take more, such as `explosion`'s `particleCount` and `color`.

```dart lib/fx.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A one-shot explosion; the entity goes when its last particle does.
void explode(World world, Vector3 at) {
  if (!world.hasSystem<ParticleSystemECS>()) {
    world.addSystem(ParticleSystemECS());
  }
  world.createEntityWithComponents([
    TransformComponent(position: at),
    ParticleEmitterComponent(
      emitter: ParticleEffects.explosion(position: at, color: Colors.amber),
      removeEntityWhenComplete: true,
    ),
  ], name: 'Explosion');
}

/// A flame on a wall torch, drawn in front of the level.
Entity addFlame(World world, Entity torch) => world.createEntityWithComponents([
  TransformComponent(),
  ParentComponent(parentId: torch.id, localPosition: Vector3(0, -40, 0)),
  ParticleEmitterComponent(
    emitter: ParticleEmitter(
      maxParticles: 120,
      emissionRate: 60,
      particleLifetime: 0.8,
      startSize: 10,
      endSize: 2,
      startColor: Colors.orange,
      endColor: Colors.red.withValues(alpha: 0),
      emissionAngle: -math.pi / 2, // up is -Y
      emissionSpread: 0.4,
      speed: 90,
      renderer: SquareParticleRenderer(),
      forces: [
        const GravityForce(Offset(0, -60)),
        WindForce(strength: 20, turbulence: 30),
        const DragForce(coefficient: 0.1),
      ],
    ),
  ),
  LayerComponent(layer: LevelLayers.foreground),
], name: 'Flame');
```

To build your own, a `ParticleEmitter` takes `maxParticles` and:

- Emission: `emissionRate` (particles per second), `duration` (seconds before it stops; null for ever), `emissionAngle` (radians from +X, so up is `-math.pi / 2`), `emissionSpread` (`math.pi * 2` emits every way), `speed` and `speedVariation`.
- Each particle: `particleLifetime`, `startSize` and `endSize`, `startColor` and `endColor`, and `angularVelocity`, with `lifetimeVariation`, `sizeVariation` and `angularVelocityVariation` for randomness.
- `renderer`: `CircleParticleRenderer` by default, or `SquareParticleRenderer`, `TriangleParticleRenderer`, `StarParticleRenderer`, `LineParticleRenderer`, `SpriteParticleRenderer`, `AnimatedSpriteParticleRenderer`, `TextParticleRenderer` or `CustomPathParticleRenderer`.
- `forces`: `GravityForce`, `WindForce`, `DragForce`, `VortexForce`, `AttractorForce`, `RepellerForce`, `NoiseForce` and `BoundaryForce`, or your own `ParticleForce`, whose `advance` runs once per update and `apply` once per particle.
- `subEmitters`: `SubEmitterConfig`s that start another emitter where a particle dies (`SubEmitterTrigger.onDeath`) or at a fraction of its life (`onLifetimeFraction`), with at most `maxInstances` alive at once.

While it runs, `burst(count)` emits at once, setting `isEmitting` to false stops new particles, `addForce` and `removeForce` change the forces, and `reset()` clears it. `isComplete` and `particleCount` say where it is.

## Deterministic effects

Effects are small animations on an entity. They count fixed steps (ticks, 60 a second) rather than seconds, so they play exactly the same on every machine and can be sent over a network. `EffectSystemECS` (priority 65) advances them one tick per update; it is not a default system, so add it once.

`scheduleEffect(entity: ..., effect: ...)` starts an effect on the next tick, or at `startTick`, and returns an `EffectHandle`. Pass that to `cancelEffect(entity, handle)` to stop the effect early.

| Effect | What it does |
|---|---|
| `MoveEffect(to: ...)` | Moves to `to`; with `from`, moves by `to` minus `from` from wherever the entity is |
| `ScaleEffect(to: ...)` | Scales uniformly |
| `RotateEffect(to: ...)` | Turns `angle`, in radians |
| `FadeEffect(to: ...)` | Fades the opacity of the entity's `RenderableComponent`, 0 to 1 |
| `ColorTintEffect(to: ...)` | Tints the entity's `RenderableComponent` |
| `ShakeEffect(amplitude: ...)` | Shakes and ends where it started; `frequency`, `xOnly` |
| `PathEffect(waypoints: ...)` | Moves through `Offset` waypoints; `cubicBezier: true` with exactly four |
| `SequenceEffect(children: ...)` | Plays its children one after another |
| `ParallelEffect(children: ...)` | Plays its children together |
| `DelayEffect()` | Waits |
| `RepeatEffect(child: ..., times: ...)` | Repeats a child; `times: 0` repeats for ever |

The single effects take `durationTicks` (30 by default, 60 for `PathEffect`) and `onComplete`; all but `DelayEffect` also take `loop`, and the tweening ones an `easing` (an `EasingType`, linear by default). Transform effects add their change each tick, so two `MoveEffect`s on one entity add up; a colour tint sets the colour, so the last one wins.

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

EffectSystemECS effectsOf(World world) {
  var effects = world.getSystem<EffectSystemECS>();
  if (effects == null) {
    effects = EffectSystemECS();
    world.addSystem(effects);
  }
  return effects;
}

/// A hit: a short shake, then a fade out.
EffectHandle hit(World world, Entity enemy) => effectsOf(world).scheduleEffect(
  entity: enemy,
  effect: SequenceEffect(
    children: [
      ShakeEffect(amplitude: 6, durationTicks: 12),
      FadeEffect(to: 0, durationTicks: 30, easing: EasingType.easeInQuad),
    ],
  ),
);

/// A collected coin pops up, grows and turns gold, all at once.
void collect(World world, Entity coin) {
  effectsOf(world).scheduleEffect(
    entity: coin,
    effect: ParallelEffect(
      children: [
        MoveEffect(
          from: Vector3.zero(),
          to: Vector3(0, -40, 0), // up 40, from wherever it is
          durationTicks: 20,
          easing: EasingType.easeOutCubic,
        ),
        ScaleEffect(to: 1.5, durationTicks: 20),
        ColorTintEffect(to: Colors.amber, durationTicks: 10),
      ],
    ),
  );
}
```

To keep effects in step across machines, schedule them at the same `startTick` (`currentTick` says where the system is). For rollback, `snapshotState()` and `restoreSnapshot(snapshot, world)` save and restore every running effect, and `snapshotToBytes()` and `restoreFromBytes(bytes, world)` do the same in a compact binary form. `EffectSerializer` turns one effect into JSON and back (`encodeEffect`, `decodeEffect`); register effect types of your own with `engine.context.effectTypes.register`.

## Post-processing

Fragment shaders can draw over the whole frame or over one entity. Declare each shader under `flutter: shaders:` in `pubspec.yaml` and load it with `ui.FragmentProgram.fromAsset`.

A `ShaderComponent(program: ...)` draws its own entity through the shader, in a layer clipped to the entity's bounds. With `isPostProcess: true` it becomes a full-screen pass instead: add a `PostProcessSystem` once (it is not a default system), and it keeps a `PostProcessPass` on `engine.rendering` for each such component. Passes run in ascending `passOrder`, the lowest applied first, closest to the raw scene, and `enabled` switches one off without removing it. You can also skip the components and call `engine.rendering.addPostProcessPass(PostProcessPass(shader: ...))` yourself, and `removePostProcessPass` later.

The scene arrives in the shader's sampler, bound for you. Your `setUniforms` callback writes the float uniforms each frame, in the order they are declared:

```text shaders/vignette.frag
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uTime;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uResolution;
  vec4 color = texture(uTexture, uv);
  float edge = 0.75 + 0.05 * sin(uTime);
  float shade = 1.0 - smoothstep(0.35, edge, distance(uv, vec2(0.5)));
  fragColor = vec4(color.rgb * shade, color.a);
}
```

```dart
import 'dart:ui' as ui;

import 'package:just_game_engine/just_game_engine.dart';

Future<void> addVignette(Engine engine) async {
  final world = engine.world;
  if (!world.hasSystem<PostProcessSystem>()) {
    world.addSystem(
      PostProcessSystem(engine.rendering, getTime: () => engine.time.totalTime),
    );
  }
  final program = await ui.FragmentProgram.fromAsset('shaders/vignette.frag');
  world.createEntityWithComponents([
    ShaderComponent(
      program: program,
      isPostProcess: true,
      setUniforms: (shader, width, height, time) {
        shader
          ..setFloat(0, width) // uResolution.x
          ..setFloat(1, height) // uResolution.y
          ..setFloat(2, time); // uTime
      },
    ),
  ], name: 'Vignette');
}
```

> **Warning:** Shader effects need Impeller. On the web, and on platforms still drawing with Skia, the engine skips them: the content draws unshaded and one line is logged per kind of effect. This applies to `ShaderComponent`, post-process passes and an emitter's `shader` alike. `ShaderFilterSupport.isSupported` tells you in advance.
