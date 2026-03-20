part of '../asset_management.dart';

/// Audio asset (placeholder for audio data)
class AudioAsset extends Asset {
  Uint8List? _audioData;
  AudioFormat? _format;
  Duration? _duration;

  /// Get raw audio data
  Uint8List? get data => _audioData;

  /// Get audio format
  AudioFormat? get format => _format;

  /// Get audio duration
  Duration? get duration => _duration;

  /// Constructor
  AudioAsset(String path) : super(path, AssetType.audio);

  @override
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final cache = Engine.instance.cache;
      if (cache.isInitialized) {
        final cachedData = await cache.getBinary(path);
        if (cachedData != null) {
          _audioData = cachedData;
          _detectFormat();
          _isLoaded = true;
          return;
        }
      }

      // Load audio data from assets
      final data = await rootBundle.load(path);
      _audioData = data.buffer.asUint8List();

      if (cache.isInitialized) {
        await cache.setBinary(path, _audioData!);
      }

      _detectFormat();

      _isLoaded = true;
    } catch (e) {
      throw AssetLoadException('Failed to load audio asset: $path', e);
    }
  }

  void _detectFormat() {
    // Detect format from extension
    if (path.endsWith('.mp3')) {
      _format = AudioFormat.mp3;
    } else if (path.endsWith('.wav')) {
      _format = AudioFormat.wav;
    } else if (path.endsWith('.ogg')) {
      _format = AudioFormat.ogg;
    }
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
enum AudioFormat { mp3, wav, ogg, flac }
