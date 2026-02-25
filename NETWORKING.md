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

### 5. Backend Server Setup (`just_game_engine_backend`)

The engine provides a standalone Python-based backend that implements the server-side logic for the modules described above (transport, session, matchmaking).

**Installation:**
```bash
# Navigate to the backend directory
cd ../../just_game_engine_backend

# Create and activate a virtual environment
python -m venv venv
source venv/bin/activate  # On Windows use: venv\\Scripts\\activate

# Install the backend package
pip install -e .
```

**Running the Server:**
The backend uses standard library `asyncio` combined with the `websockets` library for efficient real-time communication.
```bash
# Run the main server script
python src/just_game_engine_backend/main.py
```
The server will start listening for WebSocket connections (default: `ws://localhost:8080`).

---

## Integrations with External LiveOps (Firebase, Supabase, etc.)

While the `just_game_engine` networking layer handles real-time multiplayer logic natively, you may want to connect external services like **Firebase**, **Supabase**, or **PlayFab** to manage persistent data (player accounts, analytics, inventory, and global leaderboards). 

### Firebase Integration
If using Firebase, you can implement the engine's `ILeaderboardService` and `IAnalyticsService` interfaces using the standard `cloud_firestore` and `firebase_analytics` Flutter packages.
1. **Authentication:** Authenticate the user via `firebase_auth` on the client. Retrieve the user's UID and supply it to the engine's `SessionManager` as the internal Player ID.
2. **Analytics:** Create a class implementing `IAnalyticsService` that maps the engine's `flush()` batched events into `FirebaseAnalytics.instance.logEvent()`.
3. **Backend Validation:** Secure your Python server by having the backend require and verify the Firebase ID Token (using the Firebase Admin SDK for Python) upon the initial WebSocket connection.

### Supabase Integration
Supabase provides a Postgres database with real-time subscriptions, making it highly synergistic with the engine's architecture.
1. **Database & Leaderboards:** Implement `ILeaderboardService` by querying your Supabase Postgres tables natively via the `supabase_flutter` client.
2. **Matchmaking Discovery:** If you prefer database-backed matchmaking instead of the in-memory Python one, you can leverage Supabase Realtime channels. When a player creates a lobby, insert a row into a `lobbies` table. Other clients can subscribe to inserts/updates on this table to discover active lobbies seamlessly.
3. **Backend Security:** On the `just_game_engine_backend` side, use the `supabase-py` client library to validate user JWTs or securely report match results directly to the database.

---
*For testing and verification, see `test/networking/` which breaks down test suites natively per module.*
