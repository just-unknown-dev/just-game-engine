part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Event Bus — typed inter-system messaging
// ════════════════════════════════════════════════════════════════════════════

/// Base class for all events dispatched through the [EventBus].
///
/// Events are lightweight data objects that systems can fire and other systems
/// can subscribe to, enabling decoupled communication.
///
/// ```dart
/// class DamageEvent extends GameEvent {
///   final Entity target;
///   final double amount;
///   DamageEvent(this.target, this.amount);
/// }
///
/// // Producer system:
/// world.events.fire(DamageEvent(entity, 25.0));
///
/// // Consumer system (in onAddedToWorld or initialize):
/// world.events.on<DamageEvent>((event) {
///   // handle damage
/// });
/// ```
abstract class GameEvent {}

/// Typed callback for event subscriptions.
typedef EventCallback<T extends GameEvent> = void Function(T event);

/// A lightweight event bus for decoupled inter-system communication.
///
/// Events are dispatched immediately on [fire] (synchronous). Systems
/// subscribe via [on] and unsubscribe via the returned [EventSubscription].
///
/// The bus is owned by [World] and disposed with it.
class EventBus {
  final Map<Type, List<_Listener>> _listeners = {};

  /// Subscribe to events of type [T].
  ///
  /// Returns an [EventSubscription] that can be used to unsubscribe later.
  EventSubscription on<T extends GameEvent>(EventCallback<T> callback) {
    final listener = _Listener<T>(callback);
    (_listeners[T] ??= []).add(listener);
    return EventSubscription._(() {
      _listeners[T]?.remove(listener);
    });
  }

  /// Fire an event, notifying all subscribers of its runtime type.
  void fire<T extends GameEvent>(T event) {
    final listeners = _listeners[event.runtimeType];
    if (listeners == null || listeners.isEmpty) return;
    // Iterate a copy so handlers can unsubscribe during dispatch.
    for (final listener in List<_Listener>.of(listeners)) {
      listener.invoke(event);
    }
  }

  /// Remove all subscriptions (called by [World.dispose]).
  void clear() {
    _listeners.clear();
  }
}

/// Handle returned by [EventBus.on] to cancel a subscription.
class EventSubscription {
  final void Function() _cancel;
  bool _cancelled = false;

  EventSubscription._(this._cancel);

  /// Cancel this subscription. Safe to call multiple times.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

class _Listener<T extends GameEvent> {
  final EventCallback<T> _callback;
  _Listener(this._callback);

  void invoke(GameEvent event) => _callback(event as T);
}
