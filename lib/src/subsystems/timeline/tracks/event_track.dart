/// A track of named moments: "footstep", "open", "shake".
library;

import '../timeline_signals.dart';
import '../timeline_track.dart';

/// Something that happens at a time.
class TimelineEvent {
  const TimelineEvent({
    required this.time,
    required this.name,
    this.payload = '',
    this.signal = false,
  });

  final double time;
  final String name;

  /// Whatever the listener wants to be told; the timeline only carries it.
  final String payload;

  /// Also sent through [TimelineSignals], where it starts every player
  /// listening for [name] — how one timeline sets off another.
  final bool signal;

  TimelineEvent copyWith({
    double? time,
    String? name,
    String? payload,
    bool? signal,
  }) => TimelineEvent(
    time: time ?? this.time,
    name: name ?? this.name,
    payload: payload ?? this.payload,
    signal: signal ?? this.signal,
  );

  Map<String, dynamic> toJson() => {
    'time': time,
    'name': name,
    if (payload.isNotEmpty) 'payload': payload,
    if (signal) 'signal': true,
  };

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
    time: (json['time'] as num?)?.toDouble() ?? 0,
    name: json['name'] as String? ?? '',
    payload: json['payload'] as String? ?? '',
    signal: json['signal'] == true,
  );
}

class EventTrack extends TimelineTrack {
  EventTrack({
    List<TimelineEvent> events = const [],
    super.name,
    super.binding,
    super.muted,
    super.locked,
  }) : events = List.unmodifiable(
         List.of(events)..sort((a, b) => a.time.compareTo(b.time)),
       );

  static const String kindId = 'event';

  final List<TimelineEvent> events;

  @override
  String get kind => kindId;

  @override
  double get end => events.isEmpty ? 0 : events.last.time;

  @override
  String get summary => 'Events';

  @override
  TrackRunner createRunner() => _EventRunner(this);

  EventTrack copyWith({
    List<TimelineEvent>? events,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => EventTrack(
    events: events ?? this.events,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  @override
  TimelineTrack withBase({
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => copyWith(name: name, binding: binding, muted: muted, locked: locked);

  @override
  Map<String, dynamic> bodyToJson() => {
    'events': [for (final e in events) e.toJson()],
  };

  factory EventTrack.fromJson(Map<String, dynamic> json) => EventTrack(
    events: [
      for (final e in json['events'] as List? ?? const [])
        if (e is Map) TimelineEvent.fromJson(e.cast<String, dynamic>()),
    ],
    name: json['name'] as String? ?? '',
    binding: TrackBinding.fromJson(json['binding']),
    muted: json['muted'] == true,
    locked: json['locked'] == true,
  );
}

class _EventRunner extends TrackRunner {
  _EventRunner(this.track);

  final EventTrack track;

  // Forwards an event fires when time passes it — (from, to] — and an event
  // at 0 fires as play begins, which the playback makes happen by starting
  // its first step just before 0. Backwards it is [to, from), so an event
  // fires once per crossing whichever way time runs.
  @override
  void advance(TimelineContext context, double from, double to) {
    if (to >= from) {
      for (final e in track.events) {
        if (e.time > from && e.time <= to) _fire(context, e);
      }
    } else {
      for (final e in track.events.reversed) {
        if (e.time >= to && e.time < from) _fire(context, e);
      }
    }
  }

  void _fire(TimelineContext context, TimelineEvent e) {
    context.emit(e.name, e.payload);
    // A look in an editor must not set the rest of the scene going.
    if (e.signal && !context.isPreview) TimelineSignals.emit(e.name);
  }
}
