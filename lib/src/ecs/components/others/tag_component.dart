library;

import '../../ecs.dart';

/// Tag component - Simple marker component
class TagComponent extends Component {
  /// Tag name
  String tag;

  /// Create a tag component
  TagComponent(this.tag);

  @override
  String toString() => 'Tag($tag)';
}
