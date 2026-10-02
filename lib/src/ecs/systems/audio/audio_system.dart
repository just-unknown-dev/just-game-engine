/// Audio ECS System
///
/// System that drives audio playback from ECS entities.
library;

import '../../../subsystems/audio/audio.dart';
import '../../ecs.dart';
import '../../components/components.dart';
import '../../base/system_priorities.dart';

/// System that drives audio playback from ECS entities.
///
/// Processes the following component types:
/// - [AudioSourceComponent]: loads sources, manages playback lifecycle,
///   and updates 3D position from [TransformComponent]. Supports pitch,
///   speed, and DSP [AudioEffect] passes.
/// - [AudioPlayComponent]: one-shot fire-and-forget triggers (removed after play).
/// - [AudioPauseComponent]: pauses the entity's active [AudioSourceComponent].
/// - [AudioResumeComponent]: resumes the entity's paused [AudioSourceComponent].
/// - [AudioStopComponent]: stops the entity's active [AudioSourceComponent].
/// - [AudioStreamComponent]: opens and drives an [AudioStream] for large files.
/// - [AudioListenerComponent]: updates the native listener from
///   the entity's [TransformComponent].
///
/// Add to your [World]:
/// ```dart
/// world.addSystem(AudioSystem(engine: myAudioEngine));
/// ```
class AudioSystem extends System {
  /// A system playing through [engine], which it does not own or dispose.
  AudioSystem({required AudioEngine engine}) : _engine = engine;

  final AudioEngine _engine;

  @override
  List<Type> get requiredComponents => [AudioSourceComponent];

  @override
  int get priority => SystemPriorities.audio;

  @override
  void update(double deltaTime) {
    _updateListener();
    _updateSources();
    _processPlayTriggers();
    _processPauseTriggers();
    _processResumeTriggers();
    _processStopTriggers();
    _updateStreams();
  }

  /// The listener pose last sent — position, forward, up — or null before
  /// the first. Sent again only when it changes: an unmoved listener used to
  /// cost three new objects and a native update every frame.
  List<double>? _sentListener;

  /// Where each 3-D source was last sent, and under which playback handle.
  final Expando<_SentPosition> _sentPositions = Expando('audio positions');

  void _updateListener() {
    for (final entity in world.query([
      AudioListenerComponent,
      TransformComponent,
    ])) {
      final listenerComp = entity.getComponent<AudioListenerComponent>()!;
      final transform = entity.getComponent<TransformComponent>()!;
      final p = transform.position;
      final sent = _sentListener ??= List<double>.filled(9, double.nan);
      if (sent[0] == p.x &&
          sent[1] == p.y &&
          sent[2] == p.z &&
          sent[3] == listenerComp.forwardX &&
          sent[4] == listenerComp.forwardY &&
          sent[5] == listenerComp.forwardZ &&
          sent[6] == listenerComp.upX &&
          sent[7] == listenerComp.upY &&
          sent[8] == listenerComp.upZ) {
        break;
      }
      sent
        ..[0] = p.x
        ..[1] = p.y
        ..[2] = p.z
        ..[3] = listenerComp.forwardX
        ..[4] = listenerComp.forwardY
        ..[5] = listenerComp.forwardZ
        ..[6] = listenerComp.upX
        ..[7] = listenerComp.upY
        ..[8] = listenerComp.upZ;
      _engine.setListener3D(
        Audio3DListener(
          position: Audio3DPosition(p.x, p.y, p.z),
          forward: Audio3DPosition(
            listenerComp.forwardX,
            listenerComp.forwardY,
            listenerComp.forwardZ,
          ),
          up: Audio3DPosition(
            listenerComp.upX,
            listenerComp.upY,
            listenerComp.upZ,
          ),
        ),
      );
      break; // Only one listener.
    }
  }

  void _updateSources() {
    forEach((entity) {
      final audio = entity.getComponent<AudioSourceComponent>()!;

      // Lazy-start: play once on first frame.
      if (audio.handle == null && audio.playOnAdd) {
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
            )
            .then((sfxId) {
              audio.handle = sfxId;
            });

        audio.playOnAdd = false;
        return;
      }

      // Follow moving sources — only when they have moved, or started a new
      // playback, since the position was last sent.
      if (!audio.is3d) return;
      final id = audio.handle;
      if (id is! String) return;
      final transform = entity.getComponent<TransformComponent>();
      if (transform == null) return;
      final p = transform.position;
      final sent = _sentPositions[audio];
      if (sent != null &&
          sent.id == id &&
          sent.x == p.x &&
          sent.y == p.y &&
          sent.z == p.z) {
        return;
      }
      _sentPositions[audio] = (sent ?? _SentPosition())
        ..id = id
        ..x = p.x
        ..y = p.y
        ..z = p.z;
      _engine.updateSfxPosition(id, Audio3DPosition(p.x, p.y, p.z));
    });
  }

  void _processPlayTriggers() {
    final toRemove = <Entity>[];
    for (final entity in world.query([AudioPlayComponent])) {
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
      );
      toRemove.add(entity);
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
      }
      toRemove.add(entity);
    }
    for (final entity in toRemove) {
      entity.removeComponent<AudioStopComponent>();
    }
  }

  void _updateStreams() {
    for (final entity in world.query([AudioStreamComponent])) {
      final comp = entity.getComponent<AudioStreamComponent>()!;

      // Open and start the stream on the first frame.
      if (comp.stream == null && comp.playOnAdd) {
        final stream = AudioStream(path: comp.path, channel: comp.channel);
        comp.stream = stream;
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

/// A 3-D source's position as last sent to the audio engine.
class _SentPosition {
  String id = '';
  double x = 0;
  double y = 0;
  double z = 0;
}
