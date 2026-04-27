library;

import '../../ecs/ecs.dart';

class InventoryItemChangedEvent extends GameEvent {
  final String itemId;
  final int previousQuantity;
  final int newQuantity;

  InventoryItemChangedEvent({
    required this.itemId,
    required this.previousQuantity,
    required this.newQuantity,
  });
}
