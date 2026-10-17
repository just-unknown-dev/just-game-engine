/// Where entities made from a prefab file came from.
library;

import '../../ecs.dart';
import '../../serialization/prefab_format.dart';

/// On the top entity of a prefab instance: which prefab file it is
/// ([path]) and what this instance changed when it was loaded ([block]).
///
/// Runtime only, never saved as a component: a scene saves an instance as
/// its `prefab` block, worked out again from the entities as they are
/// ([PrefabCollapse]).
class PrefabInstanceComponent extends Component {
  PrefabInstanceComponent({required this.block, this.missing = false});

  /// The instance as loaded: its prefab's path and its changes.
  PrefabInstance block;

  /// Whether its prefab could not be read: it stands empty, and saves the
  /// block it was loaded with.
  final bool missing;

  /// The prefab file.
  String get path => block.path;
}

/// On every entity a prefab instance made (its top one too): the
/// instance's top entity ([instance]) and where in the prefab it is
/// ([path], a path of the prefab's ids).
///
/// Runtime only, never saved as a component.
class PrefabLink extends Component {
  PrefabLink({required this.instance, required this.path});

  /// The top entity of the instance it belongs to.
  EntityId instance;

  /// Where it is in the prefab: `b7`, or `c3/x9` inside the nested `c3`.
  final String path;
}
