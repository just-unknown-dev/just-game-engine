// The hierarchy's audit fixes: a switched-off parent switches off its
// subtree (activeInHierarchy) without touching the children's own flags,
// parent links that would loop are refused, a transform keeps its own
// scale vector, and children of a body moving between steps are drawn
// moving with it.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class Mark extends Component {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  setUp(() => world = World()..initialize());
  tearDown(() => world.dispose());

  Entity make({double x = 0, Entity? parent, String? name}) {
    final e = world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, 0, 0)),
      Mark(),
    ], name: name);
    if (parent != null) e.addComponent(ParentComponent(parentId: parent.id));
    return e;
  }

  group('a switched-off parent switches off its subtree (C7)', () {
    test('children leave queries; their own flags stay as they were', () {
      final parent = make();
      final child = make(parent: parent);
      final grandchild = make(parent: child);
      expect(world.query([Mark]), unorderedEquals([parent, child, grandchild]));

      parent.isActive = false;
      expect(world.query([Mark]), isEmpty);
      expect(child.isActive, isTrue, reason: 'its saved flag is its own');
      expect(child.isActiveInHierarchy, isFalse);
      expect(grandchild.isActiveInHierarchy, isFalse);
      expect(world.stats['activeEntities'], 0);
      expect(world.activeEntities, isEmpty);

      parent.isActive = true;
      expect(world.query([Mark]), unorderedEquals([parent, child, grandchild]));
      expect(grandchild.isActiveInHierarchy, isTrue);
    });

    test(
      'a child switched off itself stays off when its parent comes back',
      () {
        final parent = make();
        final child = make(parent: parent);
        final grandchild = make(parent: child);
        child.isActive = false;
        parent.isActive = false;
        parent.isActive = true;
        expect(child.isActiveInHierarchy, isFalse);
        expect(grandchild.isActiveInHierarchy, isFalse);
        child.isActive = true;
        expect(grandchild.isActiveInHierarchy, isTrue);
      },
    );

    test('follows re-parenting, unlinking and the parent\'s destruction', () {
      final off = make()..isActive = false;
      final on = make();
      final child = make();
      final link = ParentComponent(parentId: off.id);
      child.addComponent(link);
      expect(child.isActiveInHierarchy, isFalse);

      link.parentId = on.id;
      expect(child.isActiveInHierarchy, isTrue);
      link.parentId = off.id;
      expect(child.isActiveInHierarchy, isFalse);
      child.removeComponent<ParentComponent>();
      expect(child.isActiveInHierarchy, isTrue);

      child.addComponent(ParentComponent(parentId: off.id));
      expect(child.isActiveInHierarchy, isFalse);
      world.destroyEntity(off, withChildren: false);
      expect(child.isActiveInHierarchy, isTrue);
      expect(world.query([Mark]), containsAll([on, child]));
    });

    test('an entity made under a switched-off parent starts off', () {
      final off = make()..isActive = false;
      final made = world.createEntityWithComponents([
        Mark(),
        ParentComponent(parentId: off.id),
      ]);
      expect(made.isActive, isTrue);
      expect(made.isActiveInHierarchy, isFalse);
      expect(world.query([Mark]), isEmpty);
    });

    test('destroyed: not active in any sense', () {
      final e = make();
      world.destroyEntity(e);
      expect(e.isActiveInHierarchy, isFalse);
    });

    test('tag and name lookups pass the subtree by', () {
      final parent = make();
      final child = world.createEntityWithComponents([
        TagComponent('enemy'),
        ParentComponent(parentId: parent.id),
      ], name: 'kid');
      expect(world.findTagged('enemy'), child);
      parent.isActive = false;
      expect(world.findTagged('enemy'), isNull);
      expect(world.allTagged('enemy'), isEmpty);
      expect(world.findTagged('enemy', includeInactive: true), child);
      expect(world.findEntityByName('kid', includeInactive: false), isNull);
      parent.isActive = true;
      expect(world.allTagged('enemy'), [child]);
    });

    test('the query versions of the subtree move on', () {
      final parent = world.createEntityWithComponents([TransformComponent()]);
      final child = world.createEntityWithComponents([
        Mark(),
        ParentComponent(parentId: parent.id),
      ]);
      final before = world.queryVersion([Mark]);
      parent.isActive = false;
      expect(world.queryVersion([Mark]), isNot(before));
      expect(child.isActiveInHierarchy, isFalse);
    });

    test(
      'children are not moved, drawn or culled while their parent is off',
      () {
        world.addSystem(MovementSystem());
        final render = RenderSystem();
        world.addSystem(render);
        final parent = world.createEntityWithComponents([TransformComponent()]);
        final child = world.createEntityWithComponents([
          TransformComponent(),
          VelocityComponent(velocity: Vector3(10, 0, 0)),
          RectangleComponent(width: 2, height: 2),
          ParentComponent(parentId: parent.id),
        ]);
        world.update(1.0);
        expect(render.debugDrawOrder().map((d) => d.$1), [child]);
        final x = child.getComponent<TransformComponent>()!.position.x;

        parent.isActive = false;
        world.update(1.0);
        expect(render.debugDrawOrder(), isEmpty);
        expect(
          child.getComponent<TransformComponent>()!.position.x,
          x,
          reason: 'the movement system passes it by',
        );
      },
    );

    test('a switched-off subtree still follows its parent, not frozen', () {
      final parent = make();
      final child = make(x: 10, parent: parent);
      world.update(0.016);
      parent.isActive = false;
      parent.getComponent<TransformComponent>()!.position.x = 100;
      world.update(0.016);
      expect(child.getComponent<TransformComponent>()!.position.x, 110);
      parent.isActive = true;
      world.update(0.016);
      expect(child.getComponent<TransformComponent>()!.position.x, 110);
    });

    test('a scene saved switched off loads its subtree off', () {
      final scene = {
        'version': SceneFormat.current,
        'entities': [
          {'name': 'folder', 'enabled': false, 'components': <Object>[]},
          {
            'name': 'inside',
            'parentName': 'folder',
            'components': [
              {'type': 'TransformComponent', 'fields': <String, Object>{}},
            ],
          },
        ],
      };
      final made = SceneLoader.load(world, scene);
      expect(made[1].isActive, isTrue);
      expect(made[1].isActiveInHierarchy, isFalse);
      expect(world.query([TransformComponent]), isEmpty);
    });
  });

  group('links that would loop are refused (C10)', () {
    test('under its own descendant, or itself', () {
      final a = make();
      final b = make(parent: a);
      final c = make(parent: b);
      final link = a.addComponentAndGet(ParentComponent());
      expect(() => link.parentId = c.id, throwsArgumentError);
      expect(link.parentId, isNull, reason: 'nothing changed');
      expect(() => link.parentId = a.id, throwsArgumentError);
      expect(
        c.getComponent<ChildrenComponent>()?.childIds ?? const [],
        isEmpty,
      );
      expect(
        () => a.addComponent(ParentComponent(parentId: b.id)),
        throwsArgumentError,
      );
      expect(identical(a.getComponent<ParentComponent>(), link), isTrue);
      // Moving a whole branch elsewhere is fine.
      final d = make();
      b.getComponent<ParentComponent>()!.parentId = d.id;
      expect(b.getComponent<ParentComponent>()!.parentId, d.id);
    });

    test('the hierarchy stops on a list that leads back up', () {
      final a = make();
      final b = make(x: 5, parent: a);
      // A hand-made list naming an ancestor as a child.
      b.addComponent(ChildrenComponent()..addChild(a.id));
      world.transformHierarchy.propagate();
      world.transformHierarchy.propagateFrom(a);
      world.transformHierarchy.adopt(b);
      expect(b.getComponent<TransformComponent>()!.position.x, 5);
    });

    test('a scene whose parents loop loads, with the loop cut', () {
      final scene = {
        'version': SceneFormat.current,
        'entities': [
          {'name': 'a', 'parentName': 'b', 'components': <Object>[]},
          {'name': 'b', 'parentName': 'a', 'components': <Object>[]},
        ],
      };
      final made = SceneLoader.load(world, scene);
      final parents = [
        for (final e in made) e.getComponent<ParentComponent>()?.parentId,
      ];
      expect(parents.where((p) => p == null), hasLength(1));
      world.update(0.016);
    });
  });

  test('a transform keeps its own scale vector (C11)', () {
    final scale = Vector3(2, 3, 4);
    final t = TransformComponent(scale: scale);
    t.scale.x = 9;
    expect(scale.x, 2);
    expect(t.scale.y, 3);
  });

  group('children of a body moving between steps (P7)', () {
    test('get their previous pose from their parent\'s, counted a capture', () {
      final parent = make();
      final child = make(x: 10, parent: parent);
      world.update(0.016); // links settle
      world.addSystem(_Stepper(parent));
      final ct = child.getComponent<TransformComponent>()!;
      final captures = ct.captureCount;
      world.update(0.016); // parent captured at 0, moved to 4
      expect(ct.captureCount, captures + 1);
      expect(ct.position.x, 14);
      expect(ct.prevPosition.x, 10);
    });

    test('a turning parent turns its child\'s previous pose too', () {
      final parent = make();
      final child = make(x: 10, parent: parent);
      world.update(0.016);
      world.addSystem(_Stepper(parent, turn: 0.5));
      world.update(0.016);
      world.update(0.016);
      final ct = child.getComponent<TransformComponent>()!;
      final pt = parent.getComponent<TransformComponent>()!;
      expect(ct.prevAngle, closeTo(pt.prevAngle, 1e-12));
      expect(ct.angle, closeTo(pt.angle, 1e-12));
    });

    test('are drawn between the two poses by the render system', () {
      final parent = make();
      final child = world.createEntityWithComponents([
        TransformComponent(position: Vector3(10, 0, 0)),
        RectangleComponent(width: 2, height: 2),
        ParentComponent(parentId: parent.id),
      ]);
      final render = RenderSystem()..interpolation = 0.5;
      world.addSystem(render);
      world.update(0.016); // links settle
      _draw(render);
      world.addSystem(_Stepper(parent));
      world.update(0.016); // parent 0 → 4, child 10 → 14
      _draw(render);
      final drawn = child.getComponent<RenderableComponent>()!.renderable;
      expect(drawn.position.x, closeTo(12, 1e-9));
    });

    test('a child moved by something else keeps its own previous pose', () {
      final parent = make();
      final child = make(x: 10, parent: parent);
      world.update(0.016);
      world.addSystem(_Stepper(parent));
      world.update(0.016);
      final ct = child.getComponent<TransformComponent>()!;
      ct.position.x = 50; // gameplay puts it somewhere
      final captures = ct.captureCount;
      world.update(0.016);
      expect(ct.captureCount, captures);
      expect(ct.position.x, 50);
    });

    test('an entity not captured is drawn where it is', () {
      final still = world.createEntityWithComponents([
        TransformComponent(position: Vector3(5, 0, 0)),
        RectangleComponent(width: 2, height: 2),
      ]);
      final render = RenderSystem()..interpolation = 0.5;
      world.addSystem(render);
      world.update(0.016);
      _draw(render);
      still.getComponent<TransformComponent>()!.prevPosition.setValues(0, 0, 0);
      world.update(0.016);
      _draw(render);
      final drawn = still.getComponent<RenderableComponent>()!.renderable;
      expect(drawn.position.x, 5);
    });
  });
}

void _draw(RenderSystem render) {
  final recorder = PictureRecorder();
  render.render(Canvas(recorder), const Size(800, 600));
  recorder.endRecording();
}

/// Before the hierarchy, like a physics step: captures [target]'s pose,
/// then moves it 4 to the right (and turns it [turn]).
class _Stepper extends System {
  _Stepper(this.target, {this.turn = 0});
  final Entity target;
  final double turn;

  @override
  int get priority => SystemPriorities.physics;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    final t = target.getComponent<TransformComponent>()!;
    t.capturePrevious();
    t.position.x += 4;
    t.angle += turn;
  }
}

extension on Entity {
  T addComponentAndGet<T extends Component>(T component) {
    addComponent(component);
    return component;
  }
}
