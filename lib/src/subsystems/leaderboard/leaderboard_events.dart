library;

import '../../ecs/ecs.dart';

/// Fired on the ECS event bus after a score is successfully submitted.
class LeaderboardScoreSubmittedEvent extends GameEvent {
  LeaderboardScoreSubmittedEvent({
    required this.leaderboardId,
    required this.score,
  });

  final String leaderboardId;
  final int score;
}
