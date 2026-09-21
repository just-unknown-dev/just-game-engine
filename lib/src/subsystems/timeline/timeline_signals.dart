/// Named signals: how something that knows nothing of timelines — or one
/// timeline — sets another going.
library;

import 'dart:async';

/// A process-wide bus of names. A `TimelinePlayerComponent` whose
/// `listenSignal` is a name plays when that name is emitted; a timeline
/// event marked as a signal emits one.
///
/// ```dart
/// TimelineSignals.emit('boss_defeated');
/// ```
abstract final class TimelineSignals {
  static final StreamController<String> _signals =
      StreamController<String>.broadcast(sync: true);

  static Stream<String> get stream => _signals.stream;

  static void emit(String name) {
    if (name.isNotEmpty) _signals.add(name);
  }
}
