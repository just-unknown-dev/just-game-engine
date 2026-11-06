# Audio

_Audio & content_ · Play music and sound effects through engine.music and engine.sfx, attach sounds to entities, place them in 3D, and start audio correctly on the web.

Audio comes from `just_audio_engine`. `engine.music` plays one music track, `engine.sfx` plays sound effects, and `engine.audio` is the `AudioEngine` underneath, with channels, effects and 3D sound. For sounds that belong to things in the world, put an `AudioSourceComponent` on an entity.

Paths are asset paths, so list your audio folder under `flutter: assets:` in `pubspec.yaml`.

## Music and sound effects

```dart lib/sounds.dart
import 'package:just_game_engine/just_game_engine.dart';

Future<void> startMusic(Engine engine) =>
    engine.music.play('assets/audio/theme.ogg', volume: 0.6, fadeIn: true);

Future<void> playJump(Engine engine) async {
  await engine.sfx.play('assets/audio/jump.wav', volume: 0.8);
}

Future<void> stopMusic(Engine engine) => engine.music.stop(fadeOut: true);
```

- `engine.music` (a `MusicManager`) has `play` (looping by default; `fadeIn` with `fadeDuration`, 2 s by default), `pause`, `resume`, `stop` (with `fadeOut`), `setChannelVolume` and `isPlaying`. Playing a new track fades the current one out over a second.
- `engine.sfx` (a `SoundEffectManager`) has `play`, which takes `volume`, `loop`, `pan`, `pitch`, `speed`, `effects` and `channel` and returns an id (null when the file could not load), plus `stop(id)`, `stopAll()`, `setVolume(id, volume)` and `setChannelVolume`.
- `engine.audio` adds `setMasterVolume`, `mute`, `unmute`, `toggleMute`, `preload(paths)` to load sounds before a level starts, and `unloadSource(path)` to free one you no longer need.

## Channels and effects

Every sound plays on an `AudioChannel`: `master`, `music`, `sfx`, `voice` or `ambient`. A channel's volume scales every sound on it, streams included.

```dart
engine.music.setChannelVolume(0.5);
engine.sfx.setChannelVolume(0.8);
engine.audio.setChannelVolume(AudioChannel.ambient, 0.4);
```

Effects are applied per voice when playback starts. Pass them as `effects:` to `engine.sfx.play`, `AudioSystem.playOneShot` or an `AudioSourceComponent`: `AudioEffect.reverb(roomSize: 0.8)`, `AudioEffect.lowpass(frequency: 800)`, `AudioEffect.highpass` and `AudioEffect.eq`, applied in order. Not every platform has every effect (`AudioEffectType` says which does what): one a platform cannot do is left out, and the sound plays on.

## Sounds on entities

`AudioSourceComponent` is data; `AudioSystem`, a default system, plays it. A source starts as soon as the system sees it (`playOnAdd`, true by default), stops when the component or its entity goes, and pauses while the entity is switched off.

```dart lib/world_sounds.dart
/// A looping sound placed in the world: full volume within 50 units,
/// fading to silence at 800, muffled towards the far end.
Entity addWaterfall(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(600, 100, 0)),
  AudioSourceComponent(
    clipPath: 'assets/audio/waterfall.ogg',
    loop: true,
    channel: AudioChannel.ambient,
    is3D: true,
    minDistance: 50,
    maxDistance: 800,
    farCutoff: 1500,
  ),
], name: 'Waterfall');

/// From a system: played once, with nothing added to an entity.
void playCoin(World world, Entity coin) =>
    world.getSystem<AudioSystem>()?.playOneShot(
      'assets/audio/coin.wav',
      position: coin.getComponent<TransformComponent>()?.position,
    );

/// A third-person game hears from the player, facing like the camera.
void hearFrom(Entity player) =>
    player.addComponent(AudioListenerComponent(faceCamera: true));
```

Control a source with `play()` (from the start), `pause()`, `resume()` and `stop()`. Each asks `AudioSystem` to act at its next update and never changes the component's saved fields, so a scene saved while a sound plays still starts it next time. A source's `volume` is followed while it plays; `pan`, `loop`, `pitch`, `speed` and `effects` are read when it starts.

For long music or ambience, use `AudioStreamComponent(path: ...)`, which streams the file instead of loading it whole. It loops on the `music` channel by default, can fade in over `fadeInDuration`, and has the same `play`, `pause`, `resume` and `stop`.

## 3D sound and the listener

With `is3D: true` a source is heard from where its entity is, relative to the listener:

| Field | Default | What it does |
|---|---|---|
| `minDistance` | 1 | Full volume within this distance. |
| `maxDistance` | 50 | Silent at and beyond it (unless `rolloff` is `Audio3DRolloff.none`). |
| `rolloff` | `Audio3DRolloff.inverse` | How the sound fades between the two: `inverse`, `linear` or `none`. |
| `farCutoff` | 0 | Low-pass cutoff in Hz the sound is muffled to at `maxDistance`; 0 keeps it clear. |
| `dopplerLevel` | 0 | How much movement bends the pitch; 1 is the real-world effect for a world in metres. |

Distances are in world units: pixels in a 2D game, metres in 3D. A 2D game usually needs larger distances than the defaults, as in the waterfall above. A 3D source is not also panned, so its `pan` is ignored.

`AudioListenerComponent` marks the entity that hears. It hears from the entity's position and faces the way the entity's rotation turns the world's forward (+Z) and up (−Y). `atCamera: true` hears from the output camera's position instead, and `faceCamera: true` faces the way the camera does. Only the first listener counts; with none, `AudioSystem` hears from the camera.

## Audio on the web

Browsers keep audio silent until the player interacts with the page. On the web the engine therefore starts audio at the first key or pointer press instead of in `initialize()`. `EngineConfig(deferAudioUntilInput: ...)` changes this: null (the default) means on the web only, true means everywhere and false means never.

- A sound you play before then starts the audio engine early, and the browser may keep it silent.
- A one-shot asked for before audio has started is dropped, not queued.
- A "click to start" screen is a simple way to make sure the first press happens before your music.

When the app goes to the background, `GameWidget` pauses the music and the world's sounds and mutes the rest, and restores exactly that when the app returns. You can do the same yourself with `engine.suspendAudio()` and `engine.resumeAudio()`. See [Platforms](/docs/platforms) for other web differences.

## Known limitations

- A playing sound's pitch, pan, speed and loop cannot change until it plays again.
