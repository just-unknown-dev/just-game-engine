library;

import '../../../subsystems/timeline/timeline_asset.dart';
import '../../../subsystems/timeline/timeline_player.dart';
import '../../ecs.dart';

/// Which wrap a player uses.
enum TimelineWrapChoice {
  /// Whatever the timeline itself says.
  fromTimeline,
  once,
  loop,
  pingPong;

  TimelineWrap? get wrap => switch (this) {
    fromTimeline => null,
    once => TimelineWrap.once,
    loop => TimelineWrap.loop,
    pingPong => TimelineWrap.pingPong,
  };
}

/// Plays a timeline. The timeline is a `.timeline.json` asset at
/// [timelinePath], shared by every player that names it — or, with no path,
/// the [inline] one that belongs to this entity alone.
///
/// Tracks bound to "self" act on the entity holding this component, which is
/// what lets one asset animate many entities.
class TimelinePlayerComponent extends Component {
  TimelinePlayerComponent({
    this.timelinePath = '',
    this.inline,
    this.playOnStart = false,
    this.speed = 1.0,
    this.wrap = TimelineWrapChoice.fromTimeline,
    this.listenSignal = '',
    this.from = 0,
    this.to = 0,
  });

  /// The asset to play. Empty plays [inline].
  String timelinePath;

  /// A timeline saved inside the scene, for a one-off.
  TimelineAsset? inline;

  /// Start playing the first time the system sees this component.
  bool playOnStart;

  /// 1 is as authored; negative plays backwards.
  double speed;
  TimelineWrapChoice wrap;

  /// A `TimelineSignals` name that starts this player.
  String listenSignal;

  /// Play only part of the timeline: from here, in seconds. Zero starts at
  /// the beginning.
  ///
  /// With [to] it makes one asset serve several entities differently — a
  /// door that plays only the second half of a shared "open", a torch that
  /// loops two seconds out of ten.
  double from;

  /// Play up to here, in seconds. Zero — or anything past the end — plays
  /// to the end.
  double to;

  /// Whether this player runs only part of its timeline.
  bool get hasRange => from > 0 || to > 0;

  /// What [TimelinePlayback.range] is given; null when it plays the lot.
  (double, double)? get playRange => hasRange ? (from, to) : null;

  // ── Runtime ──────────────────────────────────────────────────────────────

  /// The running timeline, once the system has loaded it.
  TimelinePlayback? playback;

  /// While true the system leaves this player alone. An authoring tool sets
  /// it while it previews the timeline with a playback of its own.
  bool suspended = false;

  bool initialized = false;
  void Function(TimelinePlayback playback)? _pending;

  bool get isPlaying => playback?.isPlaying ?? false;
  bool get isFinished => playback?.isFinished ?? false;

  /// Seconds from the start; 0 before the timeline has loaded.
  double get time => playback?.time ?? 0;

  /// 0–1 through the timeline.
  double get progress => playback?.progress ?? 0;

  // A timeline loads asynchronously, so what is asked before then is kept
  // and done the moment it arrives.
  void _do(void Function(TimelinePlayback playback) action) {
    final running = playback;
    running == null ? _pending = action : action(running);
  }

  /// Plays from where it is — or from the start, once finished.
  void play() => _do((p) => p.play());

  /// Plays from the start (the end, when [speed] is negative).
  void restart() => _do((p) => p.play(from: p.speed < 0 ? p.duration : 0));

  /// Plays from the marker called [marker]; from the start without one.
  void playFrom(String marker) => _do((p) {
    if (!p.playFrom(marker)) p.play(from: 0);
  });

  /// Plays forwards from where it is — from the start, once finished.
  void forwards() => _do((p) {
    speed = speed.abs();
    p.speed = speed;
    p.play(from: p.isFinished || p.time >= p.duration ? 0 : null);
  });

  /// Plays [path] from its start, in place of whatever was playing — what an
  /// animator state with a timeline does on entry.
  void playTimeline(String path) {
    if (path.trim() == timelinePath.trim() && playback != null) {
      restart();
      return;
    }
    timelinePath = path;
    reset();
    // Not on start: the timeline was asked for, so it plays either way.
    initialized = true;
    _pending = (p) => p.play(from: p.speed < 0 ? p.duration : 0);
  }

  /// Plays back towards the start from where it is.
  void reverse() => _do((p) {
    speed = -speed.abs();
    p.speed = speed;
    p.play(from: p.isFinished || p.time <= 0 ? p.duration : null);
  });

  void pause() => _do((p) => p.pause());
  void stop() => _do((p) => p.stop());
  void seek(double time) => _do((p) => p.seek(time));

  /// Called by the system when [playback] has just been set.
  void flushPending() {
    final action = _pending;
    _pending = null;
    final running = playback;
    if (action != null && running != null) action(running);
  }

  /// Throws the running playback away; the system makes a new one. For when
  /// the timeline changed under it.
  void reset() {
    playback?.dispose();
    playback = null;
    initialized = false;
    _pending = null;
  }
}
