library;

class InventoryItem {
  final String id;
  final String name;
  final int maxStack;

  const InventoryItem({
    required this.id,
    required this.name,
    this.maxStack = 999999,
  });
}
