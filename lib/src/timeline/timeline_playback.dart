/// Playing a timeline: the clock, the wrap, and the tracks' runners.
library;

import '../ecs/ecs.dart';
import 'timeline_asset.dart';
import 'timeline_track.dart';
import 'timeline_context.dart';

/// An event a timeline fired.
class TimelineEventFired {
  /// The event [name], with [payload], fired by [owner]'s timeline.
  const TimelineEventFired(this.owner, this.name, this.payload);

  /// The entity whose player was playing.
  final Entity owner;

  /// The event's name, as its track gave it.
  final String name;

  /// What the event carries for its listener; empty when nothing.
  final String payload;
}

/// One timeline being played by one entity. The ECS system drives one per
/// player component; an editor drives its own to preview, and a game can
/// make one with no component at all.
class TimelinePlayback implements TrackContext {
  /// Plays [asset] in [world]. Tracks of a kind the asset was read without
  /// but [world]'s context knows (`context.trackKinds`) are read again
  /// first, so they play.
  TimelinePlayback(
    TimelineAsset asset, {
    required World world,
    required Entity owner,
    void Function(TimelineEventFired event)? onEvent,
    bool isPreview = false,
    int depth = 0,
    void Function(Component component, FieldDefinition field)? onWillWrite,
    Future<TimelineAsset> Function(String path)? loader,
  }) : this._(
         world.context.trackKinds.resolve(asset),
         world: world,
         owner: owner,
         onEvent: onEvent,
         isPreview: isPreview,
         depth: depth,
         onWillWrite: onWillWrite,
         loader: loader,
       );

  TimelinePlayback._(
    this.asset, {
    required this.world,
    required this.owner,
    this.onEvent,
    this.isPreview = false,
    this.depth = 0,
    this.onWillWrite,
    Future<TimelineAsset> Function(String path)? loader,
  }) : _loader = loader,
       runners = [for (final t in asset.tracks) t.createRunner()];

  /// The timeline played, with the tracks the world's kinds could read
  /// again already read (so not always the instance passed in).
  final TimelineAsset asset;

  @override
  final World world;

  @override
  final Entity owner;

  @override
  final bool isPreview;

  @override
  final int depth;

  final Future<TimelineAsset> Function(String path)? _loader;

  /// Told, synchronously, of every event this playback fires — and every
  /// one a timeline nested in it fires. Null ignores them.
  final void Function(TimelineEventFired event)? onEvent;

  /// See [TrackContext.willWrite].
  final void Function(Component component, FieldDefinition field)? onWillWrite;

  /// One per track, in the asset's order.
  final List<TrackRunner> runners;

  final Map<TrackBinding, Entity> _resolved = {};

  /// Seconds from the start.
  double get time => _time;
  double _time = 0;

  /// 1 is as authored; negative plays backwards.
  double speed = 1;

  /// Overrides the asset's wrap when set.
  TimelineWrap? wrap;

  /// Whether the clock is running: set by [play]; cleared by [pause],
  /// [stop], [dispose] and a `once` timeline reaching its end.
  bool get isPlaying => _playing;
  bool _playing = false;

  /// A `once` timeline got to its end (or, backwards, its start).
  @override
  bool get isFinished => _finished;
  bool _finished = false;

  bool _begun = false;
  bool _touchStart = false;

  // +1, or -1 on the way back of a ping-pong.
  int _bounce = 1;

  /// Which way the clock runs: 1 forwards, −1 backwards — [speed]'s sign,
  /// turned round while a ping-pong is on its way back.
  ///
  /// Setting it asks for that way from where the playhead is: [speed]
  /// keeps its size and takes the sign, and a ping-pong on its way back
  /// stops being turned round. Zero counts as forwards.
  int get direction => (speed < 0 ? -1 : 1) * _bounce;
  set direction(int value) {
    speed = value < 0 ? -speed.abs() : speed.abs();
    _bounce = 1;
  }

  // How far the clock has run since play last started over, in seconds of
  // timeline: what [laps] counts.
  double _travelled = 0;

  /// How many times through the stretch being played ([playLength]) the
  /// clock has run since play last started over — from an edge, a marker
  /// or [stop]. It counts on past 1 for a loop or a ping-pong (each way
  /// counting once), where [progress] folds back to 0–1: what an
  /// animator's exit time is measured by. 1 when there is no length to
  /// run.
  double get laps {
    final length = playLength;
    return length <= 0 ? 1 : _travelled / length;
  }

  // Entities a track of this playback, or of one nested in it, switched
  // off (and not back on since): see [holdsOwnerOff].
  final Set<Entity> _switchedOff = {};

  // While [update] steps: a [pause] from an event handler ends the step,
  // and the playhead parks on the event that called it ([_eventTime]).
  bool _stepping = false;
  double? _eventTime;
  double? _parkAt;

  // Bumped by whatever throws the clock somewhere else — stop, seek, a
  // restart, dispose. A step compares it with the value it began with: an
  // event handler that did one of those has the last word, and the step
  // stops where it is.
  int _generation = 0;
  int _stepGeneration = 0;

  // The playback this one is nested in, whose interruptions are its own.
  TimelinePlayback? _parent;

  /// The whole timeline, whatever this playback runs of it.
  double get duration => asset.duration > 0 ? asset.duration : asset.contentEnd;

  /// Play only this stretch of it, as `(from, to)` in seconds — what a
  /// player's *Play from* and *Play to* ask for. A `to` at or below zero
  /// means the end. Null plays all of it.
  ///
  /// It is what the clock runs between: play, stop and a loop's wrap all
  /// use these edges rather than 0 and [duration], so two entities can play
  /// different parts of one timeline.
  (double, double)? range;

  /// [range] made sense of: inside the timeline, in order, and the whole of
  /// it when what was asked for is not a stretch of time.
  (double, double) get bounds {
    final total = duration;
    final asked = range;
    if (asked == null) return (0, total);
    final from = asked.$1.clamp(0.0, total).toDouble();
    final to = (asked.$2 <= 0 ? total : asked.$2).clamp(0.0, total).toDouble();
    return to - from < 1e-6 ? (0.0, total) : (from, to);
  }

  /// Where this playback starts.
  double get rangeStart => bounds.$1;

  /// Where it ends.
  double get rangeEnd => bounds.$2;

  /// How long it runs for.
  double get playLength {
    final (from, to) = bounds;
    return to - from;
  }

  /// 0–1 through the stretch being played.
  double get progress {
    final (from, to) = bounds;
    return to - from <= 0 ? 1 : ((_time - from) / (to - from)).clamp(0.0, 1.0);
  }

  /// The wrap in force: [wrap] when set, else the asset's own.
  TimelineWrap get effectiveWrap => wrap ?? asset.wrap;

  // ── TrackContext ──────────────────────────────────────────────────────

  @override
  Entity? resolve(TrackBinding binding, {bool includeInactive = false}) {
    if (binding.isSelf) return owner;
    final known = _resolved[binding];
    if (known != null &&
        known.isAlive &&
        (includeInactive || known.isActiveInHierarchy)) {
      return known;
    }
    final found = binding.resolve(
      world,
      owner,
      includeInactive: includeInactive,
    );
    if (found == null) {
      _resolved.remove(binding);
    } else {
      _resolved[binding] = found;
    }
    return found;
  }

  @override
  void emit(String name, [String payload = '', double? time]) {
    _eventTime = time;
    try {
      onEvent?.call(TimelineEventFired(owner, name, payload));
    } finally {
      _eventTime = null;
    }
  }

  @override
  void switchActive(Entity entity, bool active) {
    entity.isActive = active;
    _noteSwitched(entity, active);
  }

  void _noteSwitched(Entity entity, bool active) {
    if (active) {
      _switchedOff.remove(entity);
    } else {
      _switchedOff.add(entity);
    }
    // The playback a player steps is the outermost one: it must know too.
    _parent?._noteSwitched(entity, active);
  }

  /// Whether a track of this playback — an activation track, or one in a
  /// timeline nested in it — has switched off [owner] or a parent of it,
  /// which is still off. The world then leaves [owner] out of its queries,
  /// so whoever steps playbacks by them must step this one anyway: only
  /// it can switch the entity back on.
  bool get holdsOwnerOff {
    if (_switchedOff.isEmpty) return false;
    Entity? at = owner;
    // Up the hierarchy; the bound only guards against a broken one.
    for (var depth = 0; at != null && depth < 256; depth++) {
      if (!at.isActive && _switchedOff.contains(at)) return true;
      final parent = at.getComponent<ParentComponent>()?.parentId;
      at = parent == null ? null : world.getEntity(parent);
    }
    return false;
  }

  @override
  void willWrite(Component component, FieldDefinition field) =>
      onWillWrite?.call(component, field);

  @override
  Future<TimelineAsset> loadTimeline(String path) =>
      (_loader ?? world.context.timelines)(path);

  @override
  TimelinePlayback child(TimelineAsset asset, Entity owner) => TimelinePlayback(
    asset,
    world: world,
    owner: owner,
    onEvent: onEvent,
    isPreview: isPreview,
    depth: depth + 1,
    onWillWrite: onWillWrite,
    loader: _loader,
  ).._parent = this;

  @override
  bool get isInterrupted =>
      _generation != _stepGeneration || (_parent?.isInterrupted ?? false);

  /// True at the end of the play range ([rangeEnd]) unless the wrap is a
  /// loop's, which goes straight on to the start: a `once` timeline stops
  /// there and a ping-pong turns round.
  @override
  bool endsAt(double time) =>
      effectiveWrap != TimelineWrap.loop && time >= rangeEnd - 1e-9;

  /// Fires what lies between [from] and [to] without moving the clock — for
  /// whoever drives this playback's time from outside, as a nested track
  /// does.
  void fireBetween(double from, double to) {
    _stepGeneration = _generation;
    _ensureBegun();
    _advance(from, to);
  }

  // ── Control ──────────────────────────────────────────────────────────────

  /// Plays from [from], or from where it is — from the start when it had
  /// finished, or the end when [speed] runs backwards.
  ///
  /// A playback that finished on the edge it would start from — at the end,
  /// now running backwards, say — turns round where it is rather than
  /// starting over: a relative track keeps the value it is relative to, so
  /// a door that opened all the way closes back to where it stood.
  void play({double? from}) {
    final backwards = speed < 0;
    final (lo, hi) = bounds;
    if (from != null) {
      _restart(from);
    } else if (_begun &&
        _finished &&
        hi > lo &&
        _time == (backwards ? hi : lo)) {
      // Turning round on the edge it stopped at: carry on from here.
    } else if (!_begun || _finished) {
      _restart(backwards ? hi : lo);
    } else if (_time < lo || _time > hi) {
      // The range moved under it — a trigger picking another slice, say.
      _restart(backwards ? hi : lo);
    }
    _playing = true;
    _finished = false;
  }

  /// Plays from the marker called [name]; false when there is none.
  bool playFrom(String name) {
    final marker = asset.markerNamed(name);
    if (marker == null) return false;
    play(from: marker.time);
    return true;
  }

  /// Stops the clock where it is; [play] carries on from there. Nothing is
  /// rewound or undone.
  ///
  /// Called from an event handler, the step that fired the event goes no
  /// further: later events in it do not fire, and the playhead stays on
  /// the event (on the end of the step, for an event of a nested
  /// timeline), so playing on does not fire it again.
  void pause() {
    _playing = false;
    if (!_stepping) return;
    _generation++;
    _parkAt = _eventTime ?? _advancingTo;
  }

  /// Stops and rewinds. What the timeline animated stays where it is.
  ///
  /// Called from an event handler, the step that fired the event goes no
  /// further: later events in it do not fire.
  void stop() {
    _generation++;
    _parkAt = null;
    _playing = false;
    _finished = false;
    if (_begun) _end();
    _time = rangeStart;
    _bounce = 1;
    _travelled = 0;
  }

  /// Jumps to [time] and shows it. Events in between do not fire — nor,
  /// called from an event handler, do the rest of that step's. A
  /// ping-pong sets off forwards from there.
  void seek(double time) {
    _generation++;
    _parkAt = null;
    _ensureBegun();
    final (lo, hi) = bounds;
    _time = time.clamp(lo, hi);
    _finished = false;
    _bounce = 1;
    apply();
  }

  /// Ends the playback for good: runners undo what only lasts while they
  /// run.
  void dispose() {
    _generation++;
    _parkAt = null;
    _playing = false;
    if (_begun) _end();
  }

  void _restart(double at) {
    _generation++;
    _parkAt = null;
    if (_begun) _end();
    final (lo, hi) = bounds;
    _time = at.clamp(lo, hi);
    _bounce = 1;
    _travelled = 0;
    _ensureBegun();
    _touchStart = true;
  }

  void _ensureBegun() {
    if (_begun) return;
    _begun = true;
    _resolved.clear();
    _switchedOff.removeWhere((e) => !e.isAlive || e.isActive);
    for (final r in runners) {
      r.begin(this);
    }
  }

  void _end() {
    _begun = false;
    for (final r in runners) {
      r.end(this);
    }
  }

  // ── Time ─────────────────────────────────────────────────────────────────

  /// Moves time on by [deltaTime] and shows the result.
  void update(double deltaTime) {
    if (!_playing) return;
    _stepping = true;
    try {
      _step(deltaTime);
    } finally {
      _stepping = false;
      _advancingTo = null;
    }
    // Paused by an event handler: the playhead stays on the event.
    final park = _parkAt;
    if (park != null) {
      _parkAt = null;
      final (lo, hi) = bounds;
      _time = park.clamp(lo, hi).toDouble();
      apply();
    }
  }

  void _step(double deltaTime) {
    // Events fire as the step passes them, and a handler may stop, seek,
    // pause or restart this playback; from then on the step is over.
    final step = _stepGeneration = _generation;
    final (lo, hi) = bounds;
    final length = hi - lo;
    // Only a ping-pong comes back; switched to another wrap on its way
    // back, it plays on as that wrap does.
    if (effectiveWrap != TimelineWrap.pingPong) _bounce = 1;
    var direction = (speed < 0 ? -1 : 1) * _bounce;
    if (length <= 0) {
      // No time to run through, but what sits on its one moment happens.
      if (_touchStart) {
        _touchStart = false;
        _advance(_time - direction * 1e-9, _time);
        if (_generation != step) return;
      }
      _playing = false;
      _finished = true;
      apply();
      return;
    }
    // The range moved under the playhead: it goes on from the edge it is
    // now past, firing nothing on the way back to it.
    if (_time < lo || _time > hi) _time = _time.clamp(lo, hi).toDouble();
    var remaining = (deltaTime * speed).abs();
    // A step many timelines long lands where the remainder would; walking
    // every lap would only fire the same events again and again. A
    // ping-pong's round trip is two lengths, so the remainder is of that.
    if (remaining > length * 4) {
      final kept = length * 2 + remaining % (length * 2);
      // The laps jumped over still count as played.
      _travelled += remaining - kept;
      remaining = kept;
    }

    // What sits exactly where play begins happens as it begins.
    if (_touchStart) {
      _touchStart = false;
      _advance(_time - direction * 1e-9, _time);
      if (_generation != step) return;
    }

    while (remaining > 0) {
      final target = _time + direction * remaining;
      // Short of the edge; landing exactly on it is reaching it.
      if (direction > 0 ? target < hi : target > lo) {
        _advance(_time, target);
        if (_generation != step) return;
        _travelled += remaining;
        _time = target;
        break;
      }
      final edge = direction > 0 ? hi : lo;
      _advance(_time, edge);
      if (_generation != step) return;
      final run = (edge - _time).abs();
      remaining -= run;
      _travelled += run;
      _time = edge;
      final wrap = effectiveWrap;
      if (wrap == TimelineWrap.once) {
        _playing = false;
        _finished = true;
        break;
      }
      if (wrap == TimelineWrap.loop) {
        // The end and the start are the same moment: what sits on the
        // start happens now.
        _time = direction > 0 ? lo : hi;
        _advance(_time - direction * 1e-9, _time);
        if (_generation != step) return;
      } else {
        _bounce = -_bounce;
        direction = -direction;
      }
    }
    apply();
  }

  // The time the step under way is running to, for a pause from a nested
  // timeline's event, whose own time is on another clock.
  double? _advancingTo;

  void _advance(double from, double to) {
    _advancingTo = to;
    for (var i = 0; i < runners.length; i++) {
      if (!asset.tracks[i].muted) runners[i].advance(this, from, to);
      if (isInterrupted) return;
    }
  }

  /// Makes the world look as the timeline says at [time].
  void apply() {
    _ensureBegun();
    for (var i = 0; i < runners.length; i++) {
      if (!asset.tracks[i].muted) runners[i].apply(this, _time);
    }
  }
}
