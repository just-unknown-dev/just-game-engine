part of '../asset_management.dart';

/// Audio asset (placeholder for audio data)
///
/// Read straight from the asset bundle and kept in memory by [AssetManager]
/// until unloaded — never copied into the engine's persistent cache.
class AudioAsset extends Asset {
  Uint8List? _audioData;
  AudioFormat? _format;
  Duration? _duration;

  /// Get raw audio data
  Uint8List? get data => _audioData;

  /// The format its path's extension names, any case; null for an
  /// extension that is none of [AudioFormat]'s.
  AudioFormat? get format => _format;

  /// The clip's length. Not worked out yet — the data is not decoded — so
  /// always null.
  Duration? get duration => _duration;

  /// Constructor
  AudioAsset(String path) : super(path, AssetType.audio);

  @override
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final data = await _bundle.load(path);
      _audioData = _bytesOf(data);
      _detectFormat();
      _isLoaded = true;
    } catch (e, stack) {
      Error.throwWithStackTrace(
        AssetLoadException('Failed to load audio asset: $path', e),
        stack,
      );
    }
  }

  void _detectFormat() {
    final lower = path.toLowerCase();
    _format = switch (lower) {
      _ when lower.endsWith('.mp3') => AudioFormat.mp3,
      _ when lower.endsWith('.wav') => AudioFormat.wav,
      _ when lower.endsWith('.ogg') => AudioFormat.ogg,
      _ when lower.endsWith('.flac') => AudioFormat.flac,
      _ => null,
    };
  }

  @override
  void unload() {
    _audioData = null;
    _format = null;
    _duration = null;
    _isLoaded = false;
  }

  @override
  int getMemoryUsage() {
    return _audioData?.length ?? 0;
  }
}

/// Audio format types
///
/// An [AudioAsset] tells its format from its path's extension.
enum AudioFormat {
  /// MPEG audio layer III (`.mp3`).
  mp3,

  /// Waveform audio (`.wav`).
  wav,

  /// Ogg-contained audio, usually Vorbis (`.ogg`).
  ogg,

  /// Free Lossless Audio Codec (`.flac`).
  flac,
}
