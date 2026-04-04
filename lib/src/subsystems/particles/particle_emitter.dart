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

  /// Renderer that draws individual particles.  Constructed from [shape] if
  /// not supplied explicitly.
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

  /// Inflation (pixels) added to the emitter bounds used as the [saveLayer]
  /// clip rect when [shader] is non-null.
  final double shaderBoundsInflation;

  /// Whether to use batched rendering when the renderer supports it.
  ///
  /// Only [SpriteParticleRenderer] currently overrides [renderBatch]; all
  /// other renderers fall through to the per-particle render loop regardless
  /// of this flag.
  final bool useBatching;

  /// Auto-stop emitting after [duration] seconds (null = infinite).
  final double? duration;

  // ── Deprecated compat ─────────────────────────────────────────────────────

  /// Shape enum — kept for backward compatibility.
  ///
  /// Prefer [renderer] instead and use one of the [ParticleRenderer]
  /// subclasses directly.
  @Deprecated('Use renderer instead')
  final ParticleShape shape;

  /// Legacy gravity vector — kept for backward compatibility.
  ///
  /// When non-null a [GravityForce] wrapping this value is prepended to
  /// [forces] automatically.  Prefer passing `GravityForce(offset)` in
  /// [forces] directly.
  @Deprecated('Pass GravityForce(offset) in forces instead')
  final Offset? gravity;

  // ── Runtime state ─────────────────────────────────────────────────────────

  /// Whether the emitter is currently emitting new particles.
  bool isEmitting = true;

  final List<Particle> _particles = [];
  final List<Particle> _pool = [];
  double _emissionAccumulator = 0.0;
  double _totalTime = 0.0;
  final math.Random _random = math.Random();

  /// Active sub-emitters spawned by this emitter's particles.
  final List<ParticleEmitter> _activeSubEmitters = [];

  /// Tracks which [SubEmitterConfig] spawned each active sub-emitter so the
  /// [maxInstances] cap can be enforced without calling the factory again.
  final Map<ParticleEmitter, SubEmitterConfig> _subEmitterOrigins = {};

  /// Tracks which particles have already fired milestone sub-emitters.
  /// Key = particle identity, value = set of already-fired fraction indices.
  final Map<int, bool> _milestonesFired = {};

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
    // ignore: deprecated_member_use_from_same_package
    @Deprecated('Pass GravityForce(offset) in forces instead') this.gravity,
    List<ParticleForce>? forces,
    this.effect,
    this.subEmitters = const [],
    this.shader,
    this.shaderBoundsInflation = 20.0,
    this.useBatching = true,
    this.duration,
    // ignore: deprecated_member_use_from_same_package
    @Deprecated('Use renderer instead') this.shape = ParticleShape.circle,
    super.position,
    super.layer,
    super.zOrder,
  }) : assert(maxParticles > 0),
       assert(emissionRate >= 0),
       assert(particleLifetime > 0),
       _forces = _buildForces(gravity, forces) {
    // ignore: deprecated_member_use_from_same_package
    _renderer = renderer ?? shape.toRenderer();
  }

  /// Combines the legacy [gravity] param with the explicit [forces] list.
  static List<ParticleForce> _buildForces(
    Offset? gravity,
    List<ParticleForce>? forces,
  ) {
    final result = <ParticleForce>[];
    if (gravity != null) result.add(GravityForce(gravity));
    if (forces != null) result.addAll(forces);
    return result;
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  /// The renderer used by this emitter.
  ParticleRenderer get renderer => _renderer;

  /// All forces currently applied to this emitter's particles.
  List<ParticleForce> get forces => List.unmodifiable(_forces);

  /// Number of currently live particles.
  int get particleCount => _particles.length;

  /// Whether this emitter has finished emitting AND has no live particles.
  bool get isComplete => !isEmitting && _particles.isEmpty;

  // ── Update ────────────────────────────────────────────────────────────────

  /// Advance the emitter by [deltaTime] seconds.
  ///
  /// Must be called once per frame.  Both [RenderingEngine.updateManagedEmitters]
  /// and [ParticleSystemECS] call this automatically.
  void update(double deltaTime) {
    _totalTime += deltaTime;

    // Stop emitting after duration
    if (duration != null && _totalTime >= duration!) {
      isEmitting = false;
    }

    // Emit new particles
    if (isEmitting) {
      _emissionAccumulator += deltaTime * emissionRate;
      while (_emissionAccumulator >= 1.0 && _particles.length < maxParticles) {
        _emitParticle();
        _emissionAccumulator -= 1.0;
      }
    }

    // Update + cull particles
    final toRemove = <int>[];
    for (int i = 0; i < _particles.length; i++) {
      final p = _particles[i];

      // Tick via effect if present, otherwise direct
      if (effect != null) {
        effect!.onUpdate(p, deltaTime, _forces);
      } else {
        p.update(deltaTime, _forces);
      }

      // Check milestone sub-emitters
      _checkMilestones(p, i);

      if (p.isDead) {
        // On-death callback
        effect?.onDeath(p, this);

        // Spawn death sub-emitters
        _spawnSubEmitters(p, SubEmitterTrigger.onDeath);

        // Recycle
        _milestonesFired.remove(i);
        _pool.add(p);
        toRemove.add(i);
      }
    }

    // Remove dead particles in O(n) without extra allocations
    for (int i = toRemove.length - 1; i >= 0; i--) {
      _particles.removeAt(toRemove[i]);
    }

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

  void _checkMilestones(Particle p, int index) {
    for (final config in subEmitters) {
      if (config.trigger != SubEmitterTrigger.onLifetimeFraction) continue;
      if (p.normalizedLife >= config.lifetimeFraction) {
        final key = index * 1000 + (config.lifetimeFraction * 100).round();
        if (_milestonesFired[key] == true) continue;
        _milestonesFired[key] = true;
        _spawnSubEmitters(
          p,
          SubEmitterTrigger.onLifetimeFraction,
          fraction: config.lifetimeFraction,
        );
      }
    }
  }

  void _spawnSubEmitters(
    Particle p,
    SubEmitterTrigger trigger, {
    double? fraction,
  }) {
    for (final config in subEmitters) {
      if (config.trigger != trigger) continue;
      if (trigger == SubEmitterTrigger.onLifetimeFraction &&
          fraction != null &&
          (config.lifetimeFraction - fraction).abs() > 0.001) {
        continue;
      }

      // Count existing active sub-emitters from this config (by identity)
      int active = _activeSubEmitters
          .where((se) => _subEmitterOrigins[se] == config)
          .length;
      if (active >= config.maxInstances) continue;

      final child = config.factory(p.position);
      child.layer = layer;
      _subEmitterOrigins[child] = config;
      _activeSubEmitters.add(child);
    }
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

    final velocity = Offset(
      math.cos(angle) * particleSpeed,
      math.sin(angle) * particleSpeed,
    );

    late Particle p;
    if (_pool.isNotEmpty) {
      p = _pool.removeLast();
      p.reset(
        position: position,
        velocity: velocity,
        lifetime: lifetime.clamp(0.001, double.infinity),
        startSize: size.clamp(0.0, double.infinity),
        endSize: endSize,
        startColor: startColor,
        endColor: endColor,
        angularVelocity: av,
      );
    } else {
      p = Particle(
        position: position,
        velocity: velocity,
        lifetime: lifetime.clamp(0.001, double.infinity),
        startSize: size.clamp(0.0, double.infinity),
        endSize: endSize,
        startColor: startColor,
        endColor: endColor,
        angularVelocity: av,
      );
    }

    effect?.onSpawn(p, this);
    _particles.add(p);
  }

  // ── Render ────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    if (_particles.isEmpty && _activeSubEmitters.isEmpty) return;

    // Optional per-emitter shader
    final bounds = getBounds();
    if (shader != null && bounds != null) {
      final inflated = bounds.inflate(shaderBoundsInflation);
      _shaderPaint.imageFilter = ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0);
      canvas.saveLayer(inflated, _shaderPaint);
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

    if (shader != null && bounds != null) {
      canvas.restore();
    }
  }

  @override
  Rect? getBounds() {
    if (_particles.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final p in _particles) {
      final r = p.currentSize / 2.0;
      if (p.position.dx - r < minX) minX = p.position.dx - r;
      if (p.position.dy - r < minY) minY = p.position.dy - r;
      if (p.position.dx + r > maxX) maxX = p.position.dx + r;
      if (p.position.dy + r > maxY) maxY = p.position.dy + r;
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
    _particles.clear();
    _pool.clear();
    _activeSubEmitters.clear();
    _subEmitterOrigins.clear();
    _milestonesFired.clear();
    _emissionAccumulator = 0.0;
    _totalTime = 0.0;
    isEmitting = true;
  }

  /// Add a force at runtime (e.g. wind changes direction mid-game).
  void addForce(ParticleForce force) => _forces.add(force);

  /// Remove a force at runtime.
  void removeForce(ParticleForce force) => _forces.remove(force);
}
