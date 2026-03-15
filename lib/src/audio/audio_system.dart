/// Audio ECS System
///
/// System that drives audio playback from ECS entities.
library;

import 'package:flutter_soloud/flutter_soloud.dart';

import '../ecs/ecs.dart';
import '../ecs/components.dart';
import 'audio_components.dart';

/// System that drives audio playback from ECS entities.
///
/// Processes three component types:
/// - [AudioSourceComponent]: loads sources, manages playback lifecycle,
///   and updates 3D position from [TransformComponent].
/// - [AudioPlayComponent]: one-shot fire-and-forget triggers (removed after play).
/// - [AudioListenerComponent]: updates the native listener from
///   the entity's [TransformComponent].
///
/// Add to your [World]:
/// ```dart
/// world.addSystem(AudioSystem());
/// ```
class AudioSystem extends System {
  @override
  List<Type> get requiredComponents => [AudioSourceComponent];

  @override
  int get priority => -10; // Run late so transforms are up to date.

  final SoLoud _engine = SoLoud.instance;

  @override
  void update(double deltaTime) {
    // ── Listener ──────────────────────────────────────────────────────
    _updateListener();

    // ── Persistent audio sources ─────────────────────────────────────
    _updateSources();

    // ── One-shot play triggers ───────────────────────────────────────
    _processPlayTriggers();
  }

  void _updateListener() {
    for (final entity in world.query([
      AudioListenerComponent,
      TransformComponent,
    ])) {
      final listenerComp = entity.getComponent<AudioListenerComponent>()!;
      final transform = entity.getComponent<TransformComponent>()!;
      _engine.set3dListenerParameters(
        transform.position.dx,
        transform.position.dy,
        0,
        listenerComp.forwardX,
        listenerComp.forwardY,
        listenerComp.forwardZ,
        listenerComp.upX,
        listenerComp.upY,
        listenerComp.upZ,
        0,
        0,
        0,
      );
      break; // Only one listener.
    }
  }

  void _updateSources() {
    forEach((entity) {
      final audio = entity.getComponent<AudioSourceComponent>()!;

      // Lazy-load the source.
      if (audio.loadedSource == null) {
        _engine.loadAsset(audio.clipPath).then((source) {
          audio.loadedSource = source;
        });
        return;
      }

      // Auto-play on first frame if requested.
      if (audio.playOnAdd &&
          audio.handle == null &&
          audio.loadedSource != null) {
        final source = audio.loadedSource! as AudioSource;
        final transform = entity.getComponent<TransformComponent>();
        if (audio.is3d && transform != null) {
          _engine
              .play3d(
                source,
                transform.position.dx,
                transform.position.dy,
                0,
                volume: audio.volume,
                looping: audio.loop,
              )
              .then((handle) {
                audio.handle = handle;
              });
        } else {
          _engine
              .play(
                source,
                volume: audio.volume,
                pan: audio.pan,
                looping: audio.loop,
              )
              .then((handle) {
                audio.handle = handle;
              });
        }
        audio.playOnAdd = false;
      }

      // Update 3D position if the voice is still active.
      if (audio.is3d && audio.handle != null) {
        final handle = audio.handle! as SoundHandle;
        final transform = entity.getComponent<TransformComponent>();
        if (transform != null && _engine.getIsValidVoiceHandle(handle)) {
          _engine.set3dSourcePosition(
            handle,
            transform.position.dx,
            transform.position.dy,
            0,
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

      _engine.loadAsset(play.clipPath).then((source) {
        if (play.is3d && transform != null) {
          _engine.play3d(
            source,
            transform.position.dx,
            transform.position.dy,
            0,
            volume: play.volume,
          );
        } else {
          _engine.play(source, volume: play.volume, pan: play.pan);
        }
      });

      toRemove.add(entity);
    }
    for (final entity in toRemove) {
      entity.removeComponent<AudioPlayComponent>();
    }
  }
}
