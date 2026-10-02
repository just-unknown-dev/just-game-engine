/// Named signals: how something that knows nothing of timelines — or one
/// timeline — sets another going.
library;

import 'dart:async';

/// A bus of names, one per engine (`engine.context.signals`), shared by every
/// world on that engine — the level's and the interface's screens', so a
/// button on a screen can start a timeline in the level. A
/// `TimelinePlayerComponent` whose `listenSignal` is a name plays when that
/// name is emitted; a timeline event marked as a signal emits one.
///
/// ```dart
/// engine.context.signals.emit('boss_defeated');
/// ```
final class TimelineSignals {
  final StreamController<String> _signals = StreamController<String>.broadcast(
    sync: true,
  );

  /// Every name emitted, as it is emitted.
  Stream<String> get stream => _signals.stream;

  /// Sends [name] to every listener. An empty name, or a bus that was
  /// disposed, sends nothing.
  void emit(String name) {
    if (name.isNotEmpty && !_signals.isClosed) _signals.add(name);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _signals.isClosed;

  /// Closes the bus: listeners hear it end, and nothing more is sent.
  void dispose() {
    if (!_signals.isClosed) _signals.close();
  }
}
