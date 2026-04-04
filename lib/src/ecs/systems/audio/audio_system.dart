/// Audio ECS System
///
/// System that drives audio playback from ECS entities.
library;

import '../../../subsystems/audio/audio.dart';
import '../../ecs.dart';
import '../../components/components.dart';
import '../system_priorities.dart';

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

  void _updateListener() {
    for (final entity in world.query([
      AudioListenerComponent,
      TransformComponent,
    ])) {
      final listenerComp = entity.getComponent<AudioListenerComponent>()!;
      final transform = entity.getComponent<TransformComponent>()!;
      _engine.setListener3D(
        Audio3DListener(
          position: Audio3DPosition(
            transform.position.dx,
            transform.position.dy,
            0,
          ),
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
            ? Audio3DPosition(transform.position.dx, transform.position.dy, 0)
            : null;

        _engine
            .playSfx(
              audio.clipPath,
              volume: audio.volume,
              loop: audio.loop,
              pan: audio.pan,
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

      // Update 3D position every frame for moving sources.
      if (audio.is3d && audio.handle != null) {
        final transform = entity.getComponent<TransformComponent>();
        if (transform != null) {
          _engine.updateSfxPosition(
            audio.handle! as String,
            Audio3DPosition(transform.position.dx, transform.position.dy, 0),
          );
        }
      }
    });
  }

  void _processPlayTriggers() {
    final toRemove = <Entity>[];
    for (final entity in world.query([AudioPlayComponent])) {
      final play = entity.getComponent<AudioPlayComponent>()!;
      final transform = entity.getComponent<TransformComponent>();

      final pos = (play.is3d && transform != null)
          ? Audio3DPosition(transform.position.dx, transform.position.dy, 0)
          : null;

      _engine.playSfx(
        play.clipPath,
        volume: play.volume,
        pan: play.pan,
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
        stream.open(_engine.backend).then((_) async {
          await stream.play(volume: comp.volume, loop: comp.loop);
          if (comp.fadeInDuration != null) {
            await stream.fade(comp.volume, comp.fadeInDuration!);
          }
        });
        comp.playOnAdd = false;
      }
    }
  }
}
