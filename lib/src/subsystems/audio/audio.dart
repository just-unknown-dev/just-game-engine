/// Audio Engine
///
/// Integrates sound effects and music into the game environment.
/// This module manages audio playback and sound processing.
///
/// Backed by the just_audio package — native platform channels on
/// iOS/macOS (AVAudioEngine), Android (SoundPool/MediaPlayer),
/// Windows (XAudio2), Linux (OpenAL Soft), and Web Audio API on web.
///
/// Re-exports what `engine.audio`, `engine.music`, `engine.sfx` and the
/// audio components take and return. `createAudioBackend`, the platform
/// factory, is left in `package:just_audio_engine`.
library;

export 'package:just_audio_engine/just_audio_engine.dart'
    show
        Audio3DListener,
        Audio3DPosition,
        AudioBackend,
        AudioBus,
        AudioBusGraph,
        AudioChannel,
        AudioClip,
        AudioEffect,
        AudioEffectType,
        AudioEngine,
        AudioState,
        AudioStream,
        MusicManager,
        SoundEffectManager;
