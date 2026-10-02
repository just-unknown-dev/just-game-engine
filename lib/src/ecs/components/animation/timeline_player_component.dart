library;

import '../../../subsystems/timeline/timeline_asset.dart';
import '../../../subsystems/timeline/timeline_player.dart';
import '../../ecs.dart';

/// Which wrap a player uses.
enum TimelineWrapChoice {
  /// Whatever the timeline itself says.
  fromTimeline,

  /// Plays once and stops, whatever the timeline says.
  once,

  /// Starts over at the end, whatever the timeline says.
  loop,

  /// Runs back and forth, whatever the timeline says.
  pingPong;

  /// The wrap this choice imposes on the playback; null for [fromTimeline],
  /// which leaves the timeline's own.
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
  /// A player of the asset at [timelinePath] — or of [inline] while the path
  /// is empty — that waits to be started, at normal [speed], with the
  /// timeline's own [wrap], over the whole timeline.
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

  /// What happens at the end: the timeline's own wrap, or one imposed on
  /// it. Copied to the playback every frame.
  TimelineWrapChoice wrap;

  /// A signal name (`context.signals`) that starts this player.
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

  /// Whether [playOnStart] has had its turn: set by the system when it makes
  /// the first playback (and by [playTimeline]), cleared by [reset].
  bool initialized = false;
  void Function(TimelinePlayback playback)? _pending;

  /// Whether the timeline is running; false before it has loaded.
  bool get isPlaying => playback?.isPlaying ?? false;

  /// Whether a timeline that wraps `once` has reached its end (its start,
  /// playing backwards); false before it has loaded.
  bool get isFinished => playback?.isFinished ?? false;

  /// Seconds from the start; 0 before the timeline has loaded.
  double get time => playback?.time ?? 0;

  /// 0–1 through the timeline.
  double get progress => playback?.progress ?? 0;

  // A timeline loads asynchronously, so what is asked before then is kept
  // and done the moment it arrives.
  //
  // The playback's speed is only brought in line with [speed] when the
  // system next runs; whoever just set [speed] (a trigger, say) means it
  // for this action already, so it is copied first.
  void _do(void Function(TimelinePlayback playback) action) {
    final running = playback;
    if (running == null) {
      _pending = action;
      return;
    }
    running.speed = speed;
    action(running);
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

  /// Plays back towards the start from where it is — from the end when it
  /// is at the start.
  void reverse() => _do((p) {
    speed = -speed.abs();
    p.speed = speed;
    // A timeline that finished at its end turns round there; one sitting
    // at its start has nowhere to go back to but the end.
    p.play(from: p.time <= p.rangeStart ? p.rangeEnd : null);
  });

  /// Holds the playhead where it is; [play] carries on from there. Asked
  /// before the timeline has loaded, it is done when it arrives (like the
  /// other controls, only the last one asked is kept).
  void pause() => _do((p) => p.pause());

  /// Stops and rewinds to the start of the play range ([from]). What the
  /// timeline animated stays where it is.
  void stop() => _do((p) => p.stop());

  /// Jumps to [time], in seconds from the timeline's start, clamped to the
  /// play range, and shows it. Events in between do not fire; playing or
  /// paused stays as it was.
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
