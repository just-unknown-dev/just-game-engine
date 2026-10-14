# ESP Architecture (Recommended App Structure)

**E**ngine · **S**ignal · **P**resentation — a three-layer pattern for structuring an app on top of Just Game Engine. It isn't new machinery: it's the same shape already backing the Subtitle (`SubtitleController` + `SubtitleOverlay`) and Narrative (`NarrativeSignals`) subsystems (see [ARCHITECTURE.md](ARCHITECTURE.md)), generalized for app code and built from pieces that already exist — the engine's `EventBus` and reactive ECS (`ComponentSignal`, `EntitySignal`, `WorldSignal`), and `just_signals`' `Signal`, `Computed` and `SignalBuilder`.

> **`just_signals` is not re-exported.** `package:just_game_engine/just_game_engine.dart` does not export `Signal`, `Computed`, `SignalBuilder` or `SignalSelector`. Add `just_signals` to your app's `pubspec.yaml` and `import 'package:just_signals/just_signals.dart';` in the state and presentation layers. (`ComponentSignal` and the other reactive wrappers come from the engine and extend `just_signals`' `Signal`.)

```
   Engine layer                State layer                 Presentation layer
   (ECS: World, Entity,        (plain Dart, no              (Flutter widgets,
    Component, System)          Flutter imports)              SignalBuilder<T>)
          │                          │                              │
   System.update() ──writes──▶ Signal<T> ◀──reads (SignalBuilder)───┤
          │                          ▲                              │
   world.events.fire(event) ──▶ EventBus.on<T>() ──▶ translates to Signal writes / callback calls
```

- **Engine layer**: `System`s, `Component`s, `Entity`s — the only layer that imports ECS types. Pushes data outward two ways: continuous values via `Signal.value =`, one-shot transitions via `world.events.fire(event)` (delivered synchronously to the subscribers of the event's exact runtime type).
- **State layer**: plain Dart classes holding `Signal<T>`/`Computed<T>` fields (one `*Signals` class per feature, following `NarrativeSignals`'/`SubtitleController`'s shape), plus small controller classes exposing named transition methods instead of a raw settable `Signal`. Depends only on `just_signals` — no `flutter/material.dart`, no ECS types. Testable in isolation, with no widget tree required.
- **Presentation layer**: Flutter widgets that read the state layer exclusively through `SignalBuilder<T>`/`SignalSelector<T, R>`, and call back out through closures/controller methods instead of reaching into `World`/`Entity` directly. Zero ECS imports.

## Where the presentation layer attaches

`GameWidget` has two slots for widgets drawn over the game:

- **`GameWidget(overlay: ...)`** — a widget stacked over the game canvas, inside the game's own `Focus` node. It gets taps but can never hold keyboard focus, which keeps `engine.input`'s key state reliable. Good for a HUD and buttons driven by pointer or touch.
- **`engine.layers`** — register a `GameLayer` (an `id`, an `order`, and `createController(engine)`). Every `GameWidget` showing the engine asks it for its own `GameLayerController`, whose `build` draws the widgets and whose `onFrame` runs once a frame after the game has stepped. Layers sit *outside* the game's `Focus` node, so a text field can be typed into and a menu walked with the arrow keys; keys a layer does not use still reach the game. Use a layer for menus, pause screens and anything that needs the keyboard. `engine.layers.setEnabled(id, false)` hides one and keeps its state.

Either way the widgets read signals from the state layer; neither slot needs the widgets to know about entities. When `engine.context.localization` is set, both sit under a `LocalizationScope` for it.

## Pros

- **Surgical rebuilds, not polling.** `SignalBuilder` is a `StatefulWidget` holding one listener per instance; a `Signal.value =` write notifies only its own listener set directly, with no `InheritedWidget` dependency walk and no `Timer`-driven cadence decoupled from the frame loop. UI updates land the same tick the underlying data changed, instead of up to one polling-interval late.
- **One-shot state has zero steady-state cost.** `EventBus.fire()` only does work when something actually happens (a death, a level-complete, a dialogue line) — there's no "is it still true?" check running every frame the way inferring state from component presence/absence would require.
- **A clear seam for hot-path discipline.** Because the presentation layer only ever touches the state layer, it's easy to audit exactly what runs on every tick (the engine-layer systems writing into it) versus what only runs on user interaction — a natural place to enforce "no per-frame allocations, no per-frame O(n) scans" in review.
- **Independently testable state.** The state layer has no Flutter dependency, so `Signal`/controller logic can be unit-tested without pumping a widget tree.
- **Reuses pieces the engine already exercises** — the same shape as the Narrative and Subtitle subsystems, so there is no new state-management package or mental model for code already using the engine's reactive ECS.

## Cons (and how to mitigate each)

- **Signals make the *presentation* side cheap, not the engine layer automatically.** A `System.update()` that hunts for an entity every frame — walking `world.entities`, or a broad `world.query(...)` result, to find one thing — pays that walk every frame, no matter how cheap the signal write after it is. The world's own lookups are indexed: `findEntityByName`, `findTagged` and `allTagged` are map lookups (and `allTagged` returns a cached list, so it does not allocate), and `query` results are cached until a matching archetype changes. *Mitigation*: use those lookups rather than scanning, and for an entity a system touches every frame, resolve it once (e.g. at spawn time) and keep the reference, checking `entity.isAlive` before use. This exact mistake — a HUD-sync system, plus two older systems, resolving the same entities every frame — was caught and fixed in the app that motivated this document.
- **More files/indirection than a single local toggle needs.** Three layers for one boolean is overhead. *Mitigation*: reserve this pattern for state genuinely shared across multiple widgets or updated continuously by the engine layer — a one-off, widget-local UI toggle can stay a plain `setState` field.
- **No built-in write-ordering guarantee if two systems touch the same signal in one frame.** `Signal` has no scheduling of its own — whichever system runs first, its listeners fire immediately on that write. *Mitigation*: give the writing system an explicit `priority` placing it after everything it reads from, so a signal is only ever written once per frame with fully-settled data (e.g. a HUD-sync system reading post-gameplay health should run after `HealthSystem`, priority `SystemPriorities.gameplay`, not before).

## Performance Tips (specific to this pattern)

- Keep entity lookups out of per-frame loops when the answer is stable. `world.findEntityByName(name)`, `world.findTagged(tag)` and `world.allTagged(tag)` are indexed and cheap; `world.query([HealthComponent, TagComponent])` is cached per set of component types. What stays expensive is scanning — iterating `world.entities` or a large query result to find one entity. Cache a reference when you can.
- Prefer one `Signal` per meaningfully-independent value over batching unrelated values into a single tuple/record signal, unless they're always consumed together by the same widget — finer-grained signals mean fewer unrelated widgets rebuild per write.
- `Signal.value =` already no-ops when the new value equals the old one — don't hand-roll an extra equality check before assigning.
