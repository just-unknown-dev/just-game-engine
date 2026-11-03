part of 'particles.dart';

/// An individual particle managed by a [ParticleEmitter].
///
/// Particles are pooled and recycled via [reset] to avoid GC pressure.
/// Rendering is delegated to the emitter's [ParticleRenderer] — this class
/// owns only simulation state.
///
/// Position and velocity are held as plain numbers — [x], [y], [vx], [vy] —
/// so moving a particle and applying forces to it allocates nothing. The
/// [position], [velocity] and [previousPosition] offsets read and write the
/// same numbers, for code that prefers them.
class Particle {
  /// Current world-space position, x.
  double x;

  /// Current world-space position, y.
  double y;

  /// Position at the start of the last tick, x — see [previousPosition].
  double previousX;

  /// Position at the start of the last tick, y — see [previousPosition].
  double previousY;

  /// Current velocity in world units/sec, x.
  double vx;

  /// Current velocity in world units/sec, y.
  double vy;

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

  /// How many of its emitter's lifetime-fraction sub-emitters this particle
  /// has set off, in fraction order. Reset with the particle.
  int _milestones = 0;

  /// Create a particle with explicit initial values.
  Particle({
    required Offset position,
    required Offset velocity,
    required this.lifetime,
    required this.startSize,
    required this.endSize,
    required this.startColor,
    required this.endColor,
    this.rotation = 0.0,
    this.angularVelocity = 0.0,
    this.mass = 1.0,
    this.customData,
  }) : x = position.dx,
       y = position.dy,
       previousX = position.dx,
       previousY = position.dy,
       vx = velocity.dx,
       vy = velocity.dy,
       age = 0.0;

  /// Current world-space position.
  Offset get position => Offset(x, y);
  set position(Offset value) {
    x = value.dx;
    y = value.dy;
  }

  /// Position at the start of the last tick — used by
  /// [LineParticleRenderer] to draw motion-blur streaks.
  Offset get previousPosition => Offset(previousX, previousY);
  set previousPosition(Offset value) {
    previousX = value.dx;
    previousY = value.dy;
  }

  /// Current velocity in world units/sec.
  Offset get velocity => Offset(vx, vy);
  set velocity(Offset value) {
    vx = value.dx;
    vy = value.dy;
  }

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
    _respawn(
      position.dx,
      position.dy,
      velocity.dx,
      velocity.dy,
      lifetime,
      startSize,
      endSize,
      startColor,
      endColor,
      rotation,
      angularVelocity,
      mass,
    );
  }

  /// [reset] without the offsets, for the emitter.
  void _respawn(
    double x,
    double y,
    double vx,
    double vy,
    double lifetime,
    double startSize,
    double endSize,
    Color startColor,
    Color endColor,
    double rotation,
    double angularVelocity,
    double mass,
  ) {
    this.x = x;
    this.y = y;
    previousX = x;
    previousY = y;
    this.vx = vx;
    this.vy = vy;
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
    _milestones = 0;
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
    previousX = x;
    previousY = y;

    for (var i = 0; i < forces.length; i++) {
      forces[i].apply(this, dt);
    }

    // Integrate position
    x = x + vx * dt;
    y = y + vy * dt;

    // Integrate rotation
    rotation += angularVelocity * dt;

    age += dt;
  }

  // ── Accessors ────────────────────────────────────────────────────────────────

  /// Returns `true` when [age] has reached [lifetime].
  bool get isDead => age >= lifetime;

  /// Normalized age in `[0, 1]`.
  double get normalizedLife => (age / lifetime).clamp(0.0, 1.0);

  /// Current interpolated size.
  double get currentSize =>
      ui.lerpDouble(startSize, endSize, normalizedLife) ?? startSize;

  /// Current interpolated color.
  ///
  /// A particle whose start and end colours are the same keeps that colour,
  /// without making a new one each frame.
  Color get currentColor {
    if (startColor == endColor) return startColor;
    return Color.lerp(startColor, endColor, normalizedLife) ?? startColor;
  }

  /// [currentColor] as a 32-bit 0xAARRGGBB value — worked out without
  /// making a [Color], for renderers that hand colours to the canvas as
  /// numbers.
  int get currentColorArgb {
    final a = startColor, b = endColor;
    if (a == b) return a.toARGB32();
    if (a.colorSpace != b.colorSpace) return currentColor.toARGB32();
    final t = normalizedLife;
    return _channel(a.a, b.a, t) << 24 |
        _channel(a.r, b.r, t) << 16 |
        _channel(a.g, b.g, t) << 8 |
        _channel(a.b, b.b, t);
  }

  /// One channel of [Color.lerp], as its 8-bit value.
  static int _channel(double from, double to, double t) {
    final v = (from * (1.0 - t) + to * t).clamp(0.0, 1.0);
    return (v * 255.0).round().clamp(0, 255);
  }
}
