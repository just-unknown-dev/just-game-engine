part of 'particles.dart';

/// An individual particle managed by a [ParticleEmitter].
///
/// Particles are pooled and recycled via [reset] to avoid GC pressure.
/// Rendering is delegated to the emitter's [ParticleRenderer] — this class
/// owns only simulation state.
class Particle {
  /// Current world-space position.
  Offset position;

  /// Position at the start of the last tick — used by [LineParticleRenderer]
  /// to draw motion-blur streaks.
  Offset previousPosition;

  /// Current velocity in world units/sec.
  Offset velocity;

  /// Current rotation in radians.
  double rotation;

  /// Angular velocity in radians/sec (positive = clockwise).
  double angularVelocity;

  /// Mass used by force calculations (default 1.0 means forces apply 1:1).
  double mass;

  /// Elapsed age in seconds.
  double age;

  /// Total lifetime in seconds.
  double lifetime;

  /// Start size (world units).
  double startSize;

  /// End size at end of lifetime.
  double endSize;

  /// Color at birth.
  Color startColor;

  /// Color at death.
  Color endColor;

  /// Opaque per-particle state slot for [ParticleEffect] subclasses.
  /// The engine never reads or writes this field.
  Object? customData;

  /// Create a particle with explicit initial values.
  Particle({
    required this.position,
    required this.velocity,
    required this.lifetime,
    required this.startSize,
    required this.endSize,
    required this.startColor,
    required this.endColor,
    this.rotation = 0.0,
    this.angularVelocity = 0.0,
    this.mass = 1.0,
    this.customData,
  }) : age = 0.0,
       previousPosition = position;

  // ── Pool reuse ──────────────────────────────────────────────────────────────

  /// Re-initialize this particle for reuse from the emitter's pool.
  void reset({
    required Offset position,
    required Offset velocity,
    required double lifetime,
    required double startSize,
    required double endSize,
    required Color startColor,
    required Color endColor,
    double rotation = 0.0,
    double angularVelocity = 0.0,
    double mass = 1.0,
  }) {
    this.position = position;
    previousPosition = position;
    this.velocity = velocity;
    this.lifetime = lifetime;
    age = 0.0;
    this.startSize = startSize;
    this.endSize = endSize;
    this.startColor = startColor;
    this.endColor = endColor;
    this.rotation = rotation;
    this.angularVelocity = angularVelocity;
    this.mass = mass;
    customData = null;
  }

  // ── Simulation ───────────────────────────────────────────────────────────────

  /// Advance this particle by [dt] seconds, applying each force in [forces].
  ///
  /// Call order:
  ///  1. Save [previousPosition].
  ///  2. Apply all forces (each mutates [velocity]).
  ///  3. Semi-implicit Euler integration of position + rotation.
  ///  4. Increment [age].
  void update(double dt, List<ParticleForce> forces) {
    previousPosition = position;

    for (final force in forces) {
      force.apply(this, dt);
    }

    // Integrate position
    position = Offset(
      position.dx + velocity.dx * dt,
      position.dy + velocity.dy * dt,
    );

    // Integrate rotation
    rotation += angularVelocity * dt;

    age += dt;
  }

  // ── Accessors ────────────────────────────────────────────────────────────────

  /// Returns `true` when [age] has reached [lifetime].
  bool get isDead => age >= lifetime;

  /// Normalized age in [0, 1].
  double get normalizedLife => (age / lifetime).clamp(0.0, 1.0);

  /// Current interpolated size.
  double get currentSize =>
      ui.lerpDouble(startSize, endSize, normalizedLife) ?? startSize;

  /// Current interpolated color.
  Color get currentColor =>
      Color.lerp(startColor, endColor, normalizedLife) ?? startColor;
}
