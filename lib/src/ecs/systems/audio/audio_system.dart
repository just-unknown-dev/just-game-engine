/// Audio ECS System
///
/// System that drives audio playback from ECS entities.
library;

import 'package:just_dart/just_dart.dart';

import '../../../foundation/world_axes.dart';
import '../../../interfaces/game_camera.dart';
import '../../../subsystems/audio/audio.dart';
import '../../ecs.dart';
import '../../components/components.dart';
import '../../base/system_priorities.dart';

/// System that drives audio playback from ECS entities.
///
/// Processes the following component types:
/// - [AudioSourceComponent]: loads sources, manages playback lifecycle,
///   and places 3-D ones where their entity is ([TransformComponent]).
///   Supports pitch, speed, and DSP [AudioEffect] passes, and follows a
///   change of volume while the sound plays.
/// - [AudioStreamComponent]: opens and drives an [AudioStream] for large
///   files.
/// - [AudioListenerComponent]: where 3-D sounds are heard from — with none,
///   the [camera].
///
/// A source's or stream's `pause`, `resume` and `stop` ([AudioRequests])
/// are carried out here, at the next [update]. Its sound stops when the
/// component or its entity goes, and pauses while the entity is switched
/// off, playing on from where it was when the entity is switched back on.
/// When a source plays to its end, its `handle` goes back to null.
///
/// A sound played once, with nothing to control afterwards — a hit, a
/// pickup, a timeline's cue — is asked for with [playOneShot]: nothing is
/// added to an entity for it.
///
/// Playback starts and stops on the fixed step ([update]); where the
/// listener and 3-D sources are is read once per rendered frame ([frame]),
/// after the camera has moved, and the engine's audio places them all at
/// the end of the frame.
///
/// Nothing plays before the audio engine has started — on the web the
/// engine starts it at the first key or tap, as browsers require: sources
/// and streams wait for it, and a one-shot asked for before then is let go
/// unplayed.
///
/// Add to your [World]:
/// ```dart
/// world.addSystem(AudioSystem(engine: myAudioEngine));
/// ```
class AudioSystem extends System implements FrameSystem {
  /// A system playing through [engine], which it does not own or dispose.
  /// A listener can hear from [camera] (see [AudioListenerComponent]).
  AudioSystem({required AudioEngine engine, this.camera}) : _engine = engine;

  final AudioEngine _engine;

  /// The camera a listener can hear from; with no listener at all, the
  /// one that hears.
  final GameCamera? camera;

  final Matrix4 _view = Matrix4.identity();
  final Matrix4 _pose = Matrix4.identity();
  final Quaternion _rotation = Quaternion.identity();
  final Vector3 _axis = Vector3.zero();

  static const List<Type> _sourceQuery = [AudioSourceComponent];
  static const List<Type> _streamQuery = [AudioStreamComponent];
  static const List<Type> _listenerQuery = [AudioListenerComponent];

  @override
  List<Type> get requiredComponents => _sourceQuery;

  @override
  int get priority => SystemPriorities.audio;

  /// The sources and streams playing — or still starting — with their
  /// entities and why they are paused.
  final Map<AudioSourceComponent, _Playback> _sources = {};
  final Map<AudioStreamComponent, _Playback> _streams = {};

  /// Which sources and streams this system has started (or that [AudioRequests.stop]
  /// kept from starting), as the [_generation] it did so in: `playOnAdd`
  /// starts a sound once, and the component's saved fields are never
  /// changed for it — an editor saving the scene saves what was authored.
  final Expando<int> _begun = Expando('audio begun');

  /// Sounds a [AudioRequests.play] stopped while their entity was switched
  /// off, to start from the beginning once it is back on.
  final Expando<int> _startWhenOn = Expando('audio start when on');

  /// Moves on in [stopAll], so every `playOnAdd` sound starts again when the
  /// system next runs.
  int _generation = 0;

  bool _hasBegun(Object component) => _begun[component] == _generation;
  void _markBegun(Object component) => _begun[component] = _generation;

  /// Whether a [AudioRequests.play] made while [component]'s entity was off
  /// waits for it, which this consumes.
  bool _takeStartWhenOn(Object component) {
    if (_startWhenOn[component] != _generation) return false;
    _startWhenOn[component] = null;
    return true;
  }

  /// The sources and streams to stop at the end of an update; reused.
  final List<AudioSourceComponent> _stoppedSources = [];
  final List<AudioStreamComponent> _stoppedStreams = [];

  /// The one-shots asked for since the last update.
  final List<_OneShot> _oneShots = [];

  /// Counts the updates, so a sound the last one did not find is known.
  int _updates = 0;

  /// Whether [suspend] has paused everything, until [resumeSuspended].
  bool _suspended = false;

  @override
  void update(double deltaTime) {
    final now = ++_updates;
    _updateSources(now);
    _playOneShots();
    _updateStreams(now);
  }

  @override
  void frame(double deltaTime, double alpha) {
    _updateListener();
    _placeSources();
  }

  @override
  void onRemovedFromWorld() => stopAll();

  @override
  void dispose() => stopAll();

  /// Plays [clipPath] once, at the next [update]: a sound with nothing to
  /// control afterwards — a hit, a pickup, a timeline's cue. Nothing is
  /// added to an entity for it, so asking costs nothing.
  ///
  /// With [position] the sound is placed there in 3-D — where it is now; it
  /// does not follow — and heard by [spatial], and [pan] is not used.
  /// Without, it plays flat. To play it at an entity, pass the entity's
  /// position:
  ///
  /// ```dart
  /// world.getSystem<AudioSystem>()?.playOneShot(
  ///   'sounds/hit.wav',
  ///   position: entity.getComponent<TransformComponent>()?.position,
  /// );
  /// ```
  ///
  /// Asked for before the audio engine has started (on the web, before the
  /// first key or tap), the sound is let go unplayed; [stopAll] lets go of
  /// those not played yet.
  void playOneShot(
    String clipPath, {
    double volume = 1.0,
    double pan = 0.0,
    double pitch = 1.0,
    double speed = 1.0,
    AudioChannel channel = AudioChannel.sfx,
    Vector3? position,
    AudioSpatial spatial = const AudioSpatial(),
    List<AudioEffect> effects = const [],
  }) {
    _oneShots.add(
      _OneShot(
        clipPath: clipPath,
        volume: volume,
        pan: pan,
        pitch: pitch,
        speed: speed,
        channel: channel,
        position: position == null
            ? null
            : Audio3DPosition(position.x, position.y, position.z),
        spatial: spatial,
        effects: effects,
      ),
    );
  }

  /// Stops every sound and stream this system started — also those still
  /// loading — and lets go of the one-shots not played yet. It forgets what
  /// it started: a source or stream with `playOnAdd` plays again when the
  /// system next runs. An editor stops a play-test's sounds this way, and
  /// keeps the system from running while the scene is edited.
  void stopAll() {
    _generation++;
    _sources.forEach((source, playback) {
      if (playback.id case final String id) _engine.stopSfx(id);
      source.handle = null;
    });
    _sources.clear();
    _streams.forEach((stream, _) {
      stream.stream?.dispose();
      stream.stream = null;
    });
    _streams.clear();
    _oneShots.clear();
  }

  /// Pauses every sound and stream this system plays, for the app going to
  /// the background (`Engine.suspendAudio` calls it); one that starts
  /// before [resumeSuspended] starts paused.
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    _sources.forEach((_, playback) {
      final wasPaused = playback.paused;
      playback.suspended = true;
      if (!wasPaused) _pauseSource(playback, true);
    });
    _streams.forEach((stream, playback) {
      final wasPaused = playback.paused;
      playback.suspended = true;
      if (!wasPaused) _pauseStream(stream, true);
    });
  }

  /// Plays on what [suspend] paused — not what the game paused itself
  /// ([AudioRequests.pause]), nor what plays on a switched-off entity.
  void resumeSuspended() {
    if (!_suspended) return;
    _suspended = false;
    _sources.forEach((_, playback) {
      if (!playback.suspended) return;
      playback.suspended = false;
      if (!playback.paused) _pauseSource(playback, false);
    });
    _streams.forEach((stream, playback) {
      if (!playback.suspended) return;
      playback.suspended = false;
      if (!playback.paused) _pauseStream(stream, false);
    });
  }

  /// The listener pose last sent — position, forward, up — or null before
  /// the first. Sent again only when it changes: an unmoved listener used to
  /// cost three new objects and a native update every frame.
  List<double>? _sentListener;

  /// Where each 3-D source was last sent, and under which playback handle
  /// and settings.
  final Expando<_Sent> _sent = Expando('audio positions');

  void _updateListener() {
    AudioListenerComponent? listener;
    Entity? holder;
    for (final entity in world.query(_listenerQuery)) {
      holder = entity;
      listener = entity.getComponent<AudioListenerComponent>();
      break; // Only one listener.
    }
    final camera = this.camera;
    final transform = holder?.getComponent<TransformComponent>();
    // With no listener, the camera hears; a listener without a transform
    // takes from the camera whatever the transform would have given.
    final fromCamera = listener == null || transform == null;
    final atCamera = camera != null && (fromCamera || listener.atCamera);
    final faceCamera = camera != null && (fromCamera || listener.faceCamera);
    if (!atCamera && transform == null) return;

    double px, py, pz, fx, fy, fz, ux, uy, uz;
    if (atCamera || faceCamera) {
      // The view matrix is rigid: its inverse holds the camera's position,
      // its rows the camera's right, down and forward.
      camera.viewMatrixInto(_view);
      _pose.copyInverse(_view);
    }
    final m = _view.storage, q = _pose.storage;
    if (atCamera) {
      (px, py, pz) = (q[12], q[13], q[14]);
    } else {
      final p = transform!.position;
      (px, py, pz) = (p.x, p.y, p.z);
    }
    if (faceCamera) {
      (fx, fy, fz) = (m[2], m[6], m[10]);
      (ux, uy, uz) = (-m[1], -m[5], -m[9]);
    } else {
      // The entity's rotation turns the world's forward and up.
      transform!.rotationInto(_rotation);
      _axis.setValues(
        WorldAxes.forwardX,
        WorldAxes.forwardY,
        WorldAxes.forwardZ,
      );
      _rotation.rotate(_axis);
      (fx, fy, fz) = (_axis.x, _axis.y, _axis.z);
      _axis.setValues(WorldAxes.upX, WorldAxes.upY, WorldAxes.upZ);
      _rotation.rotate(_axis);
      (ux, uy, uz) = (_axis.x, _axis.y, _axis.z);
    }

    final sent = _sentListener ??= List<double>.filled(9, double.nan);
    if (sent[0] == px &&
        sent[1] == py &&
        sent[2] == pz &&
        sent[3] == fx &&
        sent[4] == fy &&
        sent[5] == fz &&
        sent[6] == ux &&
        sent[7] == uy &&
        sent[8] == uz) {
      return;
    }
    sent
      ..[0] = px
      ..[1] = py
      ..[2] = pz
      ..[3] = fx
      ..[4] = fy
      ..[5] = fz
      ..[6] = ux
      ..[7] = uy
      ..[8] = uz;
    _engine.setListener3D(
      Audio3DListener(
        position: Audio3DPosition(px, py, pz),
        forward: Audio3DPosition(fx, fy, fz),
        up: Audio3DPosition(ux, uy, uz),
      ),
    );
  }

  // ── Sources ───────────────────────────────────────────────────────────────

  void _updateSources(int now) {
    final ready = _engine.isInitialized;
    for (final entity in world.query(_sourceQuery)) {
      final audio = entity.getComponent<AudioSourceComponent>()!;
      var playback = _sources[audio];
      if (playback != null) {
        playback.seen = now;
        if (playback.whileOff) {
          // Switched back on: it plays on, unless paused for another reason.
          playback.whileOff = false;
          if (!playback.paused) _pauseSource(playback, false);
        }
      }
      if (!ready) {
        // Nothing plays yet; a stop still keeps it from starting, and the
        // rest waits until the audio engine can carry it out.
        if (audio.pendingRequest == AudioRequest.stop) {
          audio.takeRequest();
          _markBegun(audio);
        }
        continue;
      }
      var restart = _takeStartWhenOn(audio);
      switch (audio.takeRequest()) {
        case AudioRequest.play:
          if (playback != null) _stopSource(audio);
          playback = null;
          restart = true;
        case final AudioRequest request:
          playback = _requestSource(audio, playback, request);
        case null:
          break;
      }

      if (playback != null) {
        final id = playback.id;
        if (id == null) continue; // Still loading.
        if (_engine.isSfxPlaying(id)) {
          _followSource(audio, playback, id);
          continue;
        }
        // Played to its end, or taken to make room for another.
        audio.handle = null;
        _sources.remove(audio);
      }

      // playOnAdd plays it once; play() again, from the start.
      if (!restart && (!audio.playOnAdd || _hasBegun(audio))) continue;
      _markBegun(audio);
      _startSource(entity, audio, now);
    }

    // The sources this update did not find: gone, or switched off.
    for (final audio in _sources.keys) {
      final playback = _sources[audio]!;
      if (playback.seen == now) continue;
      final entity = playback.entity;
      if (!entity.isAlive ||
          !identical(entity.getComponent<AudioSourceComponent>(), audio)) {
        _stoppedSources.add(audio);
        continue;
      }
      // Switched off: it pauses, and what the game asks still counts.
      final request = audio.takeRequest();
      if (request == AudioRequest.stop) {
        _markBegun(audio);
        _stoppedSources.add(audio);
        continue;
      }
      if (request == AudioRequest.play) {
        // From the start, once its entity is back on.
        _stoppedSources.add(audio);
        _startWhenOn[audio] = _generation;
        continue;
      }
      final wasPaused = playback.paused;
      if (request != null) playback.byGame = request == AudioRequest.pause;
      playback.whileOff = true;
      if (!wasPaused) _pauseSource(playback, true);
    }
    for (final audio in _stoppedSources) {
      _stopSource(audio);
    }
    _stoppedSources.clear();
  }

  /// Carries out [request] for [audio], playing as [playback] (null when it
  /// is not); returns its playback afterwards.
  _Playback? _requestSource(
    AudioSourceComponent audio,
    _Playback? playback,
    AudioRequest request,
  ) {
    if (request == AudioRequest.stop) {
      // Stopped, and kept from starting (again) by playOnAdd.
      _markBegun(audio);
      if (playback != null) _stopSource(audio);
      return null;
    }
    // Nothing playing: nothing to pause or resume.
    if (playback == null) return null;
    final wasPaused = playback.paused;
    playback.byGame = request == AudioRequest.pause;
    if (playback.paused != wasPaused) _pauseSource(playback, playback.paused);
    return playback;
  }

  void _startSource(Entity entity, AudioSourceComponent audio, int now) {
    final transform = entity.getComponent<TransformComponent>();
    final pos = (audio.is3d && transform != null)
        ? Audio3DPosition(
            transform.position.x,
            transform.position.y,
            transform.position.z,
          )
        : null;
    final playback = _sources[audio] = _Playback(entity, audio.volume)
      ..seen = now
      ..suspended = _suspended;

    _engine
        .playSfx(
          audio.clipPath,
          volume: audio.volume,
          loop: audio.loop,
          // A sound placed in 3-D is panned by where it is.
          pan: pos == null ? audio.pan : 0.0,
          pitch: audio.pitch,
          speed: audio.speed,
          effects: audio.effects,
          position3d: pos,
          spatial: audio.spatial,
          channel: audio.channel,
        )
        .then((sfxId) {
          final current = identical(_sources[audio], playback);
          if (sfxId == null) {
            if (current) _sources.remove(audio);
            return;
          }
          // Stopped while it was loading — by stop(), stopAll(), the system
          // going — or its entity or component gone: it is not heard after
          // all.
          if (!current ||
              !entity.isAlive ||
              !identical(entity.getComponent<AudioSourceComponent>(), audio)) {
            _engine.stopSfx(sfxId);
            if (current) _sources.remove(audio);
            return;
          }
          playback.id = sfxId;
          audio.handle = sfxId;
          // Paused while it loaded: by the game, its entity switched off,
          // the app gone to the background.
          if (playback.paused) _engine.pauseSfx(sfxId);
        });
  }

  /// Applies what changed on a playing source: its volume.
  void _followSource(
    AudioSourceComponent audio,
    _Playback playback,
    String id,
  ) {
    if (audio.volume == playback.volume) return;
    playback.volume = audio.volume;
    _engine.setSfxVolume(id, audio.volume);
  }

  void _pauseSource(_Playback playback, bool pause) {
    final id = playback.id;
    if (id == null) return; // Paused as it starts.
    if (pause) {
      _engine.pauseSfx(id);
    } else {
      _engine.resumeSfx(id);
    }
  }

  void _stopSource(AudioSourceComponent audio) {
    final playback = _sources.remove(audio);
    if (playback?.id case final String id) _engine.stopSfx(id);
    audio.handle = null;
  }

  /// Follows moving 3-D sources — only those that moved, changed how they
  /// are heard, or started a new playback since they were last sent.
  void _placeSources() {
    for (final entity in world.query(_sourceQuery)) {
      final audio = entity.getComponent<AudioSourceComponent>()!;
      if (!audio.is3d) continue;
      final id = audio.handle;
      if (id is! String) continue;
      final transform = entity.getComponent<TransformComponent>();
      if (transform == null) continue;
      final p = transform.position;
      final sent = _sent[audio] ??= _Sent();
      final newPlayback = sent.id != id;
      if (newPlayback || !sent.hears(audio)) {
        if (!newPlayback) _engine.setSfxSpatial(id, audio.spatial);
        sent.remember(audio);
      }
      if (!newPlayback && sent.x == p.x && sent.y == p.y && sent.z == p.z) {
        continue;
      }
      sent
        ..id = id
        ..x = p.x
        ..y = p.y
        ..z = p.z;
      _engine.updateSfxPosition(id, Audio3DPosition(p.x, p.y, p.z));
    }
  }

  void _playOneShots() {
    if (_oneShots.isEmpty) return;
    if (_engine.isInitialized) {
      for (final shot in _oneShots) {
        _engine.playSfx(
          shot.clipPath,
          volume: shot.volume,
          // A sound placed in 3-D is panned by where it is.
          pan: shot.position == null ? shot.pan : 0.0,
          pitch: shot.pitch,
          speed: shot.speed,
          effects: shot.effects,
          position3d: shot.position,
          spatial: shot.spatial,
          channel: shot.channel,
        );
      }
    }
    _oneShots.clear();
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  void _updateStreams(int now) {
    final ready = _engine.isInitialized;
    for (final entity in world.query(_streamQuery)) {
      final comp = entity.getComponent<AudioStreamComponent>()!;
      var playback = _streams[comp];
      if (playback != null) {
        playback.seen = now;
        if (playback.whileOff) {
          playback.whileOff = false;
          if (!playback.paused) _pauseStream(comp, false);
        }
      }
      if (!ready) {
        if (comp.pendingRequest == AudioRequest.stop) {
          comp.takeRequest();
          _markBegun(comp);
        }
        continue;
      }
      var restart = _takeStartWhenOn(comp);
      switch (comp.takeRequest()) {
        case AudioRequest.play:
          if (playback != null) _stopStream(comp);
          playback = null;
          restart = true;
        case final AudioRequest request:
          playback = _requestStream(comp, playback, request);
        case null:
          break;
      }
      if (playback != null) {
        _followStream(comp, playback);
        continue;
      }

      // playOnAdd opens and starts it once; play() again, from the start.
      if (!restart && (!comp.playOnAdd || _hasBegun(comp))) continue;
      _markBegun(comp);
      _startStream(entity, comp, now);
    }

    // The streams this update did not find: gone, or switched off.
    for (final comp in _streams.keys) {
      final playback = _streams[comp]!;
      if (playback.seen == now) continue;
      final entity = playback.entity;
      if (!entity.isAlive ||
          !identical(entity.getComponent<AudioStreamComponent>(), comp)) {
        _stoppedStreams.add(comp);
        continue;
      }
      final request = comp.takeRequest();
      if (request == AudioRequest.stop) {
        _markBegun(comp);
        _stoppedStreams.add(comp);
        continue;
      }
      if (request == AudioRequest.play) {
        _stoppedStreams.add(comp);
        _startWhenOn[comp] = _generation;
        continue;
      }
      final wasPaused = playback.paused;
      if (request != null) playback.byGame = request == AudioRequest.pause;
      playback.whileOff = true;
      if (!wasPaused) _pauseStream(comp, true);
    }
    for (final comp in _stoppedStreams) {
      _stopStream(comp);
    }
    _stoppedStreams.clear();
  }

  _Playback? _requestStream(
    AudioStreamComponent comp,
    _Playback? playback,
    AudioRequest request,
  ) {
    if (request == AudioRequest.stop) {
      _markBegun(comp);
      if (playback != null) _stopStream(comp);
      return null;
    }
    if (playback == null) return null;
    final wasPaused = playback.paused;
    playback.byGame = request == AudioRequest.pause;
    if (playback.paused != wasPaused) _pauseStream(comp, playback.paused);
    return playback;
  }

  void _startStream(Entity entity, AudioStreamComponent comp, int now) {
    final stream = AudioStream(path: comp.path, channel: comp.channel);
    comp.stream = stream;
    final playback = _streams[comp] = _Playback(entity, comp.volume)
      ..seen = now
      ..suspended = _suspended;
    bool stopped() => !identical(_streams[comp], playback);
    final fadeIn = comp.fadeInDuration;
    final fades = fadeIn != null && fadeIn > Duration.zero;
    stream.open(_engine.backend).then((_) async {
      // Stopped while it opened: what it loaded is let go.
      if (stopped()) return stream.dispose();
      // A fade-in starts from silence.
      await stream.play(volume: fades ? 0.0 : comp.volume, loop: comp.loop);
      // Stopped while it started: disposing again stops the voice it made.
      if (stopped()) return stream.dispose();
      if (playback.paused) await stream.pause();
      if (fades) await stream.fade(comp.volume, fadeIn);
    });
  }

  /// Applies what changed on a playing stream: its volume.
  void _followStream(AudioStreamComponent comp, _Playback playback) {
    if (comp.volume == playback.volume) return;
    playback.volume = comp.volume;
    comp.stream?.setVolume(comp.volume);
  }

  void _pauseStream(AudioStreamComponent comp, bool pause) {
    final stream = comp.stream;
    if (stream == null) return;
    if (pause) {
      stream.pause();
    } else {
      stream.resume();
    }
  }

  void _stopStream(AudioStreamComponent comp) {
    _streams.remove(comp);
    comp.stream?.dispose();
    comp.stream = null;
  }
}

/// A sound the system plays, or is still starting: whose it is, and why it
/// is paused — it plays while none of the reasons holds.
class _Playback {
  _Playback(this.entity, this.volume);

  /// The entity the sound plays for.
  final Entity entity;

  /// A source's sound ID once it plays; null while it loads.
  String? id;

  /// The update that last found it; one that did not, found it gone or
  /// switched off.
  int seen = 0;

  /// The volume last sent.
  double volume;

  /// Paused by the game ([AudioRequests.pause]).
  bool byGame = false;

  /// Paused while its entity is switched off.
  bool whileOff = false;

  /// Paused while the app is in the background ([AudioSystem.suspend]).
  bool suspended = false;

  bool get paused => byGame || whileOff || suspended;
}

/// A one-shot asked for with [AudioSystem.playOneShot].
class _OneShot {
  _OneShot({
    required this.clipPath,
    required this.volume,
    required this.pan,
    required this.pitch,
    required this.speed,
    required this.channel,
    required this.position,
    required this.spatial,
    required this.effects,
  });

  final String clipPath;
  final double volume;
  final double pan;
  final double pitch;
  final double speed;
  final AudioChannel channel;
  final Audio3DPosition? position;
  final AudioSpatial spatial;
  final List<AudioEffect> effects;
}

/// A 3-D source as last sent to the audio engine: its playback, where it
/// was, and how it was heard.
class _Sent {
  String id = '';
  double x = 0;
  double y = 0;
  double z = 0;
  double minDistance = 0;
  double maxDistance = 0;
  AudioRolloff rolloff = AudioRolloff.inverse;
  double dopplerLevel = 0;
  double farCutoff = 0;

  /// Whether [audio] is still heard the way it was last sent.
  bool hears(AudioSourceComponent audio) =>
      audio.minDistance == minDistance &&
      audio.maxDistance == maxDistance &&
      audio.rolloff == rolloff &&
      audio.dopplerLevel == dopplerLevel &&
      audio.farCutoff == farCutoff;

  void remember(AudioSourceComponent audio) {
    minDistance = audio.minDistance;
    maxDistance = audio.maxDistance;
    rolloff = audio.rolloff;
    dopplerLevel = audio.dopplerLevel;
    farCutoff = audio.farCutoff;
  }
}
