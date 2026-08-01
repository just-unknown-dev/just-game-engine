# ESP Architecture (Recommended App Structure)

**E**ngine · **S**ignal · **P**resentation — a three-layer pattern for structuring an app on top of Just Game Engine. It isn't new machinery: it's the same shape already backing the Subtitle (`SubtitleController` + `SubtitleOverlay`) and Narrative (`NarrativeSignals`) subsystems (see [ARCHITECTURE.md](ARCHITECTURE.md)), generalized for app code and built entirely from pieces the engine already ships — `EventBus`, the Reactive ECS's `Signal`/`ComponentSignal`, and `just_signals`' `SignalBuilder`.

```
   Engine layer                State layer                 Presentation layer
   (ECS: World, Entity,        (plain Dart, no              (Flutter widgets,
    Component, System)          Flutter imports)              SignalBuilder<T>)
          │                          │                              │
   System.update() ──writes──▶ Signal<T> ◀──reads (SignalBuilder)───┤
          │                          ▲                              │
   world.events.fire<T>() ──▶ EventBus.on<T>() ──▶ translates to Signal writes / callback calls
```

- **Engine layer**: `System`s, `Component`s, `Entity`s — the only layer that imports ECS types. Pushes data outward two ways: continuous values via `Signal.value =`, one-shot transitions via `world.events.fire<T>(event)`.
- **State layer**: plain Dart classes holding `Signal<T>`/`Computed<T>` fields (one `*Signals` class per feature, following `NarrativeSignals`'/`SubtitleController`'s shape), plus small controller classes exposing named transition methods instead of a raw settable `Signal`. Depends only on `just_signals` — no `flutter/material.dart`, no ECS types. Testable in isolation, with no widget tree required.
- **Presentation layer**: Flutter widgets that read the state layer exclusively through `SignalBuilder<T>`/`SignalSelector<T, R>`, and call back out through closures/controller methods instead of reaching into `World`/`Entity` directly. Zero ECS imports.

## Pros

- **Surgical rebuilds, not polling.** `SignalBuilder` is a `StatefulWidget` holding one listener per instance; a `Signal.value =` write notifies only its own listener set directly, with no `InheritedWidget` dependency walk and no `Timer`-driven cadence decoupled from the frame loop. UI updates land the same tick the underlying data changed, instead of up to one polling-interval late.
- **One-shot state has zero steady-state cost.** `EventBus.fire<T>()` only does work when something actually happens (a death, a level-complete, a dialogue line) — there's no "is it still true?" check running every frame the way inferring state from component presence/absence would require.
- **A clear seam for hot-path discipline.** Because the presentation layer only ever touches the state layer, it's easy to audit exactly what runs on every tick (the engine-layer systems writing into it) versus what only runs on user interaction — a natural place to enforce "no per-frame allocations, no per-frame O(n) scans" in review.
- **Independently testable state.** The state layer has no Flutter dependency, so `Signal`/controller logic can be unit-tested without pumping a widget tree.
- **Reuses engine internals that already exist and are already exercised in production subsystems** — no new state-management package, no new mental model for consumers already using the engine's Reactive ECS or Narrative/Subtitle systems.

## Cons (and how to mitigate each)

- **Signals make the *presentation* side cheap, not the engine layer automatically.** A `System.update()` that resolves entities via `world.findEntityByName(...)` — a linear scan over every entity — before writing a signal still pays that scan every single frame, no matter how cheap the signal write itself is. *Mitigation*: resolve entity references once (e.g. at spawn time) and cache them as settable fields on the system; never call a `World` lookup/query method inside `update()` for a result that doesn't change entity-to-entity across frames. Treat any `world.find*`/query call inside a hot-path `update()` as a code-review flag — this exact mistake was caught and fixed in the app that motivated this document (a HUD-sync system, plus two pre-existing systems that had the same per-frame `findEntityByName` cost).
- **More files/indirection than a single local toggle needs.** Three layers for one boolean is overhead. *Mitigation*: reserve this pattern for state genuinely shared across multiple widgets or updated continuously by the engine layer — a one-off, widget-local UI toggle can stay a plain `setState` field.
- **No built-in write-ordering guarantee if two systems touch the same signal in one frame.** `Signal` has no scheduling of its own — whichever system runs first, its listeners fire immediately on that write. *Mitigation*: give the writing system an explicit `priority` placing it after everything it reads from, so a signal is only ever written once per frame with fully-settled data (e.g. a HUD-sync system reading post-gameplay Health/Weapon state should run after `HealthSystem`/`WeaponSystem` in priority order, not before).

## Performance Tips (specific to this pattern)

- Never call a `World` query/lookup method (`findEntityByName`, `query<T>()`, etc.) from inside a `System.update()` if the result is stable across frames for that entity — cache it once (e.g. at spawn) instead of resolving it every tick.
- Prefer one `Signal` per meaningfully-independent value over batching unrelated values into a single tuple/record signal, unless they're always consumed together by the same widget — finer-grained signals mean fewer unrelated widgets rebuild per write.
- `Signal.value =` already no-ops when the new value equals the old one — don't hand-roll an extra equality check before assigning.
