/// Networking
///
/// Multiplayer networking module for just_game_engine.
/// Sub-barrel that re-exports all networking sub-modules:
///   • transport/   — WebSocket & UDP transport, packets, connection state
///   • matchmaking/ — rooms, lobbies, matchmaking service
///   • session/     — authenticated player session management
///   • backend/     — leaderboards, profiles, analytics, remote config
///   • gameplay/    — client prediction, lag compensation, network sync
///   • dev_tools/   — simulator, debugger, mocks for testing
library;

// ---------------------------------------------------------------------------
// Transport layer
// ---------------------------------------------------------------------------
export 'transport/packet.dart';
export 'transport/connection.dart';
export 'transport/transport_layer.dart';

// ---------------------------------------------------------------------------
// Matchmaking & Session Management
// ---------------------------------------------------------------------------
export 'matchmaking/lobby.dart';
export 'matchmaking/room.dart';
export 'matchmaking/matchmaking_service.dart';
export 'session/session_manager.dart';

// ---------------------------------------------------------------------------
// Backend & LiveOps Services
// ---------------------------------------------------------------------------
export 'backend/leaderboard_service.dart';
export 'backend/player_profile_service.dart';
export 'backend/analytics_service.dart';
export 'backend/remote_config_service.dart';

// ---------------------------------------------------------------------------
// Gameplay & Optimisation Features
// ---------------------------------------------------------------------------
export 'gameplay/prediction.dart';
export 'gameplay/lag_compensation.dart';
export 'gameplay/network_sync.dart';

// ---------------------------------------------------------------------------
// Development & Testing Tools
// ---------------------------------------------------------------------------
export 'dev_tools/network_simulator.dart';
export 'dev_tools/network_debugger.dart';
export 'dev_tools/mock_server.dart';
