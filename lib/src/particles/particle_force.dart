part of 'particles.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Abstract base
// ═══════════════════════════════════════════════════════════════════════════════

/// A force that mutates a [Particle]'s [Particle.velocity] each tick.
///
/// Forces are stored on a [ParticleEmitter] and applied once per [Particle]
/// per frame inside [Particle.update].
///
/// The built-in forces work on the particle's numbers — [Particle.vx],
/// [Particle.vy], [Particle.x], [Particle.y] — so applying one allocates
/// nothing. A force of your own may do the same, or keep using the
/// [Particle.velocity] and [Particle.position] offsets, which read and write
/// those numbers.
abstract class ParticleForce {
  /// Const constructor so subclasses can be const.
  const ParticleForce();

  /// Moves the force's own clock on by [dt] seconds — once per frame: its
  /// [ParticleEmitter] calls it at the start of each update, before any
  /// particle is. A force whose field changes over time ([WindForce],
  /// [NoiseForce]) keeps its time here, so it runs at the same pace
  /// however many particles there are. Does nothing by default.
  ///
  /// A force added to several emitters is advanced by each of them; give
  /// each emitter its own.
  void advance(double dt) {}

  /// Apply this force to [particle] for a time step of [dt] seconds.
  void apply(Particle particle, double dt);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Concrete forces
// ═══════════════════════════════════════════════════════════════════════════════

/// Constant gravitational acceleration.
class GravityForce extends ParticleForce {
  /// Acceleration vector in world units/sec².  Positive Y = downward.
  final Offset gravity;

  /// Accelerates every particle by [gravity], whatever its mass — e.g.
  /// `GravityForce(Offset(0, 300))` pulls down at 300 world units/sec².
  const GravityForce(this.gravity);

  @override
  void apply(Particle particle, double dt) {
    particle
      ..vx = particle.vx + gravity.dx * dt
      ..vy = particle.vy + gravity.dy * dt;
  }
}

/// Continuously varying directional wind with optional turbulence.
///
/// The base [direction] * [strength] force is applied every frame.
/// An additional noise-derived turbulence offset oscillates over time using
/// [frequency] Hz, adding organic variation to the particle stream. Its
/// time moves on once a frame ([advance]), the same for every particle.
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

  /// Wind along [direction] (+X by default) at [strength] (50 by default),
  /// wavering sideways by up to half of [turbulence] each way (20 by
  /// default; 0 turns it off) at [frequency] (0.5 by default). Mass is
  /// ignored.
  WindForce({
    this.direction = const Offset(1.0, 0.0),
    this.strength = 50.0,
    this.turbulence = 20.0,
    this.frequency = 0.5,
  });

  @override
  void advance(double dt) => _time += dt;

  @override
  void apply(Particle particle, double dt) {
    // Base directional force
    particle
      ..vx = particle.vx + direction.dx * strength * dt
      ..vy = particle.vy + direction.dy * strength * dt;

    // Noise turbulence (orthogonal to wind direction)
    if (turbulence > 0.0) {
      final noiseVal = _smoothNoise1D(_time * frequency) - 0.5; // [-0.5, 0.5]
      // Along the perpendicular (-direction.dy, direction.dx).
      particle
        ..vx = particle.vx + -direction.dy * noiseVal * turbulence * dt
        ..vy = particle.vy + direction.dx * noiseVal * turbulence * dt;
    }
  }

  /// Simple 1-D value noise using integer-valued cosine interpolation.
  static double _smoothNoise1D(double t) {
    final i = t.floor();
    final f = t - i;
    final u = f * f * (3.0 - 2.0 * f); // smoothstep
    return ui.lerpDouble(hash1D(i), hash1D(i + 1), u) ?? 0.5;
  }

  /// The noise's hash of lattice point [n], in `[0, 1]` — the same on every
  /// platform; see [_hash32].
  @visibleForTesting
  static double hash1D(int n) =>
      (_hash32(n & 0xFFFFFFFF) & 0x7FFFFFFF) / 0x7FFFFFFF;
}

/// Multiplies two 32-bit unsigned values, keeping the low 32 bits — the
/// same on the web as natively.
///
/// A plain `a * b` of two 32-bit numbers needs up to 64 bits. Native ints
/// wrap at 64; on the web numbers are doubles, exact only to 2^53, so the
/// low bits — the ones a hash keeps — came out different. Split into 16-bit
/// halves, no intermediate passes 2^49.
int _mul32(int a, int b) {
  final lo = (a & 0xFFFF) * b;
  final hi = (((a >>> 16) & 0xFFFF) * b) & 0xFFFF;
  return (lo + (hi << 16)) & 0xFFFFFFFF;
}

/// A 32-bit integer hash of [x] (0 ≤ [x] < 2^32), computed identically on
/// every platform.
///
/// Every step stays within 32 unsigned bits: masked after each multiply
/// ([_mul32]) and shifted with `>>>`. The web's `>>` truncates to 32 bits
/// while native `>>` does not, and its multiplies lost the low bits past
/// 2^53 — so wind and noise forces moved particles differently on the web.
int _hash32(int x) {
  x = _mul32(((x >>> 16) ^ x) & 0xFFFFFFFF, 0x45d9f3b);
  x = _mul32(((x >>> 16) ^ x) & 0xFFFFFFFF, 0x45d9f3b);
  return ((x >>> 16) ^ x) & 0xFFFFFFFF;
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

  /// Pulls particles within [radius] (150 by default) of [center] toward
  /// it: [strength] (200 by default) at the centre, fading linearly to 0 at
  /// the edge, divided by the particle's mass when that is positive.
  AttractorForce({
    required this.center,
    this.strength = 200.0,
    this.radius = 150.0,
  });

  @override
  void apply(Particle particle, double dt) {
    final dx = center.dx - particle.x;
    final dy = center.dy - particle.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0 || dist > radius) return;

    final falloff = 1.0 - (dist / radius);
    final accel =
        (strength * falloff) / (particle.mass > 0 ? particle.mass : 1.0);
    particle
      ..vx = particle.vx + (dx / dist) * accel * dt
      ..vy = particle.vy + (dy / dist) * accel * dt;
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

  /// Pushes particles within [radius] (150 by default) of [center] away
  /// from it: [strength] (200 by default) at the centre, fading linearly to
  /// 0 at the edge, divided by the particle's mass when that is positive.
  RepellerForce({
    required this.center,
    this.strength = 200.0,
    this.radius = 150.0,
  });

  @override
  void apply(Particle particle, double dt) {
    final dx = particle.x - center.dx;
    final dy = particle.y - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0 || dist > radius) return;

    final falloff = 1.0 - (dist / radius);
    final accel =
        (strength * falloff) / (particle.mass > 0 ? particle.mass : 1.0);
    particle
      ..vx = particle.vx + (dx / dist) * accel * dt
      ..vy = particle.vy + (dy / dist) * accel * dt;
  }
}

/// Velocity-proportional drag (air resistance).
///
/// Each frame the velocity magnitude is reduced by:
///   `v *= 1 - coefficient * dt`
///
/// A [coefficient] of 0.1 removes ~10% of velocity per second.
class DragForce extends ParticleForce {
  /// Drag coefficient in `[0, 1]` range.  Typical values: 0.02–0.15.
  final double coefficient;

  /// Drag taking about [coefficient] of each particle's velocity away per
  /// second (0.05 by default); mass is ignored.
  const DragForce({this.coefficient = 0.05});

  @override
  void apply(Particle particle, double dt) {
    final factor = 1.0 - (coefficient * dt).clamp(0.0, 1.0);
    particle
      ..vx = particle.vx * factor
      ..vy = particle.vy * factor;
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

  /// Swirls particles within [radius] (200 by default) of [center] around
  /// it: [strength] (150 by default) at the centre, fading linearly to 0 at
  /// the edge, divided by the particle's mass when that is positive. A
  /// negative [strength] swirls the other way.
  VortexForce({
    required this.center,
    this.strength = 150.0,
    this.radius = 200.0,
  });

  @override
  void apply(Particle particle, double dt) {
    final dx = particle.x - center.dx;
    final dy = particle.y - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0 || dist > radius) return;

    final falloff = 1.0 - (dist / radius);
    final accel =
        (strength * falloff) / (particle.mass > 0 ? particle.mass : 1.0);
    // Tangent = (-y, x) normalized
    particle
      ..vx = particle.vx + (-dy / dist) * accel * dt
      ..vy = particle.vy + (dx / dist) * accel * dt;
  }
}

/// Noise-based perturbation using 2-D value noise.
///
/// Samples a smooth noise field at the particle's world position (scaled by
/// [scale]) and time (scaled by [speed]).  The resulting vector is added to
/// [Particle.velocity], producing organic, turbulent motion without explicit
/// force fields. Its time moves on once a frame ([advance]), the same for
/// every particle.
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

  /// Turbulence pushing each particle by up to half of [strength] each way
  /// on each axis (80 by default), from a noise field sampled [scale] per
  /// world unit (0.008 by default) that drifts at [speed] (0.5 by default).
  /// Mass is ignored.
  NoiseForce({this.strength = 80.0, this.scale = 0.008, this.speed = 0.5});

  @override
  void advance(double dt) => _time += dt * speed;

  @override
  void apply(Particle particle, double dt) {
    final nx = _noise2D(particle.x * scale, particle.y * scale + 31.7, _time);
    final ny = _noise2D(particle.x * scale + 17.3, particle.y * scale, _time);

    // Map [0,1] → [-0.5, 0.5]; apply force
    particle
      ..vx = particle.vx + (nx - 0.5) * strength * dt
      ..vy = particle.vy + (ny - 0.5) * strength * dt;
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
    final v000 = hash3(xi, yi, ti);
    final v100 = hash3(xi + 1, yi, ti);
    final v010 = hash3(xi, yi + 1, ti);
    final v110 = hash3(xi + 1, yi + 1, ti);
    final v001 = hash3(xi, yi, ti + 1);
    final v101 = hash3(xi + 1, yi, ti + 1);
    final v011 = hash3(xi, yi + 1, ti + 1);
    final v111 = hash3(xi + 1, yi + 1, ti + 1);

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

  /// Deterministic integer hash of a lattice point → `[0, 1]`, the same on
  /// every platform; see [_hash32].
  @visibleForTesting
  static double hash3(int x, int y, int t) {
    final v =
        (x & 0xFFFFFFFF) ^
        _mul32(y & 0xFFFFFFFF, 57) ^
        _mul32(t & 0xFFFFFFFF, 131);
    return (_hash32(v & 0xFFFFFFFF) & 0x7FFFFFFF) / 0x7FFFFFFF;
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
/// [behavior] is applied.  Use [ParticleBoundaryBehavior.bounce] with
/// [restitution] close to 1.0 for elastic walls, or 0.3–0.5 for dampened
/// bouncing.
class BoundaryForce extends ParticleForce {
  /// The bounding rectangle in world space.
  final Rect bounds;

  /// What to do when a particle exits [bounds].
  final ParticleBoundaryBehavior behavior;

  /// Fraction of velocity retained after a bounce (0 = fully inelastic, 1 = elastic).
  final double restitution;

  /// Keeps particles to [bounds]: one found outside it gets [behavior]
  /// (bounce by default, keeping [restitution] — 0.6 by default — of the
  /// speed across the edge it crossed).
  const BoundaryForce({
    required this.bounds,
    this.behavior = ParticleBoundaryBehavior.bounce,
    this.restitution = 0.6,
  });

  @override
  void apply(Particle particle, double dt) {
    double vx = particle.vx;
    double vy = particle.vy;
    double px = particle.x;
    double py = particle.y;

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
        particle
          ..x = px
          ..y = py
          ..vx = vx
          ..vy = vy;
        break;
      case ParticleBoundaryBehavior.kill:
        particle.age = particle.lifetime;
        break;
      case ParticleBoundaryBehavior.stop:
        particle
          ..x = px
          ..y = py
          // Zero out only the crossing component
          ..vx = px == bounds.left || px == bounds.right ? 0 : vx
          ..vy = py == bounds.top || py == bounds.bottom ? 0 : vy;
        break;
    }
  }
}
