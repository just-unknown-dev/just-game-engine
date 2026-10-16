/// Audio ECS Components
///
/// Components for integrating audio with the ECS architecture.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart' show internal;

import '../../../subsystems/audio/audio.dart';
import '../../ecs.dart';

/// What a game asks of a playing sound; see [AudioRequests].
enum AudioRequest {
  /// Pause it where it is.
  pause,

  /// Play on from where [pause] left it.
  resume,

  /// Play it from the start, stopping it first if it plays.
  play,

  /// Stop it.
  stop,
}

/// Play, pause, resume and stop for a component that plays a sound —
/// [AudioSourceComponent] and [AudioStreamComponent].
///
/// Each call asks the `AudioSystem`, which carries it out at its next
/// update. Nothing is added to or taken from the entity, and the
/// component's saved fields are not changed, so asking costs nothing and an
/// editor saving the scene saves what was authored; it works on an entity
/// that is switched off too. Within one update the last of [play] and
/// [stop] wins over [pause] and [resume]; otherwise the last call counts.
///
/// ```dart
/// final door = entity.getComponent<AudioSourceComponent>()!;
/// door.pause();
/// door.resume();
/// door.stop();
/// door.play(); // from the start again
/// ```
mixin AudioRequests on Component {
  /// Whether the sound starts as soon as the `AudioSystem` sees it. The
  /// system never changes it: it is what the scene says, so a scene saved
  /// while (or after) it played still starts its sounds.
  bool get playOnAdd;
  set playOnAdd(bool value);

  AudioRequest? _request;

  /// What [play], [pause], [resume] or [stop] asked that the system has not
  /// yet carried out, or null.
  AudioRequest? get pendingRequest => _request;

  bool get _startsOrStops =>
      _request == AudioRequest.stop || _request == AudioRequest.play;

  /// Plays the sound from the start at the system's next update, stopping
  /// it first if it plays — also one that [stop] stopped, one that played
  /// to its end, and one whose [playOnAdd] is false.
  void play() => _request = AudioRequest.play;

  /// Pauses the sound at the system's next update — one still loading as
  /// soon as it starts. A sound that is not playing is not affected.
  void pause() {
    if (!_startsOrStops) _request = AudioRequest.pause;
  }

  /// Plays on a sound [pause] paused, at the system's next update. One also
  /// paused because its entity is switched off, or because the app is in
  /// the background, plays on once that is over too.
  void resume() {
    if (!_startsOrStops) _request = AudioRequest.resume;
  }

  /// Stops the sound at the system's next update — also one still loading,
  /// or one that has not started yet. It does not start again by itself
  /// ([playOnAdd] notwithstanding); [play] starts it again.
  void stop() => _request = AudioRequest.stop;

  /// For the `AudioSystem`: what was asked, which is then forgotten.
  @internal
  AudioRequest? takeRequest() {
    final request = _request;
    _request = null;
    return request;
  }
}

/// Component describing an audio source attached to an entity.
///
/// This is data-only. The actual loading and playback is handled by
/// [AudioSystem]; [pause], [resume] and [stop] ask it to control the sound.
/// The sound stops when the component or its entity goes, and pauses while
/// the entity is switched off — playing on from where it was when it is
/// switched back on.
///
/// For a sound played once, with nothing to control afterwards, use
/// [AudioSystem.playOneShot].
class AudioSourceComponent extends Component with AudioRequests {
  /// A source for [clipPath] that plays once, at full volume, centred, at
  /// its original pitch and speed, as soon as `AudioSystem` sees it.
  ///
  /// With [is3d] it is placed at the entity instead: full volume within
  /// [minDistance] of the listener, silent beyond [maxDistance], faded
  /// between by [rolloff].
  AudioSourceComponent({
    required this.clipPath,
    this.volume = 1.0,
    this.pan = 0.0,
    this.loop = false,
    this.playOnAdd = true,
    this.channel = AudioChannel.sfx,
    this.is3d = false,
    this.pitch = 1.0,
    this.speed = 1.0,
    this.effects = const [],
    this.minDistance = 1.0,
    this.maxDistance = 50.0,
    this.rolloff = AudioRolloff.inverse,
    this.dopplerLevel = 0.0,
    this.farCutoff = 0.0,
  });

  /// Asset path to the audio clip.
  String clipPath;

  /// Volume `[0.0 – 1.0]`, scaled by its [channel]'s own volume. Followed
  /// while the sound plays.
  double volume;

  /// Stereo pan, -1.0 (left) to +1.0 (right); 0.0 is centred. Ignored
  /// while the source is placed in 3-D ([is3d] on an entity with a
  /// transform). Read when the sound starts, like [loop], [pitch], [speed]
  /// and [effects]: a change while it plays is heard the next time it
  /// plays.
  double pan;

  /// Whether to loop the clip.
  bool loop;

  /// If true, playback starts as soon as the system processes this entity
  /// — once: the system remembers it started it, and never changes this
  /// field. [play] plays it again.
  @override
  bool playOnAdd;

  /// The channel the sound plays on: its volume scales the sound, and on
  /// the web it is the bus the sound goes through.
  AudioChannel channel;

  /// If true, the source is heard from where the entity is, relative to
  /// the listener ([AudioListenerComponent]); without a transform it plays
  /// flat.
  bool is3d;

  /// Pitch multiplier: 1.0 = original, 2.0 = one octave up.
  double pitch;

  /// Playback speed multiplier (1.0 = normal).
  double speed;

  /// DSP effects applied to this voice when playback starts.
  List<AudioEffect> effects;

  /// 3-D: within this distance of the listener, in world units, the sound
  /// plays at full volume.
  double minDistance;

  /// 3-D: at and beyond this distance the sound is silent (unless the
  /// [rolloff] is [AudioRolloff.none]), and muffled down to [farCutoff].
  double maxDistance;

  /// 3-D: how the sound fades between [minDistance] and [maxDistance].
  AudioRolloff rolloff;

  /// 3-D: how much moving changes the pitch — 0 none, 1 the real-world
  /// doppler effect (for a world in metres).
  double dopplerLevel;

  /// 3-D: the low-pass cutoff, in Hz, the sound is muffled to at
  /// [maxDistance]; 0 leaves it clear at any distance.
  double farCutoff;

  /// How the sound is heard in 3-D, from the fields above, made safe: a
  /// zero or negative [minDistance], or a [maxDistance] below it, cannot
  /// throw.
  AudioSpatial get spatial {
    final min = math.max(minDistance, 1e-3);
    return AudioSpatial(
      minDistance: min,
      maxDistance: math.max(maxDistance, min),
      rolloff: rolloff,
      dopplerLevel: math.max(dopplerLevel, 0),
      farCutoff: math.max(farCutoff, 0),
    );
  }

  /// Internal source handle managed by [AudioSystem].
  Object? loadedSource;

  /// Internal playback handle managed by [AudioSystem]: the sound's ID while
  /// it plays, null once it has stopped or played to its end.
  Object? handle;
}

/// Component that streams a large audio file without buffering it entirely.
///
/// Use for music tracks or long ambient loops. The [AudioSystem] opens an
/// [AudioStream] backed by the native streaming path and manages its lifecycle.
/// The stream stops when the component or its entity goes, and pauses while
/// the entity is switched off. Control it with [pause], [resume] and [stop],
/// not through [stream]: the app coming back from the background plays on
/// every stream the background paused, and only [pause] tells the system the
/// game paused one.
class AudioStreamComponent extends Component with AudioRequests {
  /// A stream of [path] on the music channel that loops at full volume and
  /// starts as soon as `AudioSystem` sees it; no fade-in unless
  /// [fadeInDuration] is given.
  AudioStreamComponent({
    required this.path,
    this.volume = 1.0,
    this.loop = true,
    this.playOnAdd = true,
    this.channel = AudioChannel.music,
    this.fadeInDuration,
  });

  /// Asset path to the audio file.
  String path;

  /// Volume `[0.0 – 1.0]`. Followed while the stream plays.
  double volume;

  /// Whether to loop the stream indefinitely.
  bool loop;

  /// If true, streaming starts as soon as the system processes this entity
  /// — once: the system remembers it started it, and never changes this
  /// field. [play] plays it again from the start.
  @override
  bool playOnAdd;

  /// The audio channel the stream is meant for, handed to its
  /// [AudioStream] (on the web, the bus it goes through). A stream bypasses
  /// the engine's channel volumes, so the channel's volume does not apply.
  AudioChannel channel;

  /// How long the stream takes to fade in from silence to [volume] when
  /// it starts; null or zero starts it at [volume] at once.
  Duration? fadeInDuration;

  /// Internal [AudioStream] instance managed by [AudioSystem].
  AudioStream? stream;

  /// Whether the stream is currently open and playing.
  bool get isPlaying => stream?.isPlaying ?? false;
}

/// Marks the entity that hears: 3-D sounds are panned and faded for where
/// it is and which way it faces.
///
/// By default it hears from the entity's own transform: its position, and
/// the way its rotation turns the world's forward (+Z) and up (−Y). Either
/// can come from the output camera instead — [atCamera], [faceCamera]. A
/// third-person game puts the listener on the player with [faceCamera]:
/// the hero's own sounds stay centred and full, the world's turn with the
/// view.
///
/// Only the first listener counts. With none, the `AudioSystem` hears from
/// the camera, when it has one.
class AudioListenerComponent extends Component {
  /// A listener at the entity, facing the way the entity does.
  AudioListenerComponent({this.atCamera = false, this.faceCamera = false});

  /// Hear from where the output camera is, not the entity. Needs the
  /// [AudioSystem] to be given the camera (the engine's default systems
  /// do).
  bool atCamera;

  /// Face the way the output camera faces, not the entity.
  bool faceCamera;
}
