/// Named signals: how something that knows nothing of timelines — or one
/// timeline — sets another going.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

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

  // Names emitted by a listener while a name is being sent: sent next, in
  // order, once every listener has heard the one before.
  final List<String> _queued = [];
  bool _sending = false;

  // How many relayed names one emit sends at most.
  static const int _maxRelays = 1000;

  /// Sends [name] to every listener. An empty name, or a bus that was
  /// disposed, sends nothing. A listener may emit too — relay one signal
  /// as another: that name goes out once the current one has reached
  /// every listener.
  void emit(String name) {
    if (name.isEmpty || _signals.isClosed) return;
    if (_sending) {
      _queued.add(name);
      return;
    }
    _sending = true;
    try {
      _signals.add(name);
      for (var i = 0; i < _queued.length && !_signals.isClosed; i++) {
        if (i == _maxRelays) {
          // Listeners relaying signals to each other in a circle.
          debugPrint(
            'TimelineSignals: "$name" set off more than $_maxRelays more '
            'signals; the rest were dropped.',
          );
          break;
        }
        _signals.add(_queued[i]);
      }
    } finally {
      _queued.clear();
      _sending = false;
    }
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _signals.isClosed;

  /// Closes the bus: listeners hear it end, and nothing more is sent.
  void dispose() {
    if (!_signals.isClosed) _signals.close();
  }
}
