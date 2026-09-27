/// Marks an entity a system built from other data at runtime.
library;

import '../../ecs.dart';

/// Tags an entity that a system made from other data while the game runs —
/// the static bodies a tile map's collision is built from, say.
///
/// Such an entity is not part of the level: it is rebuilt from its source
/// whenever that changes. Tools must therefore never save it, list it among
/// the authored entities or let it be picked, and a system that made it is
/// responsible for destroying it again.
class GeneratedEntityComponent extends Component {
  GeneratedEntityComponent({this.ownerId, this.source = ''});

  /// The entity whose data this one was built from, when there is one.
  final int? ownerId;

  /// What built it, for diagnostics, e.g. `'mapCollision'`.
  final String source;

  @override
  String toString() => 'Generated($source, owner: $ownerId)';
}
