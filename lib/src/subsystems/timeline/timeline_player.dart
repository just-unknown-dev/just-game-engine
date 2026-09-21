/// Playing a timeline: the clock, the wrap, and the tracks' runners.
library;

import 'package:flutter/services.dart' show rootBundle;

import '../../ecs/ecs.dart';
import '../../ecs/serialization/component_definition.dart' show SchemaField;
import 'timeline_asset.dart';
import 'timeline_track.dart';

/// Where timeline files come from; a tool replaces [loader] to read the
/// project's files instead of the asset bundle.
abstract final class TimelineAssets {
  static Future<TimelineAsset> Function(String path) loader = _fromBundle;

  static Future<TimelineAsset> _fromBundle(String path) async =>
      TimelineAsset.parse(await rootBundle.loadString(path));

  /// Restores the bundle loader.
  static void useBundle() => loader = _fromBundle;
}

/// An event a timeline fired.
class TimelineEventFired {
  const TimelineEventFired(this.owner, this.name, this.payload);

  /// The entity whose player was playing.
  final Entity owner;
  final String name;
  final String payload;
}

/// One timeline being played by one entity. The ECS system drives one per
/// player component; an editor drives its own to preview, and a game can
/// make one with no component at all.
class TimelinePlayback implements TimelineContext {
  TimelinePlayback(
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

  final void Function(TimelineEventFired event)? onEvent;

  /// See [TimelineContext.willWrite].
  final void Function(Component component, SchemaField field)? onWillWrite;

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

  bool get isPlaying => _playing;
  bool _playing = false;

  /// A `once` timeline got to its end (or, backwards, its start).
  bool get isFinished => _finished;
  bool _finished = false;

  bool _begun = false;
  bool _touchStart = false;

  // +1, or -1 on the way back of a ping-pong.
  int _bounce = 1;

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

  TimelineWrap get effectiveWrap => wrap ?? asset.wrap;

  // ── TimelineContext ──────────────────────────────────────────────────────

  @override
  Entity? resolve(TrackBinding binding, {bool includeInactive = false}) {
    if (binding.isSelf) return owner;
    final known = _resolved[binding];
    if (known != null && known.isAlive && (includeInactive || known.isActive)) {
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
  void emit(String name, [String payload = '']) =>
      onEvent?.call(TimelineEventFired(owner, name, payload));

  @override
  void willWrite(Component component, SchemaField field) =>
      onWillWrite?.call(component, field);

  @override
  Future<TimelineAsset> loadTimeline(String path) =>
      (_loader ?? TimelineAssets.loader)(path);

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
  );

  /// Fires what lies between [from] and [to] without moving the clock — for
  /// whoever drives this playback's time from outside, as a nested track
  /// does.
  void fireBetween(double from, double to) {
    _ensureBegun();
    _advance(from, to);
  }

  // ── Control ──────────────────────────────────────────────────────────────

  /// Plays from [from], or from where it is — from the start when it had
  /// finished, or the end when [speed] runs backwards.
  void play({double? from}) {
    final backwards = speed < 0;
    final (lo, hi) = bounds;
    if (from != null) {
      _restart(from);
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

  void pause() => _playing = false;

  /// Stops and rewinds. What the timeline animated stays where it is.
  void stop() {
    _playing = false;
    _finished = false;
    if (_begun) _end();
    _time = rangeStart;
  }

  /// Jumps to [time] and shows it. Events in between do not fire.
  void seek(double time) {
    _ensureBegun();
    final (lo, hi) = bounds;
    _time = time.clamp(lo, hi);
    _finished = false;
    apply();
  }

  /// Ends the playback for good: runners undo what only lasts while they
  /// run.
  void dispose() {
    _playing = false;
    if (_begun) _end();
  }

  void _restart(double at) {
    if (_begun) _end();
    final (lo, hi) = bounds;
    _time = at.clamp(lo, hi);
    _bounce = 1;
    _ensureBegun();
    _touchStart = true;
  }

  void _ensureBegun() {
    if (_begun) return;
    _begun = true;
    _resolved.clear();
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
    final (lo, hi) = bounds;
    final length = hi - lo;
    if (length <= 0) {
      _playing = false;
      _finished = true;
      return;
    }
    var direction = (speed < 0 ? -1 : 1) * _bounce;
    var remaining = (deltaTime * speed).abs();
    // A step many timelines long lands where the remainder would; walking
    // every lap would only fire the same events again and again.
    if (remaining > length * 4) remaining = length * 2 + remaining % length;

    // What sits exactly where play begins happens as it begins.
    if (_touchStart) {
      _touchStart = false;
      _advance(_time - direction * 1e-9, _time);
    }

    while (remaining > 0) {
      final target = _time + direction * remaining;
      // Short of the edge; landing exactly on it is reaching it.
      if (direction > 0 ? target < hi : target > lo) {
        _advance(_time, target);
        _time = target;
        break;
      }
      final edge = direction > 0 ? hi : lo;
      _advance(_time, edge);
      remaining -= (edge - _time).abs();
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
      } else {
        _bounce = -_bounce;
        direction = -direction;
      }
    }
    apply();
  }

  void _advance(double from, double to) {
    for (var i = 0; i < runners.length; i++) {
      if (!asset.tracks[i].muted) runners[i].advance(this, from, to);
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
