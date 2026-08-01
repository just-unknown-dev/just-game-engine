# Animation Blend Tree

Unity-Animator-style parametric blending between sprite-sheet animation
clips, plus crossfaded state transitions, for `just_game_engine`. This
document explains the problem, the algorithm, the public API, and how it
integrates with the engine's ECS.

## 1. Overview & motivation

Before this feature, every animated character in the engine (and in the
`dying_breath` game that consumes it) switched between sprite-sheet clips
with a **hard cut**: `elapsed`/`frameIndex` reset to zero, the new clip's
first frame appears instantly. `dying_breath`'s `PlayerAnimationSystem` and
`ZombieAnimationSystem` also **hard-snap** 8-directional facing via an
`atan2` → octant `floor` — crossing an octant boundary pops the sprite to a
different drawn angle with no interpolation. Every walk↔run speed
threshold and every strafe/backward direction change pops instantly.

The engine already had three unrelated animation subsystems (a tween/easing
`Animation` hierarchy, a simple frame-cycling `AnimationStateComponent`, and
a partially-built cross-fade scaffold on `AnimatedSpriteComponent` whose
only consumer lives in the separate `just_game_engine_editor` package and
only blends transform keyframes, never sprite pixels) — **none of them
blend sprite frames**. This feature adds that capability as a new,
purpose-built system, without touching any of the three existing ones.

Two problems have to be solved that don't exist for *skeletal* animation
(which is what Unity's blend trees actually blend — bone transforms
interpolate naturally):

1. **Raster sprite frames don't interpolate.** There's no "halfway between
   frame 3 and frame 7" pixel buffer to sample the way there's a "halfway
   rotation" between two bone transforms. Blending has to happen by
   compositing whole frames with transparency, not by interpolating pixel
   data.
2. **Clips of different lengths need to stay in lockstep.** An 8-frame idle
   and a 14-frame run blended together will visibly misalign/pop unless
   something keeps them phase-synchronized.

Sections 3–6 below cover how each is solved. Section 9 covers where facing
direction — deliberately — stays a hard snap.

## 2. Core concepts glossary

| Concept | Type | Meaning |
|---|---|---|
| Clip | `BlendClip` | Playback metadata for one named animation: fps, frame count, and where its pixels come from ([§10](#10-clipimage-loading-strategies)). |
| Motion | `BlendMotion` (sealed) | What a state plays: a single clip (`ClipMotion`), or a parametric blend over several clips (`BlendTree1DMotion`, `BlendTree2DMotion`). |
| State | `BlendState` | A named node in a state machine: a `BlendMotion` plus whether it loops. |
| Transition | `BlendTransition` | An optional crossfade-duration override for a specific (or any) state pair. |
| State machine | `BlendStateMachine` | A named set of states, reachable from any other via `play()`, crossfaded over a duration. |
| Component | `AnimationBlendTreeComponent` | Attaches a `BlendStateMachine` (+ clips + live parameters) to an entity. |
| System | `AnimationBlendTreeSystem` | Advances phases/transitions every tick and writes weighted frames into the entity's `BlendSprite`. |
| Renderable | `BlendSprite` | Composite `Renderable` that draws several weighted sprite-sheet frames as one visually-blended sprite. |

## 3. Algorithm 1 — 1D blending

`BlendSpace1D` (`lib/src/subsystems/animation/blend/blend_space_1d.dart`)
implements Unity's "Simple 1D" blend: given ascending thresholds and a
scalar parameter (e.g. speed), find the two thresholds bracketing the
parameter and interpolate linearly between them; clamp to the nearest end
outside the range.

```text
parameter <= thresholds[0]        -> weight 1.0 on thresholds[0]
parameter >= thresholds[last]     -> weight 1.0 on thresholds[last]
thresholds[i] <= parameter <= thresholds[i+1]
                                   -> t = (parameter - thresholds[i]) / (thresholds[i+1] - thresholds[i])
                                      weights[i] = 1-t, weights[i+1] = t
```

This is straightforward and needs no further justification — the
interesting algorithmic work is in 2D.

## 4. Algorithm 2 — Gradient Band Interpolation (2D)

`BlendSpace2D` (`blend_space_2d.dart`) implements the weighting algorithm
behind Unity's Freeform Directional/Cartesian 2D blend trees, originally
described by Rune Skovbo Johansen as "Gradient Band Interpolation."
Adapted here for sprite-sheet frame blending rather than skeletal pose
blending.

For every sample point `i`, and every *other* sample point `j`, project the
query onto the line from `i` toward `j` and take a linear falloff that is
1.0 at `i` and 0.0 at `j`:

```text
t_ij    = dot(query - p_i, p_j - p_i) / dot(p_j - p_i, p_j - p_i)
band_ij = 1 - t_ij
```

`i`'s raw weight is the *most restrictive* (minimum) band across all its
neighbors, clamped at 0:

```text
weight_i = max(0, min over all j != i of band_ij)
```

Summing every point's raw weight and dividing each by that sum yields the
final weights (falling back to "nearest sample = 1.0" if the sum is ~0 —
every sample coincided with every other one).

### Why the minimum-band rule works

Intuitively: point `i` only gets full weight in the region where it is
closer, along every possible direction to a neighbor, than that neighbor
is. Each neighbor `j` "vetoes" `i`'s weight linearly as the query
approaches `j`; the *most* restrictive veto wins.

### Proven property: exact identity at a sample's own point

Querying exactly at `p_i` always yields weight 1 for `i` and 0 for every
other point — and this holds for **any** layout of distinct points, not
just symmetric ones. Proof: at `query = p_i`, for any other point `k`,
using neighbor `i` specifically in `k`'s min: `iq_k = p_i - p_k` and
`ij_{k,i} = p_i - p_k` are the *same* vector, so `t = 1` and `band_{k,i} =
0`. Since `k`'s weight is the minimum band across *all* its neighbors, and
one of those bands is exactly 0, `k`'s raw weight is `<= 0`, which clamps to
exactly 0. This holds for every `k != i` simultaneously, so after
normalization `i`'s weight is exactly 1. `blend_animation_math_test.dart`
verifies this for both a symmetric 8-point radial layout and the real
asymmetric locomotion layout used by the `dying_breath` migration.

### What is *not* guaranteed

Behavior **between** samples is well-behaved and intuitive for
symmetric/radial layouts — such as the 8-directional locomotion layout
this was built for — but is not guaranteed to feel evenly "in-between" for
arbitrary scattered layouts, where a point can be weighted down more than
expected by a poorly-positioned neighbor. This is a known, documented
characteristic of Gradient Band Interpolation, not a bug in this
implementation; it did not need to be worked around for this engine's use
case (radial or axis-aligned parameter layouts).

## 5. Weighted sprite compositing

Once a set of `(clip, weight)` pairs is resolved (weights summing to 1),
turning that into a correctly-blended *picture* is a separate problem from
computing the weights, and it's easy to get subtly wrong.

`BlendCompositor.cumulativeAlphas` (`blend_compositor.dart`) draws each
contributing clip's current frame with `canvas.drawImageRect` — the same
call `Sprite.render` already uses — layered in a fixed order, where layer
`k`'s paint alpha is the **cumulative-renormalized** alpha:

```text
alpha[k] = weights[k] / (weights[0] + ... + weights[k])   // running sum through k, inclusive
```

so the first layer with any weight is always drawn **fully opaque**
(`alpha == 1.0`, since its running sum equals its own weight), and later
layers get progressively smaller alphas as the running sum grows toward 1.

**Proof sketch**: after drawing layers `0..k` with these alphas, the canvas
holds the running weighted average of those layers. Drawing layer `k+1`
with `alpha[k+1] = weights[k+1] / runningSum(0..k+1)` blends it in at
exactly its share of the new running sum — the definition of extending a
weighted running mean by one term. This holds for any layer count and,
given `Σweights = 1`, converges to the exact weighted average.

### The pitfall this avoids

This is exactly the familiar two-layer crossfade pattern ("draw A opaque,
draw B on top at alpha = t") generalized to N layers. It is **not** the
same as reusing each raw `weights[k]` directly as that layer's alpha — that
would give the base layer alpha `weights[0]` instead of `1.0`, which is a
different, generally wrong formula. The discrepancy is invisible with
exactly two layers only in the degenerate sense that people commonly reach
for "draw base opaque, draw incoming at its own weight" — which already
*is* `cumulativeAlphas`' output for N=2 — and only becomes obviously wrong
once you deliberately reuse raw weights as alphas for *every* layer
including the base. It becomes unavoidably visible once **three or more**
clips blend simultaneously, which happens routinely once Gradient Band
Interpolation resolves a query point between three neighbors.
`blend_animation_math_test.dart`'s `BlendCompositor` group works this out
numerically, including a regression case showing the naive substitution
diverging from the correct weighted average at N=3.

No `saveLayer` is needed: Flutter's `Paint.color` alpha channel already
multiplies against each source pixel's own PNG alpha under the default
`BlendMode.srcOver`, so transparent sprite backgrounds stay transparent
regardless of layer weight — the same mechanism `Sprite.render` already
relies on for its own opacity handling. `BlendSprite.render`
(`lib/src/subsystems/rendering/impl/blend_sprite.dart`) mirrors
`Sprite.render`'s exact tint/opacity paint setup, just parameterized per
layer, so a tinted `BlendSprite` composites identically to a tinted
`Sprite`.

## 6. Phase synchronization

All clips contributing to a state share one normalized phase `∈ [0,1)`,
advanced every tick by:

```text
rate  = Σ (weight_i * fps_i / frameCount_i)     // weighted-average cycles/second
phase = (phase + deltaTime * rate) wrapped into [0,1)   // looping states
phase = (phase + deltaTime * rate) clamped to [0,1]     // one-shot states
```

Each clip's own frame index is then `floor(phase * frameCount_i) %
frameCount_i` (looping) — so an 8-frame idle and a 14-frame run blended
together stay phase-locked instead of drifting in and out of sync.

The same rate-based formula covers **both** looping and one-shot states —
for a one-shot state that's a single `ClipMotion`, `rate` reduces to
exactly `1 / clipDuration`, so this is exactly `elapsed / duration` clamped
at 1, matching the old `lockUntilFinished`/`isOneShot` behavior — it's
just derived from the same weighted-rate formula used everywhere else
rather than being a separate special case.

`AnimationBlendTreeSystem._advancePhase`/`_cycleRate` implement this;
`blend_animation_ecs_test.dart`'s "Phase synchronization" group verifies it
against two clips with deliberately different frame counts and fps.

## 7. Transitions — the same primitive, a second weight source

A state transition doesn't need its own compositing logic. It's just a
second weight source: the outgoing state's weighted clips scaled by
`(1 - t)`, the incoming state's scaled by `t` (where `t` is transition
progress, `0..1`), merged into one list, and composited through the
*identical* `cumulativeAlphas` primitive from §5. Blend-tree blending and
transition crossfading are the same operation applied to two different
weight sources — there's no separate "transition renderer."

Both the outgoing and incoming state's phases keep advancing independently
throughout the transition (each still phase-synchronized per §6 within
its own state), so a transition never freezes or restarts either side's
animation — it only changes how much of each contributes to the final
picture.

### Mid-transition interrupts

Re-requesting a new state while already mid-transition doesn't blend three
states at once. `AnimationBlendTreeSystem._resolvePlayRequest` collapses
the in-flight transition onto whichever side (current or target) was
instantaneously dominant (`t >= 0.5` snaps onto the target, `t < 0.5`
settles back on the original current), then starts a fresh transition
toward the newly-requested state from there. Re-requesting the state
already being transitioned *toward* is a no-op — it doesn't disturb the
in-flight crossfade. This is a deliberate simplification (documented, not
a bug): it keeps rapid state changes (e.g. mashing movement keys) visually
coherent as a sequence of clean two-state crossfades rather than an
unbounded blend-of-blends. `blend_animation_ecs_test.dart`'s
"Mid-transition interrupts" group covers all three cases.

## 8. Public API walkthrough

### Code-defined

```dart
final machine = BlendStateMachine(
  states: {
    'idle': BlendState(motion: const ClipMotion('idle')),
    'locomotion': BlendState(
      motion: BlendTree2DMotion(
        parameterX: 'moveX',
        parameterY: 'moveY',
        children: [
          const BlendTree2DChild(position: Offset(0, 0), clip: 'idle'),
          const BlendTree2DChild(position: Offset(0, 1), clip: 'run'),
          const BlendTree2DChild(position: Offset(1, 0), clip: 'strafe_left'),
        ],
      ),
    ),
    'attack': BlendState(motion: const ClipMotion('attack'), loop: false),
  },
  transitions: const [
    BlendTransition(from: 'idle', to: 'attack', duration: 0.05),
  ],
  defaultState: 'idle',
  defaultTransitionDuration: 0.15,
);

final component = AnimationBlendTreeComponent(
  machine: machine,
  clips: {
    'idle': BlendClip(name: 'idle', fps: 8, frameCount: 4, frameSource: ...),
    'run': BlendClip(name: 'run', fps: 12, frameCount: 14, frameSource: ...),
    // ...
  },
);
entity.addComponent(RenderableComponent(renderable: BlendSprite(renderSize: const Size(96, 96))));
entity.addComponent(component);
```

Each tick, driving code sets parameters and requests states — it never
touches phases, weights, or frames directly:

```dart
component.setFloat('moveX', rightRelativeSpeed);
component.setFloat('moveY', forwardRelativeSpeed);
component.play('locomotion');
```

`play()` is idempotent when the requested state is already current (or
already the in-flight transition target) and not restarting — so it's
safe, and expected, to call every single tick.

### JSON

Every data type round-trips through `fromJson`/`toJson`, mirroring the
existing `AnimationClip.fromJson`/`toJson` convention in
`animated_sprite_component.dart`:

```json
{
  "states": {
    "idle": { "motion": { "type": "clip", "clip": "idle" }, "loop": true },
    "locomotion": {
      "motion": {
        "type": "blendTree2D",
        "parameterX": "moveX",
        "parameterY": "moveY",
        "children": [
          { "x": 0, "y": 0, "clip": "idle" },
          { "x": 0, "y": 1, "clip": "run" }
        ]
      },
      "loop": true
    },
    "attack": { "motion": { "type": "clip", "clip": "attack" }, "loop": false }
  },
  "transitions": [{ "from": "idle", "to": "attack", "duration": 0.05 }],
  "defaultState": "idle",
  "defaultTransitionDuration": 0.15
}
```

```dart
final machine = BlendStateMachine.fromJson(jsonDecode(source));
```

Nothing in the engine consumes this path yet (no runtime JSON loader, no
editor authoring UI) — it's forward-looking for a future
`just_game_engine_editor` panel, per the same "code + JSON" convention the
engine already uses elsewhere. `blend_animation_ecs_test.dart`'s "JSON
round-trip" group verifies the schema round-trips losslessly, including
nested blend trees and transition overrides.

## 9. ECS integration

- `AnimationBlendTreeComponent extends Component`
  (`lib/src/ecs/components/animation/animation_blend_tree_component.dart`)
  — pure state: the machine, clip table, live float parameters, and
  runtime playback fields (`currentStateName`, `targetStateName`,
  phases, transition timing).
- `AnimationBlendTreeSystem extends System`
  (`lib/src/ecs/systems/animation/animation_blend_tree_system.dart`) —
  `requiredComponents = [RenderableComponent, AnimationBlendTreeComponent]`,
  `priority => SystemPriorities.animation` (70). It must run after whatever
  game system sets parameters/calls `play()` and before `render` (40); 70
  sits exactly there in the engine's canonical per-frame order (Input 100 →
  Physics 90 → Movement 80 → **Animation 70** → Effects 65 → Gameplay 60 →
  … → Render 40).
- `BlendSprite extends Renderable implements BatchableSprite`
  (`lib/src/subsystems/rendering/impl/blend_sprite.dart`) — drop-in
  replacement for `Sprite` wherever `RenderableComponent.renderable` is
  assigned. `batchImage` always returns `null` (the same opt-out mechanism
  flipped `Sprite`s already use in `RenderSystem`'s atlas-batching path),
  since a `BlendSprite` draws several — potentially different — source
  images per entity per frame, which `Canvas.drawAtlas` batching can't
  express. **No `RenderSystem` changes were needed** for this feature.

### Why clips blend but facing rows don't

This system blends across clips that share the **same drawn facing row**
(gait/pose variants at one orientation — e.g. idle/walk/run/strafe), never
across **different** facing rows. Cross-fading between two different
hand-drawn facing angles would visibly ghost (a double-exposure of two
different poses), not rotate — there's no in-between artwork to
interpolate toward, unlike gait variations at a fixed facing, which *are*
different plausible in-between poses of the same pose. So a directional
octant snap (`_rowForDirection`-style) for facing is not a gap in this
feature — it's a deliberate scope boundary. `AnimationBlendTreeComponent`
exposes `directionRow`, applied uniformly to every blended layer for
exactly this reason: direction is orthogonal to blending, not another
blend axis.

True smooth 360° facing rotation for 2D sprites would need either many
more pre-rendered facing angles (reducing, not eliminating, the same
ghosting problem between more closely-spaced angles) or a fundamentally
different rendering technique (a real 3D/skeletal character, or per-pixel
rotation of a top-down billboard) — out of scope for a sprite-sheet blend
tree.

## 10. Clip/image loading strategies

`BlendFrameSource` (`lib/src/ecs/components/animation/blend_clip.dart`) is
an abstract "where do this clip's pixels come from" interface with one
concrete implementation, `GridBlendFrameSource`, that covers both of this
engine's real sprite-sheet conventions with a single class:

- **Dedicated image per clip** (this engine's actual convention — e.g.
  `dying_breath`'s `assets/characters/players/player_1/<weapon>/<clip>.png`,
  one PNG per named clip): construct with `originX`/`originY` at their
  default of `0`.
- **Shared atlas sheet** (multiple clips packed into one image): construct
  with a non-zero `originX`/`originY` offset into the shared `image`.

`BlendClip.fromJson` eagerly builds a `GridBlendFrameSource` (with `image`
left `null`) whenever the JSON includes a complete grid description
(`frameWidth`, `frameHeight`, `columns`, `rows`) — so a loader's only job is
to decode `assetPath` and assign the result to `frameSource!.image`. A
clip whose `frameSource` (or `frameSource!.image`) is still `null` simply
contributes no visible layer that tick; its phase still advances normally,
so it "catches up" seamlessly the moment loading completes.

## 11. Known limitations

- **Between-sample smoothness for scattered 2D layouts** is not
  guaranteed — see §4. Not a concern for radial/axis-aligned layouts.
- **`BlendSprite` is never atlas-batched** (§9) — each blended entity
  costs one `drawImageRect` call per contributing layer instead of
  participating in `Canvas.drawAtlas` batching. This is a non-issue at the
  scale this was built for (a handful of blended entities, e.g. the
  player) but would need a different approach (a custom multi-image batch,
  or a shader) before applying it to large simultaneously-blended crowds.
- **No declarative condition/trigger system.** Transitions are driven
  entirely by imperative `play()` calls from game code — there's no
  Unity-style "parameter comparison" condition graph deciding transitions
  on its own. `BlendTransition`'s JSON shape has room to grow a
  `conditions` field later without a breaking change; it wasn't needed for
  this engine's first consumer.
- **No editor authoring UI.** The JSON schema (§8) is forward-looking for
  a future `just_game_engine_editor` panel; nothing reads it at runtime
  yet beyond `fromJson`/`toJson` themselves.

## 12. Testing

- `test/blend_animation_math_test.dart` — pure math, no `World`/ECS
  involved: `BlendSpace1D` bracket/clamp behavior; `BlendSpace2D` against
  both a symmetric 8-point radial layout and the real asymmetric
  locomotion layout (own-sample identity, sum-to-1, non-negativity,
  degeneration to 1D for collinear points, degenerate/coincident-point
  inputs); `BlendCompositor`'s weighted-average reproduction for N=1..5
  layers plus the worked N=3 divergence regression from §5.
- `test/blend_animation_ecs_test.dart` — built on a real `World` +
  `AnimationBlendTreeSystem` (no `ui.Image` needed — phase/weight/
  transition bookkeeping never touches `BlendFrameSource.image`): `play()`
  semantics, phase lockstep across differing frame-count/fps clips,
  transition crossfade progression and completion, independent phase
  advancement during a transition, one-shot lock/complete timing,
  mid-transition interrupt collapse, `BlendStateMachine.durationFor`
  override precedence, and JSON round-tripping.

Run with `flutter test` from `packages/just_game_engine`.

## 13. Migration case study — `dying_breath` player locomotion

`PlayerAnimationSystem`
(`dying_breath/lib/game/systems/player_animation_system.dart`) migrated its
movement-driven clip selection onto this system, shipping in 1.8.0 (see
`CHANGELOG.md`).

### Before

`_chooseSheet` picked one of `idle`/`walk`/`run`/`run_backwards`/
`strafe_left`/`strafe_right` (and their `_attack` variants while firing)
via a hard speed threshold plus a dot-product direction test
(`_sheetForMovement`), and `_switchSheet` hard-cut to it — `elapsed`/
`frameIndex` reset to 0, no interpolation. Facing direction came from a
hard `atan2` → octant `floor` (`_rowForDirection`).

### After

`dying_breath/lib/game/animation/player_blend_state_machine.dart`
(`buildPlayerBlendStateMachine`) defines two 2D freeform-directional blend
trees over parameters `moveX` (facing-right-relative)/`moveY`
(facing-forward-relative), fed every tick by
`PlayerAnimationSystem._feedLocomotionParams` — a direct port of the old
`_sheetForMovement`'s dot-product math, scaled by
`(speed / playerSpeed).clamp(0, 1)`:

- `'locomotion'`/`'locomotion_idle2'`/`'locomotion_idle3'` (one per
  idle-combo variant): `idle` at the origin, `walk` at half speed forward,
  `run`/`run_backwards`/`strafe_left`/`strafe_right` at full speed on each
  axis.
- `'locomotion_aim'`: the same shape for firing on the move, with
  `attack_1` (the old stationary-firing clip) at the origin instead of
  `idle`/`walk` — unifying what was previously a hard `speed <= 10` branch
  into the same continuous blend.

Everything else `_chooseSheet` handled (melee combo, taunt, take-damage,
death, crouch, dash/burst) stayed a simple single-clip state — those were
never part of the hard-pop problem this migration targets. `_rowForDirection`
is unchanged and still drives `AnimationBlendTreeComponent.directionRow`
directly (see §9, "why clips blend but facing rows don't").

Per-clip images now load defensively (`PlayerAnimationSystem._loadClips`,
try/catch per clip) rather than the old unguarded `_loadAllSheets` —
`machete/` is genuinely missing the four aim-fire sheets that `rifle/`/
`shotgun/` have (verified against the actual asset folders), which would
have thrown on every clip-load call for a machete-equipped player under
the old code path.

### What this fixes

- The hard walk→run pop at the old speed threshold is now a continuous
  blend along the forward axis.
- The hard pop when crossing between run/strafe-left/strafe-right/
  run-backwards at the direction boundaries is now a continuous blend
  across the 2D plane.
- The hard pop between stationary firing (`attack_1`) and firing while
  moving is now part of the same continuous blend.
- The pre-existing machete asset-load crash risk is fixed as a side effect
  of the defensive per-clip loader.

### Verified

Live-tested via `flutter run -d windows` (debug build): the player spawns
and idles with a cleanly-composited single-clip frame (Gradient Band
Interpolation correctly resolves 100% weight to `idle` at the blend
tree's origin), running renders a clean single-clip frame with no
ghosting/corruption, and the one-shot death state correctly completes and
fires `PlayerDiedEvent` through to the game-over screen — confirming the
full pipeline (defensive clip loading → parameter feeding → blend
evaluation → phase sync → compositing → `BlendSprite` rendering) end to
end, with zero console exceptions across the session.
