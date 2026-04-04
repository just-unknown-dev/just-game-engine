part of 'particles.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Abstract base
// ═══════════════════════════════════════════════════════════════════════════════

/// A force that mutates a [Particle]'s [Particle.velocity] each tick.
///
/// Forces are stored on a [ParticleEmitter] and applied once per [Particle]
/// per frame inside [Particle.update].
abstract class ParticleForce {
  const ParticleForce();

  /// Apply this force to [particle] for a time step of [dt] seconds.
  void apply(Particle particle, double dt);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Concrete forces
// ═══════════════════════════════════════════════════════════════════════════════

/// Constant gravitational acceleration.
///
/// Wraps the legacy [ParticleEmitter.gravity] Offset parameter so existing
/// presets continue to work unchanged.
class GravityForce extends ParticleForce {
  /// Acceleration vector in world units/sec².  Positive Y = downward.
  final Offset gravity;

  const GravityForce(this.gravity);

  @override
  void apply(Particle particle, double dt) {
    particle.velocity = Offset(
      particle.velocity.dx + gravity.dx * dt,
      particle.velocity.dy + gravity.dy * dt,
    );
  }
}

/// Continuously varying directional wind with optional turbulence.
///
/// The base [direction] * [strength] force is applied every frame.
/// An additional noise-derived turbulence offset oscillates over time using
/// [frequency] Hz, adding organic variation to the particle stream.
class WindForce extends ParticleForce {
  /// Normalized direction of the wind.
  final Offset direction;

  /// Base wind strength in world units/sec².
  final double strength;

  /// Magnitude of the noise-based turbulence (world units/sec²).
  final double turbulence;

  /// Frequency of the turbulence oscillation in Hz.
  final double frequency;

  double _time = 0.0;

  WindForce({
    this.direction = const Offset(1.0, 0.0),
    this.strength = 50.0,
    this.turbulence = 20.0,
    this.frequency = 0.5,
  });

  @override
  void apply(Particle particle, double dt) {
    _time += dt;

    // Base directional force
    particle.velocity = Offset(
      particle.velocity.dx + direction.dx * strength * dt,
      particle.velocity.dy + direction.dy * strength * dt,
    );

    // Noise turbulence (orthogonal to wind direction)
    if (turbulence > 0.0) {
      final noiseVal = _smoothNoise1D(_time * frequency) - 0.5; // [-0.5, 0.5]
      final perp = Offset(-direction.dy, direction.dx); // perpendicular
      particle.velocity = Offset(
        particle.velocity.dx + perp.dx * noiseVal * turbulence * dt,
        particle.velocity.dy + perp.dy * noiseVal * turbulence * dt,
      );
    }
  }

  /// Simple 1-D value noise using integer-valued cosine interpolation.
  static double _smoothNoise1D(double t) {
    final i = t.floor();
    final f = t - i;
    final u = f * f * (3.0 - 2.0 * f); // smoothstep
    return ui.lerpDouble(_hash1D(i), _hash1D(i + 1), u) ?? 0.5;
  }

  static double _hash1D(int n) {
    int x = n;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = (x >> 16) ^ x;
    return (x & 0x7FFFFFFF) / 0x7FFFFFFF;
  }
}

/// Point attractor — pulls particles toward [center].
///
/// Force magnitude uses a linear falloff: `strength * (1 - dist / radius)`.
/// Particles outside [radius] are unaffected.
class AttractorForce extends ParticleForce {
  /// World-space center of the attractor.
  Offset center;

  /// Peak attraction strength (world units/sec²).
  final double strength;

  /// Radius of influence in world units.
  final double radius;

  AttractorForce({
    required this.center,
    this.strength = 200.0,
    this.radius = 150.0,
  });

  @override
  void apply(Particle particle, double dt) {
    final dx = center.dx - particle.position.dx;
    final dy = center.dy - particle.position.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0 || dist > radius) return;

    final falloff = 1.0 - (dist / radius);
    final accel =
        (strength * falloff) / (particle.mass > 0 ? particle.mass : 1.0);
    particle.velocity = Offset(
      particle.velocity.dx + (dx / dist) * accel * dt,
      particle.velocity.dy + (dy / dist) * accel * dt,
    );
  }
}

/// Point repeller — pushes particles away from [center].
///
/// Inverse of [AttractorForce] — same falloff model, opposite sign.
class RepellerForce extends ParticleForce {
  /// World-space center of the repeller.
  Offset center;

  /// Peak repulsion strength (world units/sec²).
  final double strength;

  /// Radius of influence.
  final double radius;

  RepellerForce({
    required this.center,
    this.strength = 200.0,
    this.radius = 150.0,
  });

  @override
  void apply(Particle particle, double dt) {
    final dx = particle.position.dx - center.dx;
    final dy = particle.position.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0 || dist > radius) return;

    final falloff = 1.0 - (dist / radius);
    final accel =
        (strength * falloff) / (particle.mass > 0 ? particle.mass : 1.0);
    particle.velocity = Offset(
      particle.velocity.dx + (dx / dist) * accel * dt,
      particle.velocity.dy + (dy / dist) * accel * dt,
    );
  }
}

/// Velocity-proportional drag (air resistance).
///
/// Each frame the velocity magnitude is reduced by:
///   `v *= 1 - coefficient * dt`
///
/// A [coefficient] of 0.1 removes ~10% of velocity per second.
class DragForce extends ParticleForce {
  /// Drag coefficient in [0, 1] range.  Typical values: 0.02–0.15.
  final double coefficient;

  const DragForce({this.coefficient = 0.05});

  @override
  void apply(Particle particle, double dt) {
    final factor = 1.0 - (coefficient * dt).clamp(0.0, 1.0);
    particle.velocity = Offset(
      particle.velocity.dx * factor,
      particle.velocity.dy * factor,
    );
  }
}

/// Rotational vortex force around [center].
///
/// Produces a tangential force perpendicular to the vector from [center] to
/// the particle, creating a swirling motion.  Positive [strength] = counter-
/// clockwise (math convention).
class VortexForce extends ParticleForce {
  /// World-space center of the vortex.
  Offset center;

  /// Tangential acceleration magnitude (world units/sec²).
  final double strength;

  /// Radius outside which the force is zero.
  final double radius;

  VortexForce({
    required this.center,
    this.strength = 150.0,
    this.radius = 200.0,
  });

  @override
  void apply(Particle particle, double dt) {
    final dx = particle.position.dx - center.dx;
    final dy = particle.position.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0 || dist > radius) return;

    final falloff = 1.0 - (dist / radius);
    final accel =
        (strength * falloff) / (particle.mass > 0 ? particle.mass : 1.0);
    // Tangent = (-y, x) normalized
    particle.velocity = Offset(
      particle.velocity.dx + (-dy / dist) * accel * dt,
      particle.velocity.dy + (dx / dist) * accel * dt,
    );
  }
}

/// Noise-based perturbation using 2-D value noise.
///
/// Samples a smooth noise field at the particle's world position (scaled by
/// [scale]) and time (scaled by [speed]).  The resulting vector is added to
/// [velocity], producing organic, turbulent motion without explicit force
/// fields.
///
/// The underlying implementation is a self-contained hash-based value noise
/// that requires no external dependencies.
class NoiseForce extends ParticleForce {
  /// Force magnitude in world units/sec².
  final double strength;

  /// Spatial scale of the noise — smaller values = larger swirls.
  final double scale;

  /// How fast the noise field evolves over time.
  final double speed;

  double _time = 0.0;

  NoiseForce({this.strength = 80.0, this.scale = 0.008, this.speed = 0.5});

  @override
  void apply(Particle particle, double dt) {
    _time += dt * speed;

    final nx = _noise2D(
      particle.position.dx * scale,
      particle.position.dy * scale + 31.7,
      _time,
    );
    final ny = _noise2D(
      particle.position.dx * scale + 17.3,
      particle.position.dy * scale,
      _time,
    );

    // Map [0,1] → [-0.5, 0.5]; apply force
    particle.velocity = Offset(
      particle.velocity.dx + (nx - 0.5) * strength * dt,
      particle.velocity.dy + (ny - 0.5) * strength * dt,
    );
  }

  // ── Internal noise implementation ──────────────────────────────────────────

  /// 2-D value noise with trilinear time interpolation.
  static double _noise2D(double x, double y, double t) {
    final xi = x.floor();
    final yi = y.floor();
    final ti = t.floor();

    final fx = x - xi;
    final fy = y - yi;
    final ft = t - ti;

    final ux = _fade(fx);
    final uy = _fade(fy);
    final ut = _fade(ft);

    // Sample 8 corners of the (x,y,t) unit cube
    final v000 = _hash3(xi, yi, ti);
    final v100 = _hash3(xi + 1, yi, ti);
    final v010 = _hash3(xi, yi + 1, ti);
    final v110 = _hash3(xi + 1, yi + 1, ti);
    final v001 = _hash3(xi, yi, ti + 1);
    final v101 = _hash3(xi + 1, yi, ti + 1);
    final v011 = _hash3(xi, yi + 1, ti + 1);
    final v111 = _hash3(xi + 1, yi + 1, ti + 1);

    // Trilinear interpolation
    final x00 = ui.lerpDouble(v000, v100, ux)!;
    final x10 = ui.lerpDouble(v010, v110, ux)!;
    final x01 = ui.lerpDouble(v001, v101, ux)!;
    final x11 = ui.lerpDouble(v011, v111, ux)!;
    final y0 = ui.lerpDouble(x00, x10, uy)!;
    final y1 = ui.lerpDouble(x01, x11, uy)!;
    return ui.lerpDouble(y0, y1, ut)!;
  }

  /// Smoothstep fade curve.
  static double _fade(double t) => t * t * (3.0 - 2.0 * t);

  /// Deterministic integer hash → [0, 1].
  static double _hash3(int x, int y, int t) {
    int v = x ^ (y * 57) ^ (t * 131);
    v = ((v >> 16) ^ v) * 0x45d9f3b;
    v = ((v >> 16) ^ v) * 0x45d9f3b;
    v = (v >> 16) ^ v;
    return (v.abs() & 0x7FFFFFFF) / 0x7FFFFFFF;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Boundary force
// ═══════════════════════════════════════════════════════════════════════════════

/// What happens when a particle hits a [BoundaryForce] rect.
///
/// Distinct from the ECS [BoundaryBehavior] enum which governs entity-level
/// boundary responses.
enum ParticleBoundaryBehavior {
  /// Reflect the velocity component perpendicular to the hit edge.
  bounce,

  /// Immediately kill the particle (set age = lifetime).
  kill,

  /// Stop the particle at the boundary (zero out the crossing velocity component).
  stop,
}

/// Restricts particles to an axis-aligned rectangle.
///
/// When a particle's position crosses any edge of [bounds], the chosen
/// [behavior] is applied.  Use [BoundaryBehavior.bounce] with [restitution]
/// close to 1.0 for elastic walls, or 0.3–0.5 for dampened bouncing.
class BoundaryForce extends ParticleForce {
  /// The bounding rectangle in world space.
  final Rect bounds;

  /// What to do when a particle exits [bounds].
  final ParticleBoundaryBehavior behavior;

  /// Fraction of velocity retained after a bounce (0 = fully inelastic, 1 = elastic).
  final double restitution;

  const BoundaryForce({
    required this.bounds,
    this.behavior = ParticleBoundaryBehavior.bounce,
    this.restitution = 0.6,
  });

  @override
  void apply(Particle particle, double dt) {
    double vx = particle.velocity.dx;
    double vy = particle.velocity.dy;
    double px = particle.position.dx;
    double py = particle.position.dy;

    bool hit = false;

    if (px < bounds.left) {
      hit = true;
      px = bounds.left;
      vx = vx.abs() * restitution;
    } else if (px > bounds.right) {
      hit = true;
      px = bounds.right;
      vx = -vx.abs() * restitution;
    }

    if (py < bounds.top) {
      hit = true;
      py = bounds.top;
      vy = vy.abs() * restitution;
    } else if (py > bounds.bottom) {
      hit = true;
      py = bounds.bottom;
      vy = -vy.abs() * restitution;
    }

    if (!hit) return;

    switch (behavior) {
      case ParticleBoundaryBehavior.bounce:
        particle.position = Offset(px, py);
        particle.velocity = Offset(vx, vy);
        break;
      case ParticleBoundaryBehavior.kill:
        particle.age = particle.lifetime;
        break;
      case ParticleBoundaryBehavior.stop:
        particle.position = Offset(px, py);
        // Zero out only the crossing component
        particle.velocity = Offset(
          px == bounds.left || px == bounds.right ? 0 : vx,
          py == bounds.top || py == bounds.bottom ? 0 : vy,
        );
        break;
    }
  }
}
