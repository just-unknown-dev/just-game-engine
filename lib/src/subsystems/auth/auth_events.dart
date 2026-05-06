library;

import '../../ecs/ecs.dart';
import 'auth_user.dart';

/// Fired when a player successfully signs in via any [AuthProvider].
class AuthSignedInEvent extends GameEvent {
  AuthSignedInEvent({required this.user});

  final AuthUser user;
}

/// Fired when the current player signs out.
class AuthSignedOutEvent extends GameEvent {
  AuthSignedOutEvent();
}
