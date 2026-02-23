/// Audio Engine
///
/// Integrates sound effects and music into the game environment.
/// This module manages audio playback and sound processing.
library;

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Audio channel types
enum AudioChannel { master, music, sfx, voice, ambient }

/// Audio playback state
enum AudioState { stopped, playing, paused }

/// Represents an audio clip
class AudioClip {
  final String id;
  final String path;
  final AudioChannel channel;
  final AudioPlayer player;
  AudioState state = AudioState.stopped;
  double volume = 1.0;
  bool loop = false;

  AudioClip({
    required this.id,
    required this.path,
    required this.channel,
    required this.player,
  });

  /// Play the audio clip
  Future<void> play() async {
    // audioplayers' AudioCache prepends 'assets/' internally, so we must
    // strip that prefix if the caller already included it to avoid
    // 'assets/assets/...' lookups that fail at PlatformAssetBundle.load.
    final assetPath = path.startsWith('assets/')
        ? path.substring('assets/'.length)
        : path;
    await player.play(AssetSource(assetPath));
    state = AudioState.playing;
  }

  /// Pause the audio clip
  Future<void> pause() async {
    await player.pause();
    state = AudioState.paused;
  }

  /// Resume the audio clip
  Future<void> resume() async {
    await player.resume();
    state = AudioState.playing;
  }

  /// Stop the audio clip
  Future<void> stop() async {
    await player.stop();
    state = AudioState.stopped;
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double vol) async {
    volume = vol.clamp(0.0, 1.0);
    await player.setVolume(volume);
  }

  /// Set looping
  Future<void> setLoop(bool shouldLoop) async {
    loop = shouldLoop;
    await player.setReleaseMode(
      shouldLoop ? ReleaseMode.loop : ReleaseMode.release,
    );
  }

  /// Dispose the audio clip
  void dispose() {
    player.dispose();
  }
}

/// Main audio engine class
class AudioEngine {
  /// Audio player pool for sound effects
  final List<AudioPlayer> _sfxPool = [];

  /// Active audio clips
  final Map<String, AudioClip> _activeClips = {};

  /// Music player
  AudioPlayer? _musicPlayer;
  AudioClip? _currentMusic;

  /// Volume levels for each channel
  final Map<AudioChannel, double> _channelVolumes = {
    AudioChannel.master: 1.0,
    AudioChannel.music: 1.0,
    AudioChannel.sfx: 1.0,
    AudioChannel.voice: 1.0,
    AudioChannel.ambient: 1.0,
  };

  /// Global mute state
  bool _isMuted = false;

  /// Get mute state
  bool get isMuted => _isMuted;

  /// Raw user-requested music volume (before channel/master scaling).
  /// Stored so _updateAllVolumes can re-apply scaling without compounding.
  double _rawMusicVolume = 1.0;

  /// SFX pool size
  static const int _sfxPoolSize = 10;

  /// Initialize the audio engine
  void initialize() {
    // AudioPlayers are created lazily on first use to avoid platform-channel
    // calls in environments where the plugin is not registered (e.g. tests).
    debugPrint('Audio Engine initialized');
  }

  /// Play a sound effect
  Future<String?> playSfx(
    String path, {
    double volume = 1.0,
    bool loop = false,
  }) async {
    try {
      // Get available player from pool
      final player = _getAvailableSfxPlayer();
      if (player == null) {
        debugPrint('No available SFX player in pool');
        return null;
      }

      final id = 'sfx_${DateTime.now().millisecondsSinceEpoch}';
      final clip = AudioClip(
        id: id,
        path: path,
        channel: AudioChannel.sfx,
        player: player,
      );

      await clip.setVolume(volume * _getEffectiveVolume(AudioChannel.sfx));
      await clip.setLoop(loop);
      await clip.play();

      _activeClips[id] = clip;

      // Auto-remove when complete (if not looping)
      if (!loop) {
        player.onPlayerComplete.listen((_) {
          _activeClips.remove(id);
        });
      }

      return id;
    } catch (e) {
      debugPrint('Error playing SFX: $e');
      return null;
    }
  }

  /// Play background music
  Future<void> playMusic(
    String path, {
    double volume = 1.0,
    bool loop = true,
    bool fadeIn = false,
    Duration fadeDuration = const Duration(seconds: 2),
  }) async {
    try {
      // Stop current music if playing
      if (_currentMusic != null) {
        await stopMusic(fadeOut: true);
      }

      _musicPlayer ??= AudioPlayer();

      // Store the raw volume so _updateAllVolumes can re-apply it correctly.
      _rawMusicVolume = volume;

      final clip = AudioClip(
        id: 'music',
        path: path,
        channel: AudioChannel.music,
        player: _musicPlayer!,
      );

      await clip.setLoop(loop);

      if (fadeIn) {
        await clip.setVolume(0.0);
        await clip.play();
        await _fadeVolume(
          clip,
          _rawMusicVolume * _getEffectiveVolume(AudioChannel.music),
          fadeDuration,
        );
      } else {
        await clip.setVolume(
          _rawMusicVolume * _getEffectiveVolume(AudioChannel.music),
        );
        await clip.play();
      }

      _currentMusic = clip;
    } catch (e) {
      debugPrint('Error playing music: $e');
    }
  }

  /// Pause music
  Future<void> pauseMusic() async {
    await _currentMusic?.pause();
  }

  /// Resume music
  Future<void> resumeMusic() async {
    await _currentMusic?.resume();
  }

  /// Stop music
  Future<void> stopMusic({
    bool fadeOut = false,
    Duration fadeDuration = const Duration(seconds: 1),
  }) async {
    if (_currentMusic == null) return;

    if (fadeOut) {
      await _fadeVolume(_currentMusic!, 0.0, fadeDuration);
    }

    await _currentMusic?.stop();
    _currentMusic = null;
  }

  /// Stop a specific sound effect
  Future<void> stopSfx(String id) async {
    final clip = _activeClips[id];
    if (clip != null) {
      await clip.stop();
      _activeClips.remove(id);
    }
  }

  /// Stop all sound effects
  Future<void> stopAllSfx() async {
    for (final clip in _activeClips.values.toList()) {
      await clip.stop();
    }
    _activeClips.clear();
  }

  /// Set master volume
  void setMasterVolume(double volume) {
    _channelVolumes[AudioChannel.master] = volume.clamp(0.0, 1.0);
    _updateAllVolumes();
  }

  /// Set channel volume
  void setChannelVolume(AudioChannel channel, double volume) {
    _channelVolumes[channel] = volume.clamp(0.0, 1.0);
    _updateAllVolumes();
  }

  /// Get channel volume
  double getChannelVolume(AudioChannel channel) {
    return _channelVolumes[channel] ?? 1.0;
  }

  /// Mute all audio
  void mute() {
    _isMuted = true;
    _updateAllVolumes();
  }

  /// Unmute all audio
  void unmute() {
    _isMuted = false;
    _updateAllVolumes();
  }

  /// Toggle mute
  void toggleMute() {
    _isMuted = !_isMuted;
    _updateAllVolumes();
  }

  /// Get available SFX player from pool (creates players lazily up to pool limit)
  AudioPlayer? _getAvailableSfxPlayer() {
    for (final player in _sfxPool) {
      if (player.state != PlayerState.playing) {
        return player;
      }
    }
    // Pool not full yet — create a new player lazily.
    if (_sfxPool.length < _sfxPoolSize) {
      final player = AudioPlayer();
      _sfxPool.add(player);
      return player;
    }
    return null;
  }

  /// Calculate effective volume for a channel
  double _getEffectiveVolume(AudioChannel channel) {
    if (_isMuted) return 0.0;

    final masterVol = _channelVolumes[AudioChannel.master] ?? 1.0;
    final channelVol = _channelVolumes[channel] ?? 1.0;
    return masterVol * channelVol;
  }

  /// Update all active clip volumes
  void _updateAllVolumes() {
    // Use the stored raw music volume to avoid compounding the scaling factor
    // on every call (which would silently drive the volume towards zero).
    if (_currentMusic != null) {
      _currentMusic!.setVolume(
        _rawMusicVolume * _getEffectiveVolume(AudioChannel.music),
      );
    }

    // For SFX, volume is managed per-clip at play time; we only need to handle
    // mute/unmute by zeroing or restoring via the effective-volume calculation.
    for (final clip in _activeClips.values) {
      clip.setVolume(clip.volume * (_isMuted ? 0.0 : 1.0));
    }
  }

  /// Fade volume over duration
  Future<void> _fadeVolume(
    AudioClip clip,
    double targetVolume,
    Duration duration,
  ) async {
    final steps = 20;
    final stepDuration = duration.inMilliseconds ~/ steps;
    final startVolume = clip.volume;
    final volumeDelta = targetVolume - startVolume;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final volume = startVolume + (volumeDelta * t);
      await clip.setVolume(volume);
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  /// Update audio processing
  void update() {
    // Clean up completed non-looping SFX
    _activeClips.removeWhere((key, clip) {
      if (!clip.loop && clip.state == AudioState.stopped) {
        return true;
      }
      return false;
    });
  }

  /// Clean up audio resources
  void dispose() {
    // Stop and dispose all active clips
    for (final clip in _activeClips.values) {
      clip.stop();
      clip.dispose();
    }
    _activeClips.clear();

    // Dispose music
    _currentMusic?.stop();
    _musicPlayer?.dispose();
    _musicPlayer = null;

    // Dispose SFX pool
    for (final player in _sfxPool) {
      player.dispose();
    }
    _sfxPool.clear();

    debugPrint('Audio Engine disposed');
  }
}

/// Sound effect manager (convenience wrapper)
class SoundEffectManager {
  final AudioEngine _engine;

  SoundEffectManager(this._engine);

  /// Play a sound effect
  Future<String?> play(String path, {double volume = 1.0, bool loop = false}) {
    return _engine.playSfx(path, volume: volume, loop: loop);
  }

  /// Stop a sound effect
  Future<void> stop(String id) {
    return _engine.stopSfx(id);
  }

  /// Stop all sound effects
  Future<void> stopAll() {
    return _engine.stopAllSfx();
  }

  /// Set SFX channel volume
  void setVolume(double volume) {
    _engine.setChannelVolume(AudioChannel.sfx, volume);
  }
}

/// Music manager (convenience wrapper)
class MusicManager {
  final AudioEngine _engine;

  MusicManager(this._engine);

  /// Play music
  Future<void> play(
    String path, {
    double volume = 1.0,
    bool loop = true,
    bool fadeIn = false,
  }) {
    return _engine.playMusic(path, volume: volume, loop: loop, fadeIn: fadeIn);
  }

  /// Pause music
  Future<void> pause() {
    return _engine.pauseMusic();
  }

  /// Resume music
  Future<void> resume() {
    return _engine.resumeMusic();
  }

  /// Stop music
  Future<void> stop({bool fadeOut = false}) {
    return _engine.stopMusic(fadeOut: fadeOut);
  }

  /// Set music channel volume
  void setVolume(double volume) {
    _engine.setChannelVolume(AudioChannel.music, volume);
  }
}

/// Audio mixer for volume control
class AudioMixer {
  final AudioEngine _engine;

  AudioMixer(this._engine);

  /// Set master volume
  void setMasterVolume(double volume) {
    _engine.setMasterVolume(volume);
  }

  /// Set channel volume
  void setChannelVolume(AudioChannel channel, double volume) {
    _engine.setChannelVolume(channel, volume);
  }

  /// Get channel volume
  double getChannelVolume(AudioChannel channel) {
    return _engine.getChannelVolume(channel);
  }

  /// Mute all audio
  void mute() {
    _engine.mute();
  }

  /// Unmute all audio
  void unmute() {
    _engine.unmute();
  }

  /// Toggle mute
  void toggleMute() {
    _engine.toggleMute();
  }

  /// Check if muted
  bool get isMuted => _engine.isMuted;
}
