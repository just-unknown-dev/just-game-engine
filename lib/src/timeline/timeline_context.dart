/// What timelines keep per engine: their track kinds and easings, the
/// signals that start them, how their audio plays, and where their files
/// come from.
library;

import '../ecs/engine_context.dart';
import 'timeline_asset.dart';
import 'timeline_keys.dart';
import 'timeline_signals.dart';
import 'timeline_track.dart';
import 'tracks/block_tracks.dart';

/// Loads a timeline by path.
typedef TimelineLoader = Future<TimelineAsset> Function(String path);

/// The timeline state of one [EngineContext]; read it through
/// [ContextTimeline].
final class TimelineContextState implements ContextResource {
  TimelineContextState._(this._context)
    : trackKinds = TimelineTrackKinds(withBuiltIns: _context.withBuiltIns),
      easings = KeyEasings(withBuiltIns: _context.withBuiltIns) {
    loader = bundleLoader;
  }

  /// [context]'s state, made the first time it is asked for.
  static TimelineContextState of(EngineContext context) =>
      context.slot(_key, () => TimelineContextState._(context));

  static final Object _key = Object();

  final EngineContext _context;

  /// See [ContextTimeline.trackKinds].
  final TimelineTrackKinds trackKinds;

  /// See [ContextTimeline.easings].
  final KeyEasings easings;

  /// See [ContextTimeline.signals].
  final TimelineSignals signals = TimelineSignals();

  /// See [ContextTimeline.timelineAudio].
  TimelineAudioPlayer audio = TimelineAudio.viaAudioSystem;

  /// See [ContextTimeline.timelines].
  late TimelineLoader loader;

  /// Reads a timeline from the context's bundle: the default [loader].
  Future<TimelineAsset> bundleLoader(String path) async => TimelineAsset.parse(
    await _context.bundle.loadString(path),
    kinds: trackKinds,
    migrations: _context.migrations,
  );

  @override
  void dispose() => signals.dispose();
}

/// An engine's timeline state, on its [EngineContext].
extension ContextTimeline on EngineContext {
  /// The kinds of timeline track this engine reads and plays; the engine's
  /// seven are always there.
  TimelineTrackKinds get trackKinds => TimelineContextState.of(this).trackKinds;

  /// The easings a timeline key can name.
  KeyEasings get easings => TimelineContextState.of(this).easings;

  /// Named signals, for every world on this context: a timeline event or an
  /// interface button emits one, and timeline players listening for it
  /// start. Closed with the context.
  TimelineSignals get signals => TimelineContextState.of(this).signals;

  /// How a timeline's audio track makes a sound. By default a one-shot from
  /// the world's audio system ([TimelineAudio.viaAudioSystem]); a game with
  /// its own audio replaces it.
  TimelineAudioPlayer get timelineAudio => TimelineContextState.of(this).audio;
  set timelineAudio(TimelineAudioPlayer value) =>
      TimelineContextState.of(this).audio = value;

  /// Loads timelines for the `TimelineSystem` and nested timeline tracks.
  /// The bundle by default; an authoring tool points it at the project's
  /// files (`overrideLoaders`).
  TimelineLoader get timelines => TimelineContextState.of(this).loader;
  set timelines(TimelineLoader value) =>
      TimelineContextState.of(this).loader = value;
}
