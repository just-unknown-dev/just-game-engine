// A Collider2DComponent matching what its entity draws, on both backends:
// the body takes each 2-D shape's outline (a Rectangle, Capsule, Polygon,
// Line) or the box of anything with a size, and is made again as that
// changes — and a mirrored polygon still builds a body facing out.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

final _backends = <String, PhysicsEngine Function()>{
  'native': PhysicsEngine.new,
  'pure Dart': PhysicsEngine.pureDart,
};

/// Something with a size but no outline, as a sprite is.
class _Sized extends Component {
  _Sized(this.width, this.height);
  double width, height;
}

class _SizedExtent extends ComponentExtent {
  const _SizedExtent();
  @override
  Size? sizeOf(Component component) {
    final c = component as _Sized;
    return Size(c.width, c.height);
  }
}

({World world, Physics2DQueries queries}) _setUp(PhysicsEngine engine) {
  final physics = engine..initialize();
  physics.setGravity(0, 0);
  final world = World()..initialize();
  world.context.definitions.register(
    ComponentDefinition<_Sized>(
      type: '_Sized',
      create: () => _Sized(0, 0),
      fields: const [],
      extent: const _SizedExtent(),
    ),
  );
  final system = Physics2DSystem(physics);
  world.addSystem(system);
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, queries: system.queries);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final MapEntry(key: name, value: make) in _backends.entries) {
    group('on $name', () {
      /// An entity drawn by [look], with a static collider matching it;
      /// whether [point] is in its body before and after [grow].
      void follows(
        Component look,
        Offset point,
        void Function() grow, {
        List<Component> extra = const [],
      }) {
        final (:world, :queries) = _setUp(make());
        final entity = world.createEntityWithComponents([
          TransformComponent(),
          look,
          ...extra,
          RigidBody2DComponent(bodyType: BodyType.static),
          Collider2DComponent(shape: Collider2DShape.matchShape),
        ]);
        world.update(1 / 60);
        expect(
          queries.overlapCircle(point, 0.5),
          isEmpty,
          reason: 'just outside it',
        );
        grow();
        world.update(1 / 60);
        expect(queries.overlapCircle(point, 0.5), [entity], reason: 'grown');
      }

      test('a rectangle, by its width and its rounded corners', () {
        final rect = Rectangle2DComponent(width: 40, height: 20);
        follows(rect, const Offset(25, 0), () => rect.width = 60);

        final rounded = Rectangle2DComponent(
          width: 40,
          height: 40,
          cornerRadius: 15,
        );
        // Off the rounded corner; inside once the corner is square.
        follows(rounded, const Offset(18, 18), () => rounded.cornerRadius = 0);
      });

      test('a capsule, by its height', () {
        final capsule = Capsule2DComponent(width: 20, height: 40);
        follows(capsule, const Offset(0, 25), () => capsule.height = 60);
      });

      test('a polygon, by a vertex moved', () {
        final polygon = Polygon2DComponent(
          vertices: [
            const Offset(-10, -10),
            const Offset(10, -10),
            const Offset(10, 10),
            const Offset(-10, 10),
          ],
        );
        follows(
          polygon,
          const Offset(20, 0),
          // In place: the list itself is edited.
          () => polygon.vertices[1] = const Offset(30, -10),
        );
      });

      test('a line, by its end and its width', () {
        final line = Line2DComponent(
          start: const Offset(-20, 0),
          end: const Offset(20, 0),
          strokeWidth: 4,
        );
        follows(
          line,
          const Offset(30, 0),
          () => line.end = const Offset(40, 0),
        );
        final thin = Line2DComponent(
          start: const Offset(-20, 0),
          end: const Offset(20, 0),
          strokeWidth: 2,
        );
        follows(thin, const Offset(0, 6), () => thin.strokeWidth = 20);
      });

      test('anything with a size, by its box', () {
        final sized = _Sized(20, 20);
        follows(sized, const Offset(15, 0), () => sized.width = 40);
      });

      test('a mirrored polygon still builds a body facing out', () {
        final (:world, :queries) = _setUp(make());
        final entity = world.createEntityWithComponents([
          TransformComponent(scale: Vector3(-1, 1, 1)),
          Polygon2DComponent(
            vertices: const [Offset(0, -10), Offset(30, 0), Offset(0, 10)],
          ),
          RigidBody2DComponent(bodyType: BodyType.static),
          Collider2DComponent(shape: Collider2DShape.matchShape),
        ]);
        world.update(1 / 60);
        // The triangle points left now.
        expect(queries.overlapCircle(const Offset(-20, 0), 0.5), [entity]);
        expect(queries.overlapCircle(const Offset(20, 0), 0.5), isEmpty);
      });
    });
  }

  test('an unchanged outline is the same object, asked again', () {
    final circle = Circle2DComponent(radius: 5);
    expect(circle.solidShape2D, same(circle.solidShape2D));
    circle.radius = 6;
    expect(circle.solidShape2D, const SolidCircle2D(6));
    final polygon = Polygon2DComponent(vertices: [Offset.zero]);
    expect(polygon.solidShape2D, isNull, reason: 'fewer than three points');
  });
}
