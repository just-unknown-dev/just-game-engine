# Multiplayer Networking Documentation

The `just_game_engine` networking layer offers a robust and modular foundation for building real-time multiplayer games. It includes modules for transport-level abstractions, session management, client-side prediction, lag compensation, matchmaking, and backend services.

## Architecture & Core Modules

The networking package is broken down into the following submodules:

### 1. Transport (`transport/`)
The transport layer abstracts away raw networking into unified interfaces.
- **`NetworkManager`**: The top-level service for handling connections and dispatching packets. You inject your preferred `NetworkTransport` during initialization.
- **`NetworkTransport`**: An abstraction implemented by `WebSocketTransport` (default, works across all platforms) and `UdpTransport` (stub for low-latency needs).
- **`NetworkPacket`**: The core data container. Packets have sequences, types (`reliable`, `unreliable`, `ping`, etc.), and a JSON payload.

### 2. Gameplay (`gameplay/`)
Optimizations that make networked logic feel instantaneous on the client.
- **`ClientPrediction`**: Allows a client to apply its own `InputSnapshot` locally before the server acknowledges it. Upon server update, it reconciles by dropping acknowledged inputs and replaying the rest.
- **`NetworkSyncManager`**: Automates the broadcasting of local object transforms and processes incoming updates of remote objects. 
- **`LagCompensator`**: Uses a `SnapshotBuffer` to keep historical data chunks. It interpolates between server snapshots at a fixed delay to smooth out remote players' movements despite network jitter.

### 3. Matchmaking (`matchmaking/`)
Helps players find each other or assemble before starting a logic session.
- **`Lobby`**: The pre-game phase. Manages player slots, readiness (`LobbyPlayer.isReady`), host assignment, and countdown timers.
- **`Room`**: An active game session tracking the roster of connected players, topology (dedicated vs P2P), and state.
- **`IMatchmakingService`**: Facilitates finding a match based on criteria, creating a room, or listing open rooms. Includes an in-memory `MatchmakingService` for testing.

### 4. Session (`session/`)
Tracks authenticated user state.
- **`SessionManager`**: Holds the currently active `PlayerSession` and tracks expirations and token renewals.

### 5. Backend (`backend/`)
Interfaces for integrating external LiveOps features.
- **`ILeaderboardService`**: Standardizes global or weekly score submissions, local neighborhood lookups, and score deletion.
- **`IAnalyticsService`**: Flushes generic `GameEvent` structures (w/ dimensions like elapsed duration, properties) for data warehousing.

### 6. Dev Tools (`dev_tools/`)
Utilities for local debugging and simulation.
- **`NetworkSimulator`**: Wraps any `NetworkTransport` in debug mode to forcefully inject artificial latency, jitter, and packet loss (e.g. `SimulatorConfig.poor`). 

---

## Examples & Workflows

### 1. Setting Up the Network Manager
```dart
final transport = WebSocketTransport();
final networkManager = NetworkManager();

networkManager.initialize(transport);
await networkManager.connect('localhost', 8080);

networkManager.on(PacketType.reliable, (packet) {
  print('Received data: ${packet.payload}');
});

networkManager.sendData({'action': 'jump'});
```

### 2. Client-Side Prediction
```dart
final prediction = ClientPrediction(
  initialPosition: Offset.zero,
  movementFunction: (pos, vel, input, dt) => (pos + input * 100 * dt, vel),
);

// Apply player input for current frame internally
final snapshot = prediction.applyInput(Offset(1, 0), 0.016);
// Send snapshot to the authoritative server
networkManager.sendData({'input': snapshot.toJson()}, type: PacketType.reliable);

// Once the server responds with authoritative state...
prediction.reconcile(serverAckedSequenceNumber, authoritativeServerPosition);
```

### 3. Network Sync & Lag Compensation
```dart
// Lag compensation smooths out variables over time
final compensator = LagCompensator(interpolationDelayMs: 100);

final syncManager = NetworkSyncManager(
  networkManager: networkManager,
  lagCompensator: compensator,
);

// Publish local player positions continuously
syncManager.registerLocalObject('player_id', () => SyncedTransform(
  objectId: 'player_id',
  position: currentPlayer.position,
  sequenceNumber: currentSeq,
));

// Each frame, retrieve the smoothed remote transforms
final remoteEntities = syncManager.getInterpolatedRemoteStates();
```

### 4. Lobby Matching
```dart
final lobby = Lobby(minPlayers: 2, maxPlayers: 4, countdownSeconds: 5);

lobby.onLobbyReady(() {
  print('Lobby filled and countdown finished! Starting match.');
});

lobby.addPlayer(LobbyPlayer(playerId: 'p1', displayName: 'Player 1'));
lobby.setReady('p1', ready: true);
```

---
*For testing and verification, see `test/networking/` which breaks down test suites natively per module.*
