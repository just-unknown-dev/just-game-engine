/// Core Engine
///
/// The main engine class that coordinates all subsystems and manages the game loop.
/// This is the entry point for initializing and running the game engine.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDownEvent, PointerEvent;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:just_inputs/just_inputs.dart';
import 'package:just_physics_engine/just_physics_engine.dart';

import '../ecs/ecs.dart';
import 'register_default_systems.dart';
import '../memory/cache_manager.dart';
import '../subsystems/assets/asset_management.dart';
import '../subsystems/audio/audio.dart';
import '../ecs/systems/camera/camera_system.dart';
import '../subsystems/input/cache_input_override_store.dart';
import '../subsystems/parallax/parallax_background.dart';
import 'game_layers.dart';
import '../subsystems/rendering/impl/game_terminal.dart';
import '../subsystems/rendering/rendering_engine.dart';
import 'engine_config.dart';
import '../ecs/base/engine_context.dart';
import 'engine_plugin.dart';
import 'engine_service.dart';
import 'game_loop.dart';
import 'system_manager.dart';
import 'time_manager.dart';

/// Main game engine class that orchestrates all subsystems
///
/// This is the primary interface for interacting with the Just Game Engine.
/// It manages initialization, update cycles, rendering, and cleanup of all
/// subsystems.
///
/// An engine is an ordinary object: make as many as you like — each has its
/// own [context], world and subsystems — and dispose each when done. Disposal
/// is final; to start over, make a new `Engine()`.
///
/// ```dart
/// final engine = Engine(
///   config: const EngineConfig(defaultSystems: DefaultSystems.all),
/// );
/// await engine.initialize();
/// engine.start();
/// // …
/// await engine.dispose();
/// ```
///
/// See [EngineState] for what may be called when.
class Engine {
  /// An engine built as [config] says, reading from [context] — or from a
  /// context of its own, made here and disposed with it, when null. The
  /// config's extensions are installed into the context at once.
  Engine({EngineConfig config = const EngineConfig(), EngineContext? context})
    : _config = config,
      context = context ?? EngineContext(),
      _ownsContext = context == null {
    this.context.installAll(config.extensions);
    for (final service in config.services) {
      unawaited(services.add(service));
    }
  }

  EngineConfig _config;

  /// How this engine is built.
  EngineConfig get config => _config;

  /// What this engine knows: component definitions, loaders, registries and
  /// the state packages keep per engine. Made with the engine, so it can be
  /// filled before [initialize]; [world] and every world given it read from
  /// it.
  final EngineContext context;

  /// Whether [context] was made for this engine, and goes with it.
  final bool _ownsContext;

  /// Plugins attached to this engine — editors, profilers, recorders. They
  /// receive every update and an overlay render; see [EnginePlugin].
  late final PluginHost plugins = PluginHost(this);

  /// Widgets drawn over the game by packages — the in-game interface — in
  /// every `GameWidget` showing this engine; see [GameLayer].
  final GameLayers layers = GameLayers();

  /// The services this engine runs — started with it, stopped with it; see
  /// [EngineService]. Declared in [EngineConfig.services], or added here.
  late final ServiceHost services = newServiceHost(this);

  /// The service of type [T]. Throws a [StateError] saying how to add it
  /// when this engine has none.
  T service<T extends EngineService>() => services.get<T>();

  /// The service of type [T], or null.
  T? maybeService<T extends EngineService>() => services.maybe<T>();

  /// In-game developer terminal for cheat commands and debug tooling.
  ///
  /// Register commands via [GameTerminal.registerCommand] before calling
  /// `GameWidget` so the commands are available when the terminal opens.
  final GameTerminal terminal = GameTerminal();

  // ── State ───────────────────────────────────────────────────────────────

  final ValueNotifier<EngineState> _stateNotifier = ValueNotifier(
    EngineState.uninitialized,
  );

  EngineState get _state => _stateNotifier.value;
  set _state(EngineState value) => _stateNotifier.value = value;

  /// Where the engine is in its life; see [EngineState].
  EngineState get state => _state;

  /// [state], as something to listen to: it notifies on every change —
  /// when [initialize] finishes, say. `GameWidget` uses it to start drawing
  /// an engine it was given before the engine was ready. It is never
  /// disposed, so a listener may be removed at any time, also after
  /// [dispose].
  ValueListenable<EngineState> get stateListenable => _stateNotifier;

  EngineInitException? _lastError;

  /// Why the last [initialize] failed, while the engine is
  /// [EngineState.failed]; null otherwise.
  EngineInitException? get lastError => _lastError;

  /// Whether the engine is ready: initialized, running or paused.
  bool get isInitialized =>
      _state == EngineState.initialized ||
      _state == EngineState.running ||
      _state == EngineState.paused;

  /// Check if engine is running
  bool get isRunning => _state == EngineState.running;

  /// Check if engine is paused
  bool get isPaused => _state == EngineState.paused;

  /// Whether [dispose] has been called — true from its first moment, while
  /// it is still finishing.
  bool get isDisposed =>
      _state == EngineState.disposing || _state == EngineState.disposed;

  // ── Session subsystems: made by initialize, gone after dispose ──────────

  SystemManager? _systemManager;
  GameLoop? _gameLoop;
  TimeManager? _timeManager;
  RenderingEngine? _rendering;
  PhysicsEngine? _physics;
  InputService? _input;
  AudioEngine? _audio;
  MusicManager? _music;
  SoundEffectManager? _sfx;
  CacheManager? _cache;
  CameraSystem? _cameraSystem;
  ParallaxSystem? _parallax;
  World? _world;

  T _ready<T extends Object>(T? value, String member) =>
      value ?? (throw EngineNotReadyError(member, _state));

  /// Public access to the system manager (e.g. for reading [SystemManager.schedulerStats]).
  SystemManager get systemManager => _ready(_systemManager, 'systemManager');

  /// Public access to the game loop (e.g. for reading [GameLoop.currentFPS]).
  GameLoop get gameLoop => _ready(_gameLoop, 'gameLoop');

  /// Get the current time manager
  TimeManager get time => _ready(_timeManager, 'time');

  /// Draws the game.
  RenderingEngine get rendering => _ready(_rendering, 'rendering');

  /// The physics simulation — Box2D FFI on native platforms, pure-Dart on
  /// web. [PhysicsEngine.initialize] runs in [initialize], so bodies can be
  /// added before any [PhysicsSystem] exists, but **stepping**
  /// (`physics.update`) is owned by [PhysicsSystem] when one is registered
  /// in [world], not by this `Engine`'s own update loop — that keeps a
  /// frame's gameplay-set velocity reaching the physics step the same frame
  /// it was set instead of lagging a frame behind. If no [PhysicsSystem] is
  /// in [world], bodies added here simply won't advance.
  PhysicsEngine get physics => _ready(_physics, 'physics');

  /// The game's input: devices, the input asset, players. Starts with no
  /// actions — the game loads its asset after [initialize]. Updated once per
  /// fixed step, and every frame while paused so menus and rebinding still
  /// hear it.
  InputService get input => _ready(_input, 'input');

  /// Sound and music. On the web it starts at the first key or pointer
  /// press (see [EngineConfig.deferAudioUntilInput]).
  AudioEngine get audio => _ready(_audio, 'audio');

  /// Background music — play, fade, pause, stop — played through [audio].
  MusicManager get music => _ready(_music, 'music');

  /// One-shot and looping sound effects, played through [audio].
  SoundEffectManager get sfx => _ready(_sfx, 'sfx');

  /// Persistent key-value and binary storage.
  CacheManager get cache => _ready(_cache, 'cache');

  /// The output camera and the brain that drives it.
  CameraSystem get cameraSystem => _ready(_cameraSystem, 'cameraSystem');

  /// The parallax backgrounds drawn behind the world, as a list.
  @Deprecated(
    'Add a ParallaxComponent to an entity; ParallaxRenderSystem (a default '
    'system) scrolls and draws it. Removed in 3.0.',
  )
  ParallaxSystem get parallax => _ready(_parallax, 'parallax');

  /// The ECS world the game runs in, reading from [context].
  World get world => _ready(_world, 'world');

  /// Loads, caches and releases the game's images, audio, text and atlases;
  /// its context's ([EngineContext.assets]), so it is there before
  /// [initialize].
  AssetManager get assets => context.assets;

  // ── Frame bookkeeping ───────────────────────────────────────────────────

  /// The input clock: real seconds, advanced by each fixed step (before time
  /// scale, so a hold takes as long in slow motion) and by the frame while
  /// paused.
  double _inputTime = 0;

  /// Last measured subsystem update costs in milliseconds.
  final Map<String, double> _lastUpdateBreakdownMs = <String, double>{};

  double _lastUpdateTotalMs = 0.0;
  double _lastDeltaTime = 0.0;
  int _frameNumber = 0;

  /// Latest per-frame performance snapshot. Safe to read in any state.
  Map<String, dynamic> get performanceStats => {
    'frame': _frameNumber,
    'deltaTime': _lastDeltaTime,
    'lastUpdateMs': _lastUpdateTotalMs,
    'budgetRemainingMs': 16.67 - _lastUpdateTotalMs,
    'isOverBudget': _lastUpdateTotalMs > 16.67,
    'systemTimesMs': Map<String, double>.unmodifiable(_lastUpdateBreakdownMs),
    'scheduler': _systemManager?.schedulerStats ?? const <String, dynamic>{},
  };

  // ── Initialize ──────────────────────────────────────────────────────────

  /// What undoes each stage [initialize] completed, in the order they were
  /// built; run backwards by [dispose] or a failed [initialize]. An entry
  /// may return a Future for work that finishes later (audio shutdown).
  final List<Future<void>? Function()> _teardown = [];

  Future<void>? _initializing;

  /// Builds the engine's subsystems and world. Call once, before [start].
  ///
  /// Stages run in order — core, cache, input, audio, physics, rendering,
  /// world, subsystems, services — each undone by [dispose]. If one throws,
  /// everything already built is undone, [state] becomes
  /// [EngineState.failed], and an [EngineInitException] naming the stage is
  /// thrown (and kept in [lastError]); `initialize` may then be called
  /// again.
  ///
  /// Called while it is already running, it returns the same Future. Called
  /// on an initialized engine it throws a [StateError], and on a disposed
  /// one a [StateError] saying to make a new `Engine()`.
  ///
  /// [config], when given, replaces the constructor's (its extensions are
  /// installed) — kept for code written for 1.x; prefer
  /// `Engine(config: ...)`.
  Future<void> initialize({EngineConfig? config}) {
    switch (_state) {
      case EngineState.initializing:
        return _initializing!;
      case EngineState.initialized || EngineState.running || EngineState.paused:
        throw StateError('Engine is already initialized');
      case EngineState.disposing || EngineState.disposed:
        throw StateError(_disposedMessage);
      case EngineState.uninitialized || EngineState.failed:
        break;
    }
    if (config != null) {
      _config = config;
      context.installAll(config.extensions);
      for (final service in config.services) {
        unawaited(services.add(service));
      }
    }
    _state = EngineState.initializing;
    _lastError = null;
    return _initializing = _runInitialize().whenComplete(
      () => _initializing = null,
    );
  }

  static const String _disposedMessage =
      'This Engine was disposed; create a new Engine().';

  Future<void> _runInitialize() async {
    debugPrint('Initializing Just Game Engine...');
    var stage = 'core';
    try {
      // 1. core
      final time = _timeManager = TimeManager();
      final systems = _systemManager = SystemManager();
      await systems.initialize();
      _gameLoop = GameLoop(
        onUpdate: _update,
        onRender: _frame,
        timeManager: time,
      );
      _teardown.add(() {
        _gameLoop?.stop();
        _systemManager?.dispose();
        _gameLoop = null;
        _systemManager = null;
        _timeManager = null;
        return null;
      });

      // 2. cache
      stage = 'cache';
      final cache = _cache = CacheManager();
      _teardown.add(() {
        _cache?.dispose();
        _cache = null;
        return null;
      });
      await cache.initialize();

      // 3. input — players' own bindings live in the cache.
      stage = 'input';
      final input = _input = InputService();
      _teardown.add(() {
        _input?.dispose();
        _input = null;
        return null;
      });
      input.overrideStore = CacheInputOverrideStore(cache);

      // 4. audio — optional: a failure is logged and the rest goes on.
      stage = 'audio';
      await _startAudio();

      // 5. physics
      stage = 'physics';
      final physics = _physics = PhysicsEngine();
      _teardown.add(() {
        _physics?.dispose();
        _physics = null;
        return null;
      });
      physics.initialize();
      // The project's collision layers, when it has a file of them.
      await context.loadPhysicsLayers();

      // 6. rendering, and the camera and parallax it draws with
      stage = 'rendering';
      final cameras = _cameraSystem = CameraSystem();
      final parallax = _parallax = ParallaxSystem();
      final rendering = _rendering =
          _config.createRendering?.call() ?? RenderingEngine();
      _teardown.add(() {
        _rendering?.dispose();
        _parallax?.dispose();
        _cameraSystem?.dispose();
        _rendering = null;
        _parallax = null;
        _cameraSystem = null;
        return null;
      });
      cameras.initialize(); // Before rendering, which draws through it.
      parallax.initialize();
      rendering.camera = cameras.mainCamera;
      rendering.backgroundHooks.add(parallax.render);
      // Plugins draw over the world (order 100 — after the world's own hook,
      // which GameWidget adds at the default order).
      rendering.overlayHooks.addIfAbsent(plugins.renderOverlay, order: 100);
      rendering.initialize();

      // 7. world
      stage = 'world';
      final world = _world = World(context: context);
      _teardown.add(() {
        // Before physics and rendering: its systems take out what they put
        // into them (joints, post-process passes) while both still live.
        _world?.dispose();
        _world = null;
        return null;
      });
      world.initialize();
      if (_config.defaultSystems.isNotEmpty) {
        registerDefaultSystems(world, this, include: _config.defaultSystems);
      }

      // 8. subsystems and the frame's update tasks
      stage = 'subsystems';
      _registerSystems();

      // 9. services, in the order they were declared or added
      stage = 'services';
      _teardown.add(() {
        // Every stop() is called now, while the world still exists; the
        // engine waits for them at the end of dispose().
        final stopping = services.stopAllForEngine();
        return stopping.isEmpty ? null : _settle(stopping);
      });
      try {
        await services.startAllForEngine();
      } catch (error) {
        final failed = serviceFailureOf(error);
        if (failed == null) rethrow;
        stage = 'service:${failed.service.runtimeType}';
        Error.throwWithStackTrace(failed.error, failed.stack);
      }

      _state = EngineState.initialized;
      debugPrint('Engine initialized successfully');
    } catch (error, stack) {
      debugPrint('Failed to initialize engine ($stage): $error');
      final pending = _runTeardown();
      _state = EngineState.failed;
      final failure = _lastError = EngineInitException(stage, error, stack);
      await _settle(pending);
      throw failure;
    }
  }

  /// Starts the audio engine — at once, or on the web at the first key or
  /// pointer press: a browser keeps an audio context made before any user
  /// gesture suspended, and just_audio_engine makes its context when it
  /// initialises.
  Future<void> _startAudio() async {
    final audio = _audio = _config.createAudio?.call() ?? AudioEngine();
    _music = MusicManager(audio);
    _sfx = SoundEffectManager(audio);
    void Function()? stopWaiting;
    _teardown.add(() {
      stopWaiting?.call();
      _audio = null;
      _music = null;
      _sfx = null;
      // As in initialize: with no audio plugin — headless, tests, a platform
      // without one — shutting down fails asynchronously.
      return audio.dispose().catchError((Object e) {
        debugPrint('AudioEngine: dispose skipped (${e.runtimeType})');
      });
    });
    if (_config.deferAudioUntilInput ?? kIsWeb) {
      stopWaiting = _onFirstInput(() => unawaited(_initializeAudio(audio)));
    } else {
      await _initializeAudio(audio);
    }
  }

  static Future<void> _initializeAudio(AudioEngine audio) async {
    try {
      await audio.initialize();
    } catch (e) {
      debugPrint('AudioEngine: initialization skipped (${e.runtimeType})');
    }
  }

  /// Calls [then] once, at the next key press or pointer press anywhere in
  /// the app. Returns what stops waiting.
  static void Function() _onFirstInput(void Function() then) {
    var done = false;
    late final bool Function(KeyEvent) onKey;
    late final void Function(PointerEvent) onPointer;
    void stop() {
      if (done) return;
      done = true;
      HardwareKeyboard.instance.removeHandler(onKey);
      GestureBinding.instance.pointerRouter.removeGlobalRoute(onPointer);
    }

    onKey = (_) {
      stop();
      then();
      return false;
    };
    onPointer = (event) {
      if (event is! PointerDownEvent) return;
      stop();
      then();
    };
    HardwareKeyboard.instance.addHandler(onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(onPointer);
    return stop;
  }

  /// Register all systems with the system manager
  ///
  /// Keyed by the declared types (see [SystemManager.registerSystem]), so
  /// [subsystem] finds them by those types.
  void _registerSystems() {
    final systems = _systemManager!;
    systems
      ..registerSystem<RenderingEngine>('rendering', rendering)
      ..registerSystem<PhysicsEngine>('physics', physics)
      ..registerSystem<InputService>('input', input)
      ..registerSystem<AudioEngine>('audio', audio)
      ..registerSystem<CacheManager>('cache', cache)
      ..registerSystem<AssetManager>('assets', assets)
      ..registerSystem<CameraSystem>('camera', cameraSystem)
      ..registerSystem<ParallaxSystem>('parallax', parallax)
      ..registerSystem<World>('ecs', world);

    systems.registerUpdateTask('input', (_) {
      _inputTime += gameLoop.fixedDeltaTime;
      input.update(_inputTime);
    });
    systems.registerUpdateTask(
      'camera',
      (deltaTime) => cameraSystem.update(deltaTime),
    );
    systems.registerUpdateTask(
      'parallax',
      (deltaTime) =>
          parallax.update(deltaTime, cameraSystem.mainCamera.position),
    );
    // No standalone 'physics' task here — see the doc comment on [physics]
    // above. PhysicsSystem steps it inline within the 'ecs' task below.
    systems.registerUpdateTask(
      'particles',
      (deltaTime) => rendering.updateManagedEmitters(deltaTime),
    );
    systems.registerUpdateTask('audio', (_) => audio.update());
    systems.registerUpdateTask('ecs', (deltaTime) => world.update(deltaTime));
  }

  // ── Running ─────────────────────────────────────────────────────────────

  /// Start the game engine and begin the game loop.
  ///
  /// Throws a [StateError] unless the engine is [EngineState.initialized]
  /// (not yet started, or stopped).
  void start() {
    if (isDisposed) throw StateError(_disposedMessage);
    if (_state != EngineState.initialized) {
      throw StateError(
        'Engine.start() needs an initialized engine that is not running '
        '(state: ${_state.name}).',
      );
    }
    debugPrint('Starting game engine...');
    _state = EngineState.running;
    gameLoop.start();
  }

  /// Pause the game engine
  ///
  /// This will pause the update loop but continue rendering. Anywhere but
  /// [EngineState.running] it does nothing: a menu may ask twice.
  void pause() {
    if (_state != EngineState.running) {
      debugPrint('Engine is not running');
      return;
    }

    debugPrint('Pausing engine...');
    _state = EngineState.paused;
    gameLoop.pause();
  }

  /// Resume the game engine from paused state; anywhere else it does
  /// nothing.
  void resume() {
    if (_state != EngineState.paused) {
      debugPrint('Engine is not paused');
      return;
    }

    debugPrint('Resuming engine...');
    _state = EngineState.running;
    gameLoop.resume();
  }

  /// Stop the game engine: back to [EngineState.initialized]. Anywhere but
  /// running or paused it does nothing.
  void stop() {
    if (_state != EngineState.running && _state != EngineState.paused) {
      debugPrint('Engine is not running');
      return;
    }

    debugPrint('Stopping engine...');
    gameLoop.stop();
    _state = EngineState.initialized;
  }

  /// Update the engine state (called every frame)
  /// Once per frame, after the fixed steps: plugins tick here, on wall-clock
  /// time, so an editor keeps working while the game is paused or its time
  /// scale is zero.
  void _frame() {
    final time = _timeManager;
    if (time == null) return;
    // Paused, the fixed steps stop — but a menu still needs its buttons, and
    // a rebind its keys.
    if (isPaused) {
      _inputTime += time.unscaledDeltaTime;
      input.update(_inputTime);
    }
    plugins.update(time.unscaledDeltaTime);
  }

  void _update(double deltaTime) {
    if (_state != EngineState.running) return;
    final systems = _systemManager!;

    _frameNumber++;
    _lastDeltaTime = deltaTime;

    systems.runUpdateCycle(deltaTime);
    _lastUpdateBreakdownMs
      ..clear()
      ..addAll(systems.lastTaskTimesMs);
    _lastUpdateTotalMs = systems.lastFrameMs;
  }

  // ── Dispose ─────────────────────────────────────────────────────────────

  Future<void>? _disposing;

  /// Shuts the engine down, for good: plugins detach, services are told to
  /// stop, then the world goes — before physics and rendering, so its
  /// systems can take out what they put into them — then rendering,
  /// physics, audio, input, cache and the core; then the layers and
  /// terminal. Once every service has stopped and audio has shut down, the
  /// context goes too, when this engine made it.
  ///
  /// Everything but that slow part is done before this returns its Future,
  /// so not awaiting it is safe; await it where the next thing must not
  /// overlap (a test's tear-down). Called during [initialize], it
  /// waits for it and then disposes. Calling it again does nothing more.
  /// A disposed engine cannot be used again: make a new `Engine()`.
  Future<void> dispose() {
    final running = _disposing;
    if (running != null) return running;
    switch (_state) {
      case EngineState.disposed:
        return Future.value();
      case EngineState.initializing:
        // Once it has finished — built, or failed and undone — dispose.
        return _disposing = _initializing!
            .then<void>((_) {}, onError: (Object _) {})
            .then((_) {
              _disposing = null;
              return dispose();
            });
      default:
        break;
    }
    debugPrint('Shutting down engine...');
    _state = EngineState.disposing;
    _gameLoop?.stop();
    plugins.detachAll();
    final pending = _runTeardown();
    layers
      ..clear()
      ..dispose();
    terminal.dispose();
    return _disposing = _settle(pending).whenComplete(() {
      // Last: services may use the context (their databases live in it)
      // until their stop() has finished.
      if (_ownsContext) context.dispose();
      _state = EngineState.disposed;
      debugPrint('Engine shutdown complete');
    });
  }

  /// Runs the teardown stack backwards, each entry guarded, and returns the
  /// Futures of the entries still finishing.
  List<Future<void>> _runTeardown() {
    final pending = <Future<void>>[];
    while (_teardown.isNotEmpty) {
      final undo = _teardown.removeLast();
      try {
        final future = undo();
        if (future != null) pending.add(future);
      } catch (error, stack) {
        debugPrint('Engine: a teardown step failed: $error\n$stack');
      }
    }
    return pending;
  }

  static Future<void> _settle(List<Future<void>> pending) async {
    for (final future in pending) {
      try {
        await future;
      } catch (error) {
        debugPrint('Engine: a teardown step failed: $error');
      }
    }
  }

  // ── Lookup ──────────────────────────────────────────────────────────────

  /// The engine subsystem registered under type [T] — `RenderingEngine`,
  /// `PhysicsEngine`, `ParallaxSystem`, … — or null (also before
  /// [initialize] and after [dispose]).
  ///
  /// Subsystems are keyed by the type they were registered under (see
  /// [SystemManager.registerSystem]). ECS systems live in the world: find
  /// those with `world.getSystem<T>()`.
  T? subsystem<T extends Object>() => _systemManager?.getSystem<T>();

  /// Get a reference to a specific subsystem
  ///
  /// Returns null if the system is not found.
  @Deprecated('Use subsystem<T>(); World.getSystem<T>() finds ECS systems.')
  T? getSystem<T extends Object>() => subsystem<T>();
}

/// Where an [Engine] is in its life.
///
/// ```text
/// uninitialized ─initialize()→ initializing ─ok→ initialized ─start()→ running
///       ↑                           │ throws           ↑  ↑                │ ↑
///       └──── initialize() ──── failed                 │  └── stop() ──────┤ │
///                                                      │        pause()/resume()
///                                                      │              paused
/// any state ─dispose()→ disposing → disposed (final: make a new Engine)
/// ```
enum EngineState {
  /// Made, not yet initialized.
  uninitialized,

  /// [Engine.initialize] is running.
  initializing,

  /// Ready, not running.
  initialized,

  /// Running and updating.
  running,

  /// Paused: rendering, not updating.
  paused,

  /// [Engine.initialize] failed and undid what it had built; it may be
  /// called again. [Engine.lastError] says why.
  failed,

  /// [Engine.dispose] is finishing.
  disposing,

  /// Disposed, for good.
  disposed,
}

/// Why [Engine.initialize] failed: the [stage] that threw, and what it
/// threw.
final class EngineInitException implements Exception {
  /// The failure of [stage], which threw [cause] at [stackTrace].
  EngineInitException(this.stage, this.cause, this.stackTrace);

  /// The stage that failed: `core`, `cache`, `input`, `audio`, `physics`,
  /// `rendering`, `world`, `subsystems`, `services` (or `service:<Type>`).
  final String stage;

  /// What it threw.
  final Object cause;

  /// Where.
  final StackTrace stackTrace;

  @override
  String toString() =>
      'EngineInitException: the engine could not initialize ($stage): '
      '$cause';
}

/// An engine subsystem was asked for when there is none: before
/// [Engine.initialize] has built it, or after [Engine.dispose].
final class EngineNotReadyError extends StateError {
  /// The error for asking for [member] while the engine is in [state]; the
  /// message says what to do about it (initialize first, or make a new
  /// engine).
  EngineNotReadyError(this.member, this.state)
    : super(
        'Engine.$member is not available while the engine is ${state.name}: '
        '${switch (state) {
          EngineState.disposing || EngineState.disposed => 'this engine was disposed; create a new Engine().',
          EngineState.failed => 'initialize() failed — see Engine.lastError.',
          _ => 'call and await initialize() first.',
        }}',
      );

  /// What was asked for.
  final String member;

  /// The engine's state then.
  final EngineState state;
}
