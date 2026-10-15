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
///   Supports pitch, speed, and DSP [AudioEffect] passes. The sound stops
///   when the component or its entity goes; when it plays to its end, its
///   `handle` goes back to null.
/// - [AudioPlayComponent]: one-shot fire-and-forget triggers (removed after play).
/// - [AudioPauseComponent]: pauses the entity's active [AudioSourceComponent].
/// - [AudioResumeComponent]: resumes the entity's paused [AudioSourceComponent].
/// - [AudioStopComponent]: stops the entity's active [AudioSourceComponent].
/// - [AudioStreamComponent]: opens and drives an [AudioStream] for large files.
/// - [AudioListenerComponent]: where 3-D sounds are heard from — with none,
///   the [camera].
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

  @override
  List<Type> get requiredComponents => [AudioSourceComponent];

  @override
  int get priority => SystemPriorities.audio;

  /// The sources and streams playing, with their entities: when the world
  /// changes shape, the ones whose component or entity has gone are
  /// stopped.
  final Map<AudioSourceComponent, Entity> _sources = {};
  final Map<AudioStreamComponent, Entity> _streams = {};
  int _seenStructure = -1;

  @override
  void update(double deltaTime) {
    _stopOrphans();
    _startSources();
    _processPlayTriggers();
    _processPauseTriggers();
    _processResumeTriggers();
    _processStopTriggers();
    _updateStreams();
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
    for (final entity in world.query([AudioListenerComponent])) {
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

  /// Stops what plays for a component or entity that has gone.
  void _stopOrphans() {
    final version = world.structureVersion;
    if (version == _seenStructure) return;
    _seenStructure = version;
    _sources.removeWhere((source, entity) {
      if (entity.isAlive &&
          identical(entity.getComponent<AudioSourceComponent>(), source)) {
        return false;
      }
      if (source.handle case final String id) _engine.stopSfx(id);
      source.handle = null;
      return true;
    });
    _streams.removeWhere((stream, entity) {
      if (entity.isAlive &&
          identical(entity.getComponent<AudioStreamComponent>(), stream)) {
        return false;
      }
      stream.stream?.dispose();
      stream.stream = null;
      return true;
    });
  }

  /// Stops every sound and stream this system started. A source with
  /// `playOnAdd` still set plays again when the system next runs: an editor
  /// stops a play-test's sounds this way, and keeps the system from running
  /// while the scene is edited.
  void stopAll() {
    for (final source in _sources.keys) {
      if (source.handle case final String id) _engine.stopSfx(id);
      source.handle = null;
    }
    _sources.clear();
    for (final stream in _streams.keys) {
      stream.stream?.dispose();
      stream.stream = null;
    }
    _streams.clear();
  }

  void _startSources() {
    if (!_engine.isInitialized) return;
    forEach((entity) {
      final audio = entity.getComponent<AudioSourceComponent>()!;
      if (audio.handle case final String id) {
        if (_engine.isSfxPlaying(id)) {
          _sources[audio] = entity;
          return;
        }
        // Played to its end, or taken to make room for another.
        audio.handle = null;
        _sources.remove(audio);
      }

      // Lazy-start: play once on first frame.
      if (!audio.playOnAdd) return;
      audio.playOnAdd = false;
      final transform = entity.getComponent<TransformComponent>();
      final pos = (audio.is3d && transform != null)
          ? Audio3DPosition(
              transform.position.x,
              transform.position.y,
              transform.position.z,
            )
          : null;

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
            if (sfxId == null) return;
            // Gone while it was loading: it is not heard after all.
            if (!entity.isAlive ||
                !identical(
                  entity.getComponent<AudioSourceComponent>(),
                  audio,
                )) {
              _engine.stopSfx(sfxId);
              return;
            }
            audio.handle = sfxId;
            _sources[audio] = entity;
          });
    });
  }

  /// Follows moving 3-D sources — only those that moved, changed how they
  /// are heard, or started a new playback since they were last sent.
  void _placeSources() {
    forEach((entity) {
      final audio = entity.getComponent<AudioSourceComponent>()!;
      if (!audio.is3d) return;
      final id = audio.handle;
      if (id is! String) return;
      final transform = entity.getComponent<TransformComponent>();
      if (transform == null) return;
      final p = transform.position;
      final sent = _sent[audio] ??= _Sent();
      final newPlayback = sent.id != id;
      if (newPlayback || !sent.hears(audio)) {
        if (!newPlayback) _engine.setSfxSpatial(id, audio.spatial);
        sent.remember(audio);
      }
      if (!newPlayback && sent.x == p.x && sent.y == p.y && sent.z == p.z) {
        return;
      }
      sent
        ..id = id
        ..x = p.x
        ..y = p.y
        ..z = p.z;
      _engine.updateSfxPosition(id, Audio3DPosition(p.x, p.y, p.z));
    });
  }

  void _processPlayTriggers() {
    final toRemove = <Entity>[];
    final ready = _engine.isInitialized;
    for (final entity in world.query([AudioPlayComponent])) {
      toRemove.add(entity);
      if (!ready) continue;
      final play = entity.getComponent<AudioPlayComponent>()!;
      final transform = entity.getComponent<TransformComponent>();

      final pos = (play.is3d && transform != null)
          ? Audio3DPosition(
              transform.position.x,
              transform.position.y,
              transform.position.z,
            )
          : null;

      _engine.playSfx(
        play.clipPath,
        volume: play.volume,
        pan: pos == null ? play.pan : 0.0,
        pitch: play.pitch,
        speed: play.speed,
        effects: play.effects,
        position3d: pos,
        spatial: play.spatial,
        channel: play.channel,
      );
    }
    for (final entity in toRemove) {
      entity.removeComponent<AudioPlayComponent>();
    }
  }

  void _processPauseTriggers() {
    final toRemove = <Entity>[];
    for (final entity in world.query([
      AudioPauseComponent,
      AudioSourceComponent,
    ])) {
      final audio = entity.getComponent<AudioSourceComponent>()!;
      if (audio.handle case final String id) {
        _engine.pauseSfx(id);
      }
      toRemove.add(entity);
    }
    for (final entity in toRemove) {
      entity.removeComponent<AudioPauseComponent>();
    }
  }

  void _processResumeTriggers() {
    final toRemove = <Entity>[];
    for (final entity in world.query([
      AudioResumeComponent,
      AudioSourceComponent,
    ])) {
      final audio = entity.getComponent<AudioSourceComponent>()!;
      if (audio.handle case final String id) {
        _engine.resumeSfx(id);
      }
      toRemove.add(entity);
    }
    for (final entity in toRemove) {
      entity.removeComponent<AudioResumeComponent>();
    }
  }

  void _processStopTriggers() {
    final toRemove = <Entity>[];
    for (final entity in world.query([
      AudioStopComponent,
      AudioSourceComponent,
    ])) {
      final audio = entity.getComponent<AudioSourceComponent>()!;
      if (audio.handle case final String id) {
        _engine.stopSfx(id);
        audio.handle = null;
        _sources.remove(audio);
      }
      toRemove.add(entity);
    }
    for (final entity in toRemove) {
      entity.removeComponent<AudioStopComponent>();
    }
  }

  void _updateStreams() {
    if (!_engine.isInitialized) return;
    for (final entity in world.query([AudioStreamComponent])) {
      final comp = entity.getComponent<AudioStreamComponent>()!;

      // Open and start the stream on the first frame.
      if (comp.stream == null && comp.playOnAdd) {
        final stream = AudioStream(path: comp.path, channel: comp.channel);
        comp.stream = stream;
        _streams[comp] = entity;
        final fadeIn = comp.fadeInDuration;
        final fades = fadeIn != null && fadeIn > Duration.zero;
        stream.open(_engine.backend).then((_) async {
          // A fade-in starts from silence.
          await stream.play(volume: fades ? 0.0 : comp.volume, loop: comp.loop);
          if (fades) await stream.fade(comp.volume, fadeIn);
        });
        comp.playOnAdd = false;
      }
    }
  }
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
