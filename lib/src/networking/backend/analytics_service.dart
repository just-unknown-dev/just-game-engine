/// Analytics Service
///
/// Abstract interface and data models for game analytics and telemetry.
/// Implement [IAnalyticsService] to forward events to any analytics backend
/// (Firebase Analytics, Amplitude, Mixpanel, custom, etc.).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A single analytics event emitted by the game.
class GameEvent {
  /// Snake_case or camelCase event name (e.g. "level_complete", "itemPurchased").
  final String eventName;

  /// Arbitrary key-value properties attached to this event.
  final Map<String, dynamic> properties;

  /// UTC timestamp when the event occurred.
  final DateTime timestamp;

  /// Optional session identifier for grouping events.
  final String? sessionId;

  /// Optional player identifier.
  final String? playerId;

  GameEvent({
    required this.eventName,
    this.properties = const {},
    this.sessionId,
    this.playerId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'event': eventName,
    'properties': properties,
    'ts': timestamp.millisecondsSinceEpoch,
    if (sessionId != null) 'session': sessionId,
    if (playerId != null) 'player': playerId,
  };

  @override
  String toString() => 'GameEvent($eventName, player=$playerId)';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Backend-agnostic analytics service.
///
/// Implementations should batch and flush events efficiently according to
/// their platform's SDK requirements.
abstract class IAnalyticsService {
  /// Set the active [userId] for all subsequent events.
  Future<void> setUserId(String userId);

  /// Set a persistent property applied to all future events.
  Future<void> setUserProperty(String key, String value);

  /// Log a structured [GameEvent].
  Future<void> logEvent(GameEvent event);

  /// Convenience: log an event by [name] with optional [properties].
  Future<void> logCustom(String name, [Map<String, dynamic>? properties]);

  /// Log the start of a timed event. Call [logEventEnd] with the same [name]
  /// to record the elapsed duration automatically.
  Future<void> logEventStart(String name);

  /// End a timed event started with [logEventStart].
  Future<void> logEventEnd(String name, [Map<String, dynamic>? extraProps]);

  /// Force any buffered events to be sent immediately.
  Future<void> flush();

  /// Opt out of analytics entirely (GDPR / privacy control).
  Future<void> setEnabled(bool enabled);
}

// ---------------------------------------------------------------------------
// In-memory / debug implementation
// ---------------------------------------------------------------------------

/// A debug [IAnalyticsService] that accumulates events in memory and prints
/// them to the console. Useful during development and for unit tests.
///
/// Only active in debug builds; in release the standard no-op guard applies.
class DebugAnalyticsService implements IAnalyticsService {
  final List<GameEvent> _events = [];
  final Map<String, DateTime> _timers = {};
  String? _userId;
  bool _enabled = true;

  /// Read-only list of all recorded events.
  List<GameEvent> get events => List.unmodifiable(_events);

  /// Clear the recorded event list.
  void clearEvents() => _events.clear();

  @override
  Future<void> setUserId(String userId) async {
    _userId = userId;
    debugPrint('DebugAnalytics: setUserId($userId)');
  }

  @override
  Future<void> setUserProperty(String key, String value) async {
    debugPrint('DebugAnalytics: setUserProperty($key=$value)');
  }

  @override
  Future<void> logEvent(GameEvent event) async {
    if (!_enabled) return;
    final enriched = GameEvent(
      eventName: event.eventName,
      properties: event.properties,
      sessionId: event.sessionId,
      playerId: event.playerId ?? _userId,
      timestamp: event.timestamp,
    );
    _events.add(enriched);
    debugPrint('DebugAnalytics: ${enriched.toJson()}');
  }

  @override
  Future<void> logCustom(String name, [Map<String, dynamic>? properties]) =>
      logEvent(
        GameEvent(
          eventName: name,
          properties: properties ?? {},
          playerId: _userId,
        ),
      );

  @override
  Future<void> logEventStart(String name) async {
    _timers[name] = DateTime.now().toUtc();
    debugPrint('DebugAnalytics: timer started for "$name"');
  }

  @override
  Future<void> logEventEnd(
    String name, [
    Map<String, dynamic>? extraProps,
  ]) async {
    final start = _timers.remove(name);
    if (start == null) {
      debugPrint('DebugAnalytics: no timer found for "$name"');
      return;
    }
    final elapsed = DateTime.now().toUtc().difference(start).inMilliseconds;
    await logCustom(name, {'duration_ms': elapsed, ...?extraProps});
  }

  @override
  Future<void> flush() async {
    debugPrint('DebugAnalytics: flush() — ${_events.length} events buffered');
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    debugPrint('DebugAnalytics: analytics ${enabled ? "enabled" : "disabled"}');
  }

  /// Release resources.
  void dispose() {
    _events.clear();
    _timers.clear();
    debugPrint('DebugAnalyticsService: disposed');
  }
}
