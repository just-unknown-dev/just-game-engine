# Timelines

_Graphics_ · Animate any component field over time, and play clips, cut cameras, switch entities, play sounds and fire events from one asset.

A timeline animates component fields over time, and can also play sprite clips, cut between cameras, switch entities on and off, play sounds and fire events, all on one clock. Use one for a bobbing coin, a door, a moving platform or a whole cut-scene.

Timelines are assets: a `.timeline.json` file (format 2), or a `TimelineAsset` stored inline in the component that plays it. The editor's Timeline dock authors them, with a dope sheet, a curve editor, record mode and motion paths drawn in the level (see [The editor](/docs/editor)). The files are plain JSON, so you can also write them by hand or build them in code.

`TimelineSystem` plays them and `TimelineTriggerSystem` starts them from trigger areas. Both come with `DefaultSystem.sprites`.

## A timeline file

This one slides its entity 96 units up in one second and fires `opened` at the end:

```json assets/timelines/door_open.timeline.json
{
  "formatVersion": 2,
  "name": "door_open",
  "duration": 1.0,
  "wrap": "once",
  "tracks": [
    {
      "kind": "property",
      "component": "TransformComponent",
      "field": "position",
      "channel": "y",
      "mode": "relative",
      "keys": [
        { "t": 0.0, "v": 0.0, "i": "eased", "e": "easeInOutCubic" },
        { "t": 1.0, "v": -96.0 }
      ]
    },
    {
      "kind": "event",
      "events": [{ "time": 1.0, "name": "opened" }]
    }
  ]
}
```

- `duration` is in seconds, and `wrap` is `once`, `loop` or `pingPong`. `fps` only sets how the editor snaps time. Optional `markers` (`{ "time": 3.0, "name": "skip" }`) are named places to play from.
- A property track keys one field of one component: any field the component's definition saves, a package's own components included. `channel` picks one number of a vector (`x`, `y`, `z`) or an offset (`dx`, `dy`).
- `"mode": "relative"` makes the keys offsets from the value the field had when the timeline started, so one asset opens every door wherever it stands. Only numbers can be relative.
- A key has a time `t` and a value `v`. Without `i` it reaches the next key along a bezier, which is a straight line until you give it `in` and `out` handles. `"i": "linear"` is a straight line, `"i": "step"` holds, and `"i": "eased"` follows the easing named in `e` (see Easing on [Sprites & animation](/docs/sprites)).
- A track acts on the entity playing the timeline unless it has a `binding`, such as `{ "name": "Door" }` or `{ "tag": "enemy" }`.

## Track kinds

| `kind` | Track | What it does |
|---|---|---|
| `property` | `PropertyTrack` | Keys one field of one component |
| `event` | `EventTrack` | Fires named `events`, each with an optional `payload`, whenever play crosses them in either direction |
| `spriteClip` | `SpriteClipTrack` | Plays the block's clip on the bound `SpriteAnimationComponent`; between blocks the sprite goes back to its own clip |
| `cameraShot` | `CameraShotTrack` | Raises the priority of the virtual camera the block names by its `amount`, rounded to a whole number, while the block lasts (the editor starts new shots at 100) |
| `audio` | `AudioTrack` | Plays the file the block names, at `amount` volume, when time passes the block's start going forwards |
| `activation` | `ActivationTrack` | The bound entity is active inside the blocks and inactive outside them |
| `nested` | `NestedTimelineTrack` | Runs the timeline the block names inside this one |
| `skeletalClip` | `SkeletalClipTrack` | With `Graphics3D` only: plays clips on a 3D model's `AnimationPlayerComponent` |

All but the first two are block tracks: a list of `blocks`, each with a `start` and `length` in seconds, a `value`, and optional `speed`, `amount` and `loop`. A cut-scene:

```json assets/timelines/boss_intro.timeline.json
{
  "formatVersion": 2,
  "name": "boss_intro",
  "duration": 6.0,
  "wrap": "once",
  "tracks": [
    {
      "kind": "cameraShot",
      "blocks": [{ "start": 0.0, "length": 3.0, "value": "BossCam", "amount": 100 }]
    },
    {
      "kind": "spriteClip",
      "binding": { "name": "Boss" },
      "blocks": [{ "start": 1.0, "length": 2.0, "value": "roar" }]
    },
    {
      "kind": "audio",
      "blocks": [{ "start": 1.0, "value": "assets/audio/roar.ogg", "amount": 0.8 }]
    },
    {
      "kind": "activation",
      "binding": { "name": "BossHealthBar" },
      "blocks": [{ "start": 3.0, "length": 3.0 }]
    },
    {
      "kind": "event",
      "events": [{ "time": 6.0, "name": "fight", "signal": true }]
    }
  ],
  "markers": [{ "time": 3.0, "name": "skip" }]
}
```

> **Note:** Blocks that run to the very end of a `once` timeline hold there: a camera shot keeps its camera until the player stops, and activation and sprite-clip blocks keep their state. End a shot block before the timeline ends to hand the camera back, as `boss_intro` does.

## Playing from code

A `TimelinePlayerComponent` plays one timeline on its entity: the asset at `timelinePath`, or the `inline` one when the path is empty. Tracks without a binding act on that entity, so one asset can animate many.

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

void addDoor(Engine engine) {
  final world = engine.world;

  // Plays when a player walks into the 200 x 200 area round the door,
  // and plays backwards when they leave.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(500, 250, 0)),
    RectangleComponent(width: 40, height: 96),
    TimelinePlayerComponent(
      timelinePath: 'assets/timelines/door_open.timeline.json',
    ),
    TimelineTriggerComponent(
      width: 200,
      height: 200,
      onEnter: TimelineTriggerAction.play,
      onExit: TimelineTriggerAction.reverse,
    ),
  ], name: 'Door');

  // Events from every timeline in the world.
  world.getSystem<TimelineSystem>()?.events.listen((event) {
    debugPrint('${event.owner.name}: ${event.name}');
  });
}

/// Restarts every timeline player whose `listenSignal` is "alarm".
void soundTheAlarm(Engine engine) => engine.context.signals.emit('alarm');
```

The player's controls work even before the timeline has loaded: the last one asked is done when it arrives.

- `play()` carries on from where it is, `restart()` plays from the start, `reverse()` plays backwards and `forwards()` forwards again. `pause()` holds, `stop()` rewinds, `seek(t)` jumps without firing the events in between, `playFrom('skip')` starts at a marker, and `playTimeline(path)` swaps in another asset.
- `playOnStart: true` plays at once. `speed` scales time, and a negative speed plays backwards.
- `wrap` overrides the asset's own: `TimelineWrapChoice.once`, `loop`, `pingPong` or `fromTimeline` (the default).
- `from` and `to` play only part of the timeline, in seconds, so one asset can serve several entities differently.
- `isPlaying`, `isFinished`, `time` and `progress` say where it is.

A `TimelineTriggerComponent` drives a player when a target walks into its rectangle, centred on its entity (128 by 128 by default; the entity's scale and rotation are ignored). It is set off by entities tagged `player` unless you give it another `target`, and drives its own entity's player unless `playerName` names another. `onEnter` (`restart` by default) and `onExit` (`nothing` by default) take a `TimelineTriggerAction`: `play`, `restart`, `reverse`, `pause`, `stop` or `nothing`. `oneShot: true` fires once.

## Events and signals

`world.getSystem<TimelineSystem>()?.events` streams a `TimelineEventFired` (its `owner`, `name` and `payload`) for every event any timeline fires.

`engine.context.signals.emit('alarm')` restarts every player whose `listenSignal` is `alarm`. Signals are shared by every world on the engine, so a button on a UI screen can start a timeline in the level. An event with `"signal": true`, like `fight` above, is sent as a signal too, which is how one timeline sets off another.

## Timelines in code

A `TimelineAsset` can also be built in code and given to a player as `inline`:

```dart
import 'package:just_game_engine/just_game_engine.dart';

/// A coin that bobs 12 units up and down for ever.
Entity addCoin(World world, Vector3 at) {
  final bob = TimelineAsset(
    name: 'coin_bob',
    duration: 1.0,
    wrap: TimelineWrap.pingPong,
    tracks: [
      PropertyTrack(
        component: 'TransformComponent',
        field: 'position',
        channel: 'y',
        mode: PropertyTrackMode.relative,
        curve: KeyCurve(const [
          TimelineKey(
            time: 0,
            value: 0,
            interpolation: KeyInterpolation.eased,
            easing: 'easeInOutSine',
          ),
          TimelineKey(time: 1, value: -12),
        ]),
      ),
    ],
  );
  return world.createEntityWithComponents([
    TransformComponent(position: at),
    CircleComponent(radius: 10),
    TimelinePlayerComponent(inline: bob, playOnStart: true),
  ], name: 'Coin');
}
```

`TimelineAsset.parse(text)` reads a file's text, and `encode()` writes one. A package can add its own track kinds to `engine.context.trackKinds`; a track of a kind the engine doesn't know is kept and saved back unchanged.
