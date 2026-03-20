library;

import '../../ecs.dart';

/// Children component - Tracks child entities
class ChildrenComponent extends Component {
  /// List of child entity IDs
  final List<EntityId> childIds = [];

  /// Add a child
  void addChild(EntityId id) {
    if (!childIds.contains(id)) {
      childIds.add(id);
    }
  }

  /// Remove a child
  void removeChild(EntityId id) {
    childIds.remove(id);
  }

  @override
  String toString() => 'Children(${childIds.length})';
}
