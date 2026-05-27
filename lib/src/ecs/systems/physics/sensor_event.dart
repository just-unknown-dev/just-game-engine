/// Sensor-related game events published to the [EventBus].
library;

import '../../ecs.dart';

/// Fired when a non-sensor body begins overlapping a sensor body.
///
/// Subscribe via the world event bus:
/// ```dart
/// world.events.on<SensorEnterEvent>((e) {
///   print('${e.visitor.id} entered sensor ${e.sensor.id}');
/// });
/// ```
class SensorEnterEvent extends GameEvent {
  /// The entity with [PhysicsBodyComponent.isSensor] == true.
  final Entity sensor;

  /// The entity that entered the sensor zone.
  final Entity visitor;

  SensorEnterEvent({required this.sensor, required this.visitor});
}

/// Fired when a non-sensor body stops overlapping a sensor body.
class SensorExitEvent extends GameEvent {
  /// The entity with [PhysicsBodyComponent.isSensor] == true.
  final Entity sensor;

  /// The entity that left the sensor zone.
  final Entity visitor;

  SensorExitEvent({required this.sensor, required this.visitor});
}
