import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlendSpace1D', () {
    test('interpolates linearly between two adjacent thresholds', () {
      final space = BlendSpace1D([0, 10, 20]);
      final w = space.evaluate(5);
      expect(w[0], closeTo(0.5, 1e-9));
      expect(w[1], closeTo(0.5, 1e-9));
      expect(w[2], closeTo(0.0, 1e-9));
    });

    test('clamps below the first threshold', () {
      final space = BlendSpace1D([0, 10, 20]);
      final w = space.evaluate(-5);
      expect(w, [1.0, 0.0, 0.0]);
    });

    test('clamps above the last threshold', () {
      final space = BlendSpace1D([0, 10, 20]);
      final w = space.evaluate(99);
      expect(w, [0.0, 0.0, 1.0]);
    });

    test('is exact at an interior threshold', () {
      final space = BlendSpace1D([0, 10, 20]);
      final w = space.evaluate(10);
      expect(w[0], closeTo(0.0, 1e-9));
      expect(w[1], closeTo(1.0, 1e-9));
      expect(w[2], closeTo(0.0, 1e-9));
    });

    test('single threshold always returns weight 1', () {
      final space = BlendSpace1D([5]);
      expect(space.evaluate(-100), [1.0]);
      expect(space.evaluate(100), [1.0]);
    });

    test('empty thresholds returns empty weights', () {
      final space = BlendSpace1D([]);
      expect(space.evaluate(0), isEmpty);
    });

    test('weights always sum to 1 and are never negative across a sweep', () {
      final space = BlendSpace1D([0, 5, 12, 20]);
      for (var p = -10.0; p <= 30.0; p += 0.7) {
        final w = space.evaluate(p);
        final sum = w.fold<double>(0, (a, b) => a + b);
        expect(sum, closeTo(1.0, 1e-9), reason: 'parameter=$p');
        for (final weight in w) {
          expect(weight, greaterThanOrEqualTo(-1e-12), reason: 'parameter=$p');
        }
      }
    });
  });

  group('BlendSpace2D — Gradient Band Interpolation', () {
    // Unit-circle samples at 45-degree increments — matches
    // PlayerAnimationSystem's 8-directional octant convention.
    List<Offset> radialPoints(int count, {double radius = 1.0}) => [
      for (var i = 0; i < count; i++)
        Offset.fromDirection(2 * math.pi * i / count, radius),
    ];

    // The player-locomotion migration's real 2D blend tree: idle at the
    // origin, walk/run/run_backwards on the forward axis, strafes on the
    // right axis — a deliberately asymmetric layout, unlike the radial one.
    const locomotionPoints = [
      Offset(0, 0), // idle
      Offset(0, 0.5), // walk
      Offset(0, 1), // run
      Offset(0, -1), // run_backwards
      Offset(1, 0), // strafe_left
      Offset(-1, 0), // strafe_right
    ];

    test(
      'weight is exactly 1 at a sample\'s own point for ANY distinct layout '
      '(radial and the real asymmetric locomotion layout)',
      () {
        for (final points in [radialPoints(8), locomotionPoints]) {
          final space = BlendSpace2D(points);
          for (var i = 0; i < points.length; i++) {
            final w = space.evaluate(points[i]);
            for (var j = 0; j < points.length; j++) {
              expect(
                w[j],
                closeTo(j == i ? 1.0 : 0.0, 1e-6),
                reason: 'points=$points own=$i sample=$j',
              );
            }
          }
        }
      },
    );

    test('bisector between two adjacent radial samples splits 0.5/0.5', () {
      final points = radialPoints(8);
      final space = BlendSpace2D(points);
      final query = Offset.fromDirection(math.pi / 8, 1.0); // halfway 0<->1
      final w = space.evaluate(query);
      expect(w[0], closeTo(0.5, 1e-6));
      expect(w[1], closeTo(0.5, 1e-6));
      for (var i = 2; i < points.length; i++) {
        expect(w[i], closeTo(0.0, 1e-6), reason: 'sample $i');
      }
    });

    test('weights sum to 1 and are never negative across a radial sweep', () {
      final points = radialPoints(8);
      final space = BlendSpace2D(points);
      for (var deg = 0; deg < 360; deg += 5) {
        for (final radius in [0.0, 0.3, 0.7, 1.0, 1.5]) {
          final query = Offset.fromDirection(deg * math.pi / 180, radius);
          final w = space.evaluate(query);
          final sum = w.fold<double>(0, (a, b) => a + b);
          expect(sum, closeTo(1.0, 1e-6), reason: 'deg=$deg radius=$radius');
          for (final weight in w) {
            expect(
              weight,
              greaterThanOrEqualTo(-1e-9),
              reason: 'deg=$deg radius=$radius',
            );
          }
        }
      }
    });

    test(
      'weights sum to 1 and are never negative across the real locomotion '
      'layout',
      () {
        final space = BlendSpace2D(locomotionPoints);
        for (var x = -1.5; x <= 1.5; x += 0.25) {
          for (var y = -1.5; y <= 1.5; y += 0.25) {
            final w = space.evaluate(Offset(x, y));
            final sum = w.fold<double>(0, (a, b) => a + b);
            expect(sum, closeTo(1.0, 1e-6), reason: 'query=($x,$y)');
            for (final weight in w) {
              expect(
                weight,
                greaterThanOrEqualTo(-1e-9),
                reason: 'query=($x,$y)',
              );
            }
          }
        }
      },
    );

    test('degenerates to BlendSpace1D for two collinear points', () {
      final space2d = BlendSpace2D([const Offset(0, 0), const Offset(0, 10)]);
      final space1d = BlendSpace1D([0, 10]);
      for (var y = -5.0; y <= 15.0; y += 1.0) {
        final w2 = space2d.evaluate(Offset(0, y));
        final w1 = space1d.evaluate(y);
        expect(w2[0], closeTo(w1[0], 1e-9), reason: 'y=$y');
        expect(w2[1], closeTo(w1[1], 1e-9), reason: 'y=$y');
      }
    });

    test('single point always returns weight 1', () {
      final space = BlendSpace2D([const Offset(3, 4)]);
      expect(space.evaluate(const Offset(0, 0)), [1.0]);
      expect(space.evaluate(const Offset(100, 100)), [1.0]);
    });

    test('empty points returns empty weights', () {
      final space = BlendSpace2D(const []);
      expect(space.evaluate(Offset.zero), isEmpty);
    });

    test('a duplicated point among distinct others does not throw or NaN', () {
      final space = BlendSpace2D([
        const Offset(1, 1),
        const Offset(1, 1),
        const Offset(5, 5),
      ]);
      final w = space.evaluate(const Offset(1, 1));
      for (final weight in w) {
        expect(weight.isNaN, isFalse);
      }
      expect(w.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('all-coincident points fall back to nearest without /0', () {
      final space = BlendSpace2D([const Offset(2, 2), const Offset(2, 2)]);
      final w = space.evaluate(const Offset(2, 2));
      for (final weight in w) {
        expect(weight.isNaN, isFalse);
      }
      expect(w.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });
  });

  group('BlendCompositor — cumulative alpha compositing', () {
    // Simulates sequential Porter-Duff "over" compositing of [values] using
    // [alphas]: result starts at 0 and each layer blends in as
    // alpha*value + (1-alpha)*result — the same recurrence BlendSprite.render
    // performs via successive drawImageRect calls.
    double composite(List<double> values, List<double> alphas) {
      var result = 0.0;
      for (var i = 0; i < values.length; i++) {
        result = alphas[i] * values[i] + (1 - alphas[i]) * result;
      }
      return result;
    }

    test('reproduces the exact weighted average for N=1..5 layers', () {
      final rand = math.Random(42);
      for (var n = 1; n <= 5; n++) {
        for (var trial = 0; trial < 20; trial++) {
          final raw = List.generate(n, (_) => rand.nextDouble() + 0.01);
          final sum = raw.fold<double>(0, (a, b) => a + b);
          final weights = raw.map((w) => w / sum).toList();
          final values = List.generate(n, (_) => rand.nextDouble() * 100);

          final alphas = BlendCompositor.cumulativeAlphas(weights);
          final result = composite(values, alphas);

          var expected = 0.0;
          for (var i = 0; i < n; i++) {
            expected += weights[i] * values[i];
          }

          expect(result, closeTo(expected, 1e-9), reason: 'n=$n trial=$trial');
        }
      }
    });

    test(
      'the naive "alpha = raw weight" shortcut matches at N=2 but diverges '
      'at N=3',
      () {
        const weights = [0.2, 0.3, 0.5];
        const values = [10.0, 20.0, 30.0];
        const expected = 0.2 * 10.0 + 0.3 * 20.0 + 0.5 * 30.0; // 23.0

        final correctResult = composite(
          values,
          BlendCompositor.cumulativeAlphas(weights),
        );
        expect(correctResult, closeTo(expected, 1e-9));

        // Naively reusing raw weights as alphas for every layer (instead of
        // cumulativeAlphas' running-sum renormalization) silently produces
        // the wrong ratio once there are 3+ simultaneously-blended layers.
        final naiveResult = composite(values, weights);
        expect(naiveResult, isNot(closeTo(expected, 0.5)));
      },
    );

    test(
      'the base layer is always drawn fully opaque — the familiar 2-layer '
      'crossfade pattern (draw A opaque, draw B at alpha=t) is what '
      'cumulativeAlphas generalizes to N layers, not "alpha = raw weight" '
      'applied uniformly',
      () {
        final alphas = BlendCompositor.cumulativeAlphas([0.35, 0.65]);
        expect(alphas[0], closeTo(1.0, 1e-9)); // base: fully opaque
        expect(alphas[1], closeTo(0.65, 1e-9)); // incoming: its own weight
      },
    );

    test('handles an all-zero weight list without dividing by zero', () {
      final alphas = BlendCompositor.cumulativeAlphas([0.0, 0.0, 0.0]);
      for (final a in alphas) {
        expect(a.isNaN, isFalse);
      }
    });
  });
}
