# World, entities & systems

_Core_ · Model a game as entities that carry components, and its rules as systems that query them every fixed step.

A game is a `World` of entities. An entity is an id with components; a component is plain data; a system is the logic that runs over every entity with the components it needs. `engine.world` is the engine's world.

## Entities and components

A component is any class that extends `Component`. Give it fields and leave the logic to a system:

```dart
import 'package:just_game_engine/just_game_engine.dart';

/// Data: how fast an entity turns, in radians per second.
class SpinComponent extends Component {
  SpinComponent({this.speed = 1.0});

  double speed;
}

/// Logic: turns every entity that has a transform and a spin.
class SpinSystem extends System {
  @override
  int get priority => SystemPriorities.gameplay;

  @override
  List<Type> get requiredComponents => [TransformComponent, SpinComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final spin = entity.getComponent<SpinComponent>()!;
      transform.angle += spin.speed * deltaTime;
    });
  }
}

void addSpinner(World world) {
  world.addSystem(SpinSystem());
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 0, 0)),
    Rectangle2DComponent(width: 80, height: 80),
    SpinComponent(speed: 2),
  ], name: 'Spinner');
}
```

- `world.createEntityWithComponents(components, name: ...)` places the entity with all its components in one go. `world.createEntity(name: ...)` makes an empty one.
- `entity.addComponent(c)`, `removeComponent<T>()`, `getComponent<T>()`, `hasComponent<T>()` and `components` work on one entity. Override `onAttach` and `onDetach` on a component to hear when it is added or removed.
- An entity holds one component of each type: adding a second of a type replaces the first. Every shape and sprite is stored as a `RenderableComponent`, so one entity draws one thing; put a second drawing on a child entity. See [Rendering](/docs/rendering).
- `world.destroyEntity(entity)` removes an entity and everything under it. `destroyAllEntities()` clears the world. Entity ids count up for the life of the world and are never reused; `entity.isAlive` tells you whether a handle you kept still points at a live entity.

## Systems

A system declares `requiredComponents`, implements `update(deltaTime)`, and reads its entities through `entities` or `forEach`. It also has `initialize`, `onAddedToWorld`, `onRemovedFromWorld`, `dispose` and `render(canvas, size)` to override, and an `isActive` switch.

Add one with `world.addSystem(system)`, take it out with `removeSystem`, and find one with `getSystem<T>()` or `hasSystem<T>()`. Adding a system that is already in the world does nothing, and systems may add or remove systems while the world updates.

Systems run by priority, highest first, not in the order you add them; systems of equal priority run in the order they were added. The world places a system by its priority when it is added, so set the priority before adding it (overriding the getter is simplest). The main constants (all of them are in `SystemPriorities`):

| Priority | Constant | What runs |
|---:|---|---|
| 110 | `levelMap` | level maps load and update |
| 108 | `mapCollision` | bodies for map tiles |
| 105 | `parallax` | `ParallaxRenderSystem` scrolls parallax backgrounds |
| 100 | `input` | actions copied onto `InputComponent`s |
| 95 | `playerControl` | your character controller: reads input, sets velocity |
| 90 | `physics` | the physics step |
| 80 | `movement` | velocity onto transform, for entities without a body |
| 70 | `animation` | animators, sprite clips, timelines |
| 65 | `effects` | deterministic effects |
| 60 | `gameplay` | health, lifetime, your game rules |
| 50 | `hierarchy` | children follow their parents |
| 48 | `particles` | particle emitters |
| 45 | `camera` | the camera brain frames the finished positions |
| 40 | `render` | `RenderSystem`, which draws once per display frame |
| −10 | `audio` | sounds follow their entities |

A system that sets no priority runs at 0. If you change a priority after adding the system, call `world.sortSystems()`. An exception thrown by a system ends that update; the engine does not catch it.

## Queries

`world.query([TransformComponent, VelocityComponent])` returns the entities that have every listed type and are active in the hierarchy. A system's `entities` is exactly this query for its `requiredComponents`.

- Results are cached per set of types and rebuilt only when an entity that could match is added, removed, changes components, or is switched on or off. Asking again in the same frame is a lookup.
- A returned list never changes; a later change makes a new one.
- Results come in storage order, not creation order. Set draw order with `LayerComponent`, never by creation order.
- `world.queryVersion(types)` moves on whenever that query's result may have changed, for a system that caches something per entity.

To find one entity, use the indexed lookups instead of scanning `world.entities` every frame: `world.findEntityByName(name)`, and `world.findTagged(tag)` and `world.allTagged(tag)` for tags (see [Tags & spawners](/docs/tags-spawners)). For an entity you touch every frame, look it up once and keep the reference.

## Events and deferred changes

`world.events` is a typed `EventBus`. Subclass `GameEvent`, subscribe with `on<T>()`, and `fire` an event; subscribers of its exact runtime type are called at once. `on` returns an `EventSubscription` to `cancel()`. The engine fires its own events here, such as `CollisionEnter2DEvent` from physics and `TileChangedEvent` from level maps.

`world.commands` is a `CommandBuffer` for structural changes made while a system walks its entities: `create`, `destroy`, `addComponent` and `removeComponent<T>()`. The world applies the queue in order after each system that left commands in it, so the next system sees the change. A command on an entity that is gone by then is skipped.

```dart
class CoinCollected extends GameEvent {
  CoinCollected(this.value);

  final int value;
}

class CoinSystem extends System {
  @override
  List<Type> get requiredComponents => [TagComponent];

  @override
  void update(double deltaTime) {
    for (final coin in world.allTagged('coin')) {
      if (isTouchingPlayer(coin)) {
        world.events.fire(CoinCollected(10));
        world.commands.destroy(coin); // applied after this system
      }
    }
  }

  bool isTouchingPlayer(Entity coin) => false; // your game's test
}

// Somewhere in your game's setup:
// final sub = world.events.on<CoinCollected>((e) => score += e.value);
// sub.cancel(); // when you no longer need it
```

The bus is cleared with the world, so subscriptions do not outlive it.

## Prefabs in code

An `EntityPrefab` is a name and a list of component factories. `world.instantiate(prefab)` calls every factory and creates the entity in one step, so each copy gets fresh components:

```dart
final bullet = EntityPrefab(
  name: 'Bullet',
  factories: [
    () => TransformComponent(),
    () => VelocityComponent(velocity: Vector3(500, 0, 0)),
    () => Circle2DComponent(radius: 4),
  ],
);

Entity fire(World world, Vector3 muzzle) {
  final shot = world.instantiate(bullet);
  shot.getComponent<TransformComponent>()!.position.setFrom(muzzle);
  return shot;
}
```

Prefabs made in the editor are saved as `.prefab.json` files instead; those are covered in [Scenes & saving](/docs/scenes).

## Parents and children

`TransformComponent` is always the world transform: physics, cameras, timelines and your code read and write it in world space. A child's offset from its parent lives in its `ParentComponent` (`localPosition`, `localRotation`, `localScale`), and the world keeps the two in step every update.

```dart
/// Hangs a turret on [tank], 30 units above its centre. From the next
/// update on it moves and turns with the tank.
Entity addTurret(World world, Entity tank) => world.createEntityWithComponents([
  TransformComponent(),
  ParentComponent(parentId: tank.id, localPosition: Vector3(0, -30, 0)),
  Rectangle2DComponent(width: 50, height: 12),
], name: 'Turret');
```

- The world keeps the other end of the link: the tank gets a `ChildrenComponent` listing the turret.
- A `ParentComponent` with no local values leaves the child where its `TransformComponent` puts it and works its offset out from there. Scenes load their links this way.
- To move the turret on the tank later, change `localPosition`. If you write a child's `TransformComponent` directly, its offset is worked out again from where you put it.
- Destroying the tank destroys the turret. Pass `withChildren: false` to `world.destroyEntity` to keep the children where they are.

`entity.isActive` switches one entity on or off. `entity.isActiveInHierarchy` is true only when the entity and every parent above it are switched on. Queries, tag lookups, targets, drawing and simulation all go by `isActiveInHierarchy`, so switching a parent off takes its whole subtree out of the game, while each child keeps its own `isActive`.

## The reactive layer

For Flutter UI that follows game data, the engine wraps the ECS in `just_signals` signals:

- `ComponentSignal<C, T>` is a `Signal` over one component field, with a getter and a setter. `TransformSignals` is a ready-made set; make a `ComponentSignal` for any other field you show (a velocity, a health). Writing through the signal updates the component and notifies listeners; when a system changes the component directly, call `sync()`.
- `EntitySignal` (`entity.toSignal()`) follows an entity's components; `WorldSignal` (`world.toSignal()`) exposes `entityCount`, `systemCount`, `entities` and `query(types)`.
- `ReactiveSystem` processes only entities marked dirty (`markDirty`), in `processEntity`. `AutoSyncSystem` and `SignalSyncMixin` sync signals after a system's update, and the `ReactiveComponent` mixin gives a component its own property signals.

The layer is optional; nothing else in the engine depends on it. Only `Signal` and `Computed` are re-exported by `package:just_game_engine/just_game_engine.dart`. For `SignalBuilder` and the rest, add `just_signals` to your pubspec and import it. For a suggested way to connect systems, signals and widgets, see [UI over the game](/docs/game-widget).
