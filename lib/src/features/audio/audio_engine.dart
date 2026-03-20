/// Audio Engine
///
/// Integrates sound effects and music into the game environment.
/// This module manages audio playback and sound processing.
///
/// Backed by the flutter_soloud package (SoLoud + Miniaudio) via FFI.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'soloud_web_loader.dart'
    if (dart.library.js_interop) 'soloud_web_loader_web.dart';

/// Audio channel types
enum AudioChannel { master, music, sfx, voice, ambient }

/// Audio playback state
enum AudioState { stopped, playing, paused }

/// Represents an audio clip
class AudioClip {
  final String id;
  final String path;
  final AudioChannel channel;
  AudioSource? _source;
  SoundHandle? _handle;
  AudioState state = AudioState.stopped;
  double volume = 1.0;
  bool loop = false;

  AudioClip({required this.id, required this.path, required this.channel});

  final SoLoud _engine = SoLoud.instance;

  /// Play the audio clip
  Future<void> play() async {
    _source ??= await _engine.loadAsset(path);
    _handle = await _engine.play(_source!, volume: volume, looping: loop);
    state = AudioState.playing;
  }

  /// Pause the audio clip
  Future<void> pause() async {
    if (_handle != null && _engine.getIsValidVoiceHandle(_handle!)) {
      _engine.setPause(_handle!, true);
      state = AudioState.paused;
    }
  }

  /// Resume the audio clip
  Future<void> resume() async {
    if (_handle != null && _engine.getIsValidVoiceHandle(_handle!)) {
      _engine.setPause(_handle!, false);
      state = AudioState.playing;
    }
  }

  /// Stop the audio clip
  Future<void> stop() async {
    if (_handle != null && _engine.getIsValidVoiceHandle(_handle!)) {
      await _engine.stop(_handle!);
    }
    _handle = null;
    state = AudioState.stopped;
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double vol) async {
    volume = vol.clamp(0.0, 1.0);
    if (_handle != null && _engine.getIsValidVoiceHandle(_handle!)) {
      _engine.setVolume(_handle!, volume);
    }
  }

  /// Set looping
  Future<void> setLoop(bool shouldLoop) async {
    loop = shouldLoop;
    if (_handle != null && _engine.getIsValidVoiceHandle(_handle!)) {
      _engine.setLooping(_handle!, shouldLoop);
    }
  }

  /// Returns true when the underlying voice is still active.
  bool get isPlaying =>
      _handle != null && _engine.getIsValidVoiceHandle(_handle!);

  /// Dispose the audio clip
  Future<void> dispose() async {
    if (_handle != null && _engine.getIsValidVoiceHandle(_handle!)) {
      await _engine.stop(_handle!);
    }
    _handle = null;
    if (_source != null) {
      await _engine.disposeSource(_source!);
      _source = null;
    }
  }
}

/// Main audio engine class
class AudioEngine {
  /// Whether the native SoLoud engine has been successfully initialized.
  bool _initialized = false;

  /// Cached audio sources keyed by normalised asset path (for SFX reuse)
  final Map<String, AudioSource> _sfxSources = {};

  /// Active audio clips (tracked SFX)
  final Map<String, AudioClip> _activeClips = {};

  /// Current music clip
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
  double _rawMusicVolume = 1.0;

  final SoLoud _native = SoLoud.instance;

  /// Initialize the audio engine
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  /// Lazily initializes SoLoud. Safe to call multiple times.
  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    try {
      await loadSoLoudWeb();
      await _native.init();
      _initialized = true;
      debugPrint('AudioEngine: SoLoud initialized successfully');
      return true;
    } catch (e) {
      debugPrint('AudioEngine: failed to initialize SoLoud: $e');
      return false;
    }
  }

  /// Play a sound effect
  Future<String?> playSfx(
    String path, {
    double volume = 1.0,
    bool loop = false,
  }) async {
    if (!await _ensureInitialized()) {
      debugPrint('AudioEngine: cannot playSfx — engine not initialized');
      return null;
    }
    try {
      final assetPath = path.startsWith('assets/') ? path : 'assets/$path';

      _sfxSources[assetPath] ??= await _native.loadAsset(assetPath);
      final source = _sfxSources[assetPath]!;

      final effectiveVolume = volume * _getEffectiveVolume(AudioChannel.sfx);
      final handle = await _native.play(
        source,
        volume: effectiveVolume,
        looping: loop,
      );

      final id = 'sfx_${DateTime.now().millisecondsSinceEpoch}';
      final clip = AudioClip(id: id, path: path, channel: AudioChannel.sfx);
      clip._source = source;
      clip._handle = handle;
      clip.volume = effectiveVolume;
      clip.loop = loop;
      clip.state = AudioState.playing;

      _activeClips[id] = clip;
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
    if (!await _ensureInitialized()) {
      debugPrint('AudioEngine: cannot playMusic — engine not initialized');
      return;
    }
    try {
      if (_currentMusic != null) {
        await stopMusic(fadeOut: true);
      }

      _rawMusicVolume = volume;

      final clip = AudioClip(
        id: 'music',
        path: path,
        channel: AudioChannel.music,
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

      // Protect music from being auto-killed when max voices reached.
      if (clip._handle != null) {
        _native.setProtectVoice(clip._handle!, true);
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

  /// Calculate effective volume for a channel
  double _getEffectiveVolume(AudioChannel channel) {
    if (_isMuted) return 0.0;

    final masterVol = _channelVolumes[AudioChannel.master] ?? 1.0;
    final channelVol = _channelVolumes[channel] ?? 1.0;
    return masterVol * channelVol;
  }

  /// Update all active clip volumes
  void _updateAllVolumes() {
    if (_currentMusic != null) {
      _currentMusic!.setVolume(
        _rawMusicVolume * _getEffectiveVolume(AudioChannel.music),
      );
    }

    for (final clip in _activeClips.values) {
      clip.setVolume(clip.volume * (_isMuted ? 0.0 : 1.0));
    }
  }

  /// Fade volume over duration.
  Future<void> _fadeVolume(
    AudioClip clip,
    double targetVolume,
    Duration duration,
  ) async {
    if (clip._handle != null && _native.getIsValidVoiceHandle(clip._handle!)) {
      _native.fadeVolume(clip._handle!, targetVolume, duration);
      await Future.delayed(duration);
      clip.volume = targetVolume;
    }
  }

  /// Update audio processing — cleans up finished non-looping SFX.
  void update() {
    _activeClips.removeWhere((key, clip) {
      if (!clip.loop && !clip.isPlaying) {
        return true;
      }
      return false;
    });
  }

  /// Clean up audio resources
  void dispose() {
    for (final clip in _activeClips.values) {
      clip.stop();
      clip.dispose();
    }
    _activeClips.clear();

    _currentMusic?.stop();
    _currentMusic?.dispose();
    _currentMusic = null;

    _sfxSources.clear();

    if (_initialized) {
      try {
        _native.deinit();
      } catch (_) {
        // Native bindings may not be available (e.g. web).
      }
      _initialized = false;
    }
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
