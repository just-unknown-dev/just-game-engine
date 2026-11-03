// Support for fx_ecs_world_test.dart: a component type with the same name as
// one declared there, from another library. Not a test itself.

import 'package:just_game_engine/just_game_engine.dart';

/// Shares its name with the test's own `Health`, and nothing else.
class Health extends Component {
  Health(this.value);
  final int value;
}
