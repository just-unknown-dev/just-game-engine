part of 'particles.dart';

/// Particle emitter — the core class of the advanced particle system.
///
/// A [ParticleEmitter] extends [Renderable] so it can be added directly to the
/// [RenderingEngine] or attached to an ECS entity via [ParticleEmitterComponent].
///
/// ## Quick-start (standalone)
/// ```dart
/// final emitter = ParticleEffects.fire(position: Offset(400, 300));
/// renderingEngine.addManagedEmitter(emitter); // automatically updated + rendered
/// ```
///
/// ## Custom effect
/// ```dart
/// final emitter = ParticleEmitter(
///   maxParticles: 200,
///   emissionRate: 60,
///   particleLifetime: 1.5,
///   renderer: SpriteParticleRenderer(image: myFlameImage),
///   forces: [
///     GravityForce(const Offset(0, -80)),
///     WindForce(turbulence: 30),
///     DragForce(coefficient: 0.05),
///   ],
///   subEmitters: [
///     SubEmitterConfig(
///       trigger: SubEmitterTrigger.onDeath,
///       factory: (pos) => ParticleEffects.sparkle(position: pos),
///     ),
///   ],
/// );
/// ```
class ParticleEmitter extends Renderable {
  // ── Configuration ─────────────────────────────────────────────────────────

  /// Maximum number of live particles at any time.
  final int maxParticles;

  /// Particles emitted per second.
  double emissionRate;

  /// Base particle lifetime in seconds.
  final double particleLifetime;

  /// ± variation in lifetime (uniform distribution).
  final double lifetimeVariation;

  /// Starting size in world units.
  final double startSize;

  /// Ending size at end of lifetime.
  final double endSize;

  /// ± variation in start size (uniform distribution).
  final double sizeVariation;

  /// Color at birth.
  final Color startColor;

  /// Color at death.
  final Color endColor;

  /// Emission cone angle (radians, measured from the positive-X axis).
  final double emissionAngle;

  /// Half-angle of the emission cone (radians).  Use `math.pi * 2` for
  /// omnidirectional.
  final double emissionSpread;

  /// Base initial speed (world units/sec).
  final double speed;

  /// ± variation in initial speed (world units/sec).
  final double speedVariation;

  /// Base initial angular velocity (radians/sec).  Combined with
  /// [angularVelocityVariation] to randomize rotation per particle.
  final double angularVelocity;

  /// ± variation in angular velocity (radians/sec).
  final double angularVelocityVariation;

  /// Renderer that draws individual particles: a [CircleParticleRenderer]
  /// if none is supplied.
  late final ParticleRenderer _renderer;

  /// Forces applied to each particle every frame.
  final List<ParticleForce> _forces;

  /// Optional custom behavior (spawn / update / death hooks).
  final ParticleEffect? effect;

  /// Sub-emitter configurations.
  final List<SubEmitterConfig> subEmitters;

  /// Optional fragment shader applied around the entire emitter via
  /// [Canvas.saveLayer].  Pass a [ui.FragmentShader] instance together with
  /// [shaderBoundsInflation] to tune the clip rect.
  final ui.FragmentShader? shader;

  /// Inflation (pixels) added to the emitter bounds used as the `saveLayer`
  /// clip rect when [shader] is non-null.
  final double shaderBoundsInflation;

  /// Whether to use batched rendering when the renderer supports it.
  ///
  /// [SpriteParticleRenderer], [TextParticleRenderer] and a batched
  /// [CircleParticleRenderer] override `renderBatch`; the other renderers
  /// fall through to the per-particle render loop regardless of this flag.
  final bool useBatching;

  /// Auto-stop emitting after [duration] seconds (null = infinite).
  final double? duration;

  // ── Runtime state ─────────────────────────────────────────────────────────

  /// Whether the emitter is currently emitting new particles.
  bool isEmitting = true;

  final List<Particle> _particles = [];
  late final ObjectPool<Particle> _particlePool;
  double _emissionAccumulator = 0.0;
  double _totalTime = 0.0;
  final math.Random _random = math.Random();

  /// Active sub-emitters spawned by this emitter's particles.
  final List<ParticleEmitter> _activeSubEmitters = [];

  /// Tracks which [SubEmitterConfig] spawned each active sub-emitter so the
  /// [maxInstances] cap can be enforced without calling the factory again.
  final Map<ParticleEmitter, SubEmitterConfig> _subEmitterOrigins = {};

  /// The lifetime-fraction sub-emitters, in fraction order. Each particle
  /// counts how many of them it has set off, so each fires once per
  /// particle. (They were once keyed by the particle's index in the live
  /// list, which shifts as dead particles are removed, and the keys were
  /// never cleared — later particles at a used index never fired.)
  late final List<SubEmitterConfig> _milestones = [
    for (final c in subEmitters)
      if (c.trigger == SubEmitterTrigger.onLifetimeFraction) c,
  ]..sort((a, b) => a.lifetimeFraction.compareTo(b.lifetimeFraction));

  // Reusable Paint for shader saveLayer
  final Paint _shaderPaint = Paint();

  /// Create a [ParticleEmitter].
  ParticleEmitter({
    required this.maxParticles,
    this.emissionRate = 10,
    this.particleLifetime = 1.0,
    this.lifetimeVariation = 0.2,
    this.startSize = 5.0,
    this.endSize = 1.0,
    this.sizeVariation = 1.0,
    this.startColor = Colors.white,
    this.endColor = Colors.transparent,
    this.emissionAngle = 0.0,
    this.emissionSpread = math.pi * 2,
    this.speed = 100.0,
    this.speedVariation = 20.0,
    this.angularVelocity = 0.0,
    this.angularVelocityVariation = 0.0,
    ParticleRenderer? renderer,
    List<ParticleForce>? forces,
    this.effect,
    this.subEmitters = const [],
    this.shader,
    this.shaderBoundsInflation = 20.0,
    this.useBatching = true,
    this.duration,
    super.position,
    super.layer,
    super.zOrder,
  }) : assert(maxParticles > 0),
       assert(emissionRate >= 0),
       assert(particleLifetime > 0),
       _forces = [...?forces] {
    _renderer = renderer ?? CircleParticleRenderer();
    _particlePool = ObjectPool<Particle>(
      create: _createPooledParticle,
      reset: _resetPooledParticle,
      maxSize: maxParticles,
      initialSize: math.min(maxParticles, 64),
    );
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  Particle _createPooledParticle() => Particle(
    position: position.toOffset(),
    velocity: Offset.zero,
    lifetime: particleLifetime,
    startSize: startSize,
    endSize: endSize,
    startColor: startColor,
    endColor: endColor,
  );

  void _resetPooledParticle(Particle particle) {
    particle
      ..customData = null
      ..age = particle.lifetime
      ..vx = 0.0
      ..vy = 0.0
      ..angularVelocity = 0.0
      ..previousX = particle.x
      ..previousY = particle.y;
  }

  /// The renderer used by this emitter.
  ParticleRenderer get renderer => _renderer;

  /// All forces currently applied to this emitter's particles.
  List<ParticleForce> get forces => List.unmodifiable(_forces);

  /// Number of currently live particles.
  int get particleCount => _particles.length;

  /// Number of recycled particles currently available for reuse.
  int get pooledParticleCount => _particlePool.availableCount;

  /// Whether this emitter has finished emitting AND has no live particles
  /// — its own, or its sub-emitters' (a firework's sparks).
  bool get isComplete =>
      !isEmitting && _particles.isEmpty && _activeSubEmitters.isEmpty;

  // ── Update ────────────────────────────────────────────────────────────────

  /// Advance the emitter by [deltaTime] seconds.
  ///
  /// Must be called once per frame.  Both [RenderingEngine.updateManagedEmitters]
  /// and [ParticleSystemECS] call this automatically.
  void update(double deltaTime) {
    final startedAt = _totalTime;
    _totalTime += deltaTime;
    final limit = duration;

    // Emit new particles — for the part of the frame inside [duration], so
    // a burst shorter than the first frame still bursts.
    if (isEmitting) {
      final emitting = limit == null
          ? deltaTime
          : math.max(0.0, math.min(deltaTime, limit - startedAt));
      _emissionAccumulator += emitting * emissionRate;
      while (_emissionAccumulator >= 1.0 && _particles.length < maxParticles) {
        _emitParticle();
        _emissionAccumulator -= 1.0;
      }
      // Held back by maxParticles: what could not be emitted is dropped,
      // not saved up to pour out once there is room (or after the rate
      // drops to 0).
      if (_emissionAccumulator >= 1.0) {
        _emissionAccumulator -= _emissionAccumulator.floorToDouble();
      }
    }

    // Stop emitting after duration
    if (limit != null && _totalTime >= limit) {
      isEmitting = false;
    }

    // Forces' own clocks move on once a frame, not once per particle.
    for (var i = 0; i < _forces.length; i++) {
      _forces[i].advance(deltaTime);
    }

    // Update + cull particles using in-place compaction to avoid per-frame
    // allocations from temporary removal lists.
    int writeIndex = 0;
    for (int i = 0; i < _particles.length; i++) {
      final p = _particles[i];

      // Tick via effect if present, otherwise direct
      if (effect != null) {
        effect!.onUpdate(p, deltaTime, _forces);
      } else {
        p.update(deltaTime, _forces);
      }

      // Check milestone sub-emitters
      if (_milestones.isNotEmpty) _checkMilestones(p);

      if (p.isDead) {
        // On-death callback
        effect?.onDeath(p, this);

        // Spawn death sub-emitters
        _spawnSubEmitters(p, SubEmitterTrigger.onDeath);

        // Recycle
        _particlePool.release(p);
      } else {
        _particles[writeIndex++] = p;
      }
    }
    _particles.length = writeIndex;

    // Update sub-emitters; remove completed ones
    _activeSubEmitters.removeWhere((se) {
      se.update(deltaTime);
      if (se.isComplete) {
        _subEmitterOrigins.remove(se);
        return true;
      }
      return false;
    });
  }

  /// Sets off each lifetime-fraction sub-emitter [p] has reached and not
  /// yet set off — all of them, should one frame pass several.
  void _checkMilestones(Particle p) {
    final life = p.normalizedLife;
    while (p._milestones < _milestones.length &&
        life >= _milestones[p._milestones].lifetimeFraction) {
      _spawn(p, _milestones[p._milestones]);
      p._milestones++;
    }
  }

  void _spawnSubEmitters(Particle p, SubEmitterTrigger trigger) {
    for (final config in subEmitters) {
      if (config.trigger == trigger) _spawn(p, config);
    }
  }

  /// Spawns [config]'s emitter at [p], unless [config.maxInstances] of them
  /// are still running.
  void _spawn(Particle p, SubEmitterConfig config) {
    // Count existing active sub-emitters from this config (by identity)
    var active = 0;
    for (final se in _activeSubEmitters) {
      if (identical(_subEmitterOrigins[se], config)) active++;
    }
    if (active >= config.maxInstances) return;

    final child = config.factory(p.position);
    child.layer = layer;
    _subEmitterOrigins[child] = config;
    _activeSubEmitters.add(child);
  }

  /// Emit a single particle from the pool or newly allocated.
  void _emitParticle() {
    final angle = emissionAngle + (_random.nextDouble() - 0.5) * emissionSpread;
    final particleSpeed =
        speed + (_random.nextDouble() - 0.5) * speedVariation * 2;
    final lifetime =
        particleLifetime + (_random.nextDouble() - 0.5) * lifetimeVariation * 2;
    final size = startSize + (_random.nextDouble() - 0.5) * sizeVariation * 2;
    final av =
        angularVelocity +
        (_random.nextDouble() - 0.5) * angularVelocityVariation * 2;

    final p = _particlePool.acquire();
    p._respawn(
      position.x,
      position.y,
      math.cos(angle) * particleSpeed,
      math.sin(angle) * particleSpeed,
      lifetime.clamp(0.001, double.infinity),
      size.clamp(0.0, double.infinity),
      endSize,
      startColor,
      endColor,
      0.0,
      av,
      1.0,
    );

    effect?.onSpawn(p, this);
    _particles.add(p);
  }

  // ── Render ────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    if (_particles.isEmpty && _activeSubEmitters.isEmpty) return;

    // Optional per-emitter shader, filtering a layer over the particles.
    // Bounds are only worked out for it. Where shaders cannot filter layers
    // (the web, Skia) the particles draw without it; see
    // ShaderFilterSupport. (The shader used to be passed over entirely: the
    // layer was given a zero blur instead.)
    final layerShader = shader;
    var layered = false;
    if (layerShader != null &&
        ShaderFilterSupport.check('A ParticleEmitter shader')) {
      final bounds = getBounds();
      if (bounds != null) {
        // Made every frame on purpose: a shader filter copies the uniforms
        // when it is made, so a kept one would freeze an animated effect.
        _shaderPaint.imageFilter = ui.ImageFilter.shader(layerShader);
        canvas.saveLayer(bounds.inflate(shaderBoundsInflation), _shaderPaint);
        layered = true;
      }
    }

    // Batch render if the renderer supports it and batching is enabled
    if (useBatching) {
      _renderer.renderBatch(canvas, _particles);
    } else {
      for (final p in _particles) {
        _renderer.render(canvas, p);
      }
    }

    // Render active sub-emitters
    for (final se in _activeSubEmitters) {
      se.render(canvas, size);
    }

    if (layered) canvas.restore();
  }

  // Particles live in world space.
  @override
  bool get boundsAreWorldSpace => true;

  @override
  Rect? getBounds() {
    if (_particles.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final p in _particles) {
      final r = p.currentSize / 2.0;
      if (p.x - r < minX) minX = p.x - r;
      if (p.y - r < minY) minY = p.y - r;
      if (p.x + r > maxX) maxX = p.x + r;
      if (p.y + r > maxY) maxY = p.y + r;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Burst [count] particles immediately, ignoring [emissionRate].
  void burst(int count) {
    for (int i = 0; i < count && _particles.length < maxParticles; i++) {
      _emitParticle();
    }
  }

  /// Reset the emitter to its initial state, clearing all particles.
  void reset() {
    for (final particle in _particles) {
      _particlePool.release(particle);
    }
    _particles.clear();
    _particlePool.clear();
    _activeSubEmitters.clear();
    _subEmitterOrigins.clear();
    _emissionAccumulator = 0.0;
    _totalTime = 0.0;
    isEmitting = true;
  }

  /// Add a force at runtime (e.g. wind changes direction mid-game).
  void addForce(ParticleForce force) => _forces.add(force);

  /// Remove a force at runtime.
  void removeForce(ParticleForce force) => _forces.remove(force);
}
