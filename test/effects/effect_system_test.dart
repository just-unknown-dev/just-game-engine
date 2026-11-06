// EffectSystem: scheduling, cancelling, and snapshots — JSON and binary —
// restored onto a world, including a rollback over effects scheduled after
// the snapshot.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A world with an [EffectSystem] and [count] entities at the origin.
(World, EffectSystem, List<Entity>) _world({int count = 1}) {
  final world = World()..initialize();
  final system = EffectSystem();
  world.addSystem(system);
  final entities = [
    for (var i = 0; i < count; i++)
      world.createEntityWithComponents([TransformComponent()]),
  ];
  return (world, system, entities);
}

double _x(Entity e) => e.getComponent<TransformComponent>()!.position.x;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scheduleEffect adds an EffectComponent and the move plays out', () {
    final (world, system, [entity]) = _world();
    addTearDown(world.dispose);
    expect(entity.getComponent<EffectComponent>(), isNull);

    system.scheduleEffect(
      entity: entity,
      effect: MoveEffect(to: Vector3(400, 0, 0), durationTicks: 4),
    );
    expect(entity.getComponent<EffectComponent>(), isNotNull);

    final xs = <double>[];
    for (var i = 0; i < 6; i++) {
      world.update(1 / 60);
      xs.add(_x(entity));
    }
    expect(xs, [100, 200, 300, 400, 400, 400]);
    expect(system.currentTick, 6);
    expect(entity.getComponent<EffectComponent>()!.player.isEmpty, isTrue);
  });

  test('cancelEffect mid-way leaves the entity where it was', () {
    final (world, system, [entity]) = _world();
    addTearDown(world.dispose);
    final handle = system.scheduleEffect(
      entity: entity,
      effect: MoveEffect(to: Vector3(400, 0, 0), durationTicks: 4),
    );
    world
      ..update(1 / 60)
      ..update(1 / 60);
    expect(_x(entity), 200);

    system.cancelEffect(entity, handle);
    world
      ..update(1 / 60)
      ..update(1 / 60);
    expect(_x(entity), 200);
    expect(handle.isCancelled, isTrue);
    expect(entity.getComponent<EffectComponent>()!.player.isEmpty, isTrue);
  });

  test('a later start tick waits for it', () {
    final (world, system, [entity]) = _world();
    addTearDown(world.dispose);
    system.scheduleEffect(
      entity: entity,
      effect: MoveEffect(to: Vector3(200, 0, 0), durationTicks: 2),
      startTick: 3,
    );
    final xs = <double>[];
    for (var i = 0; i < 5; i++) {
      world.update(1 / 60);
      xs.add(_x(entity));
    }
    expect(xs, [0, 0, 0, 100, 200]);
  });

  test('a snapshot sent as bytes resumes the same on another world', () {
    final (a, systemA, [entityA]) = _world();
    addTearDown(a.dispose);
    systemA.scheduleEffect(
      entity: entityA,
      effect: MoveEffect(to: Vector3(400, 0, 0), durationTicks: 8),
    );
    for (var i = 0; i < 3; i++) {
      a.update(1 / 60);
    }
    final bytes = systemA.snapshotToBytes();

    // The joining peer has the same entity, already where A's is.
    final (b, systemB, [entityB]) = _world();
    addTearDown(b.dispose);
    expect(entityB.id, entityA.id);
    entityB.getComponent<TransformComponent>()!.position = Vector3(
      _x(entityA),
      0,
      0,
    );
    systemB.restoreFromBytes(bytes, b);
    expect(systemB.currentTick, systemA.currentTick);

    for (var i = 0; i < 6; i++) {
      a.update(1 / 60);
      b.update(1 / 60);
      expect(_x(entityB), _x(entityA), reason: 'after ${i + 1} more ticks');
    }
    expect(_x(entityB), 400);
  });

  test('a snapshot survives JSON, through the serializer', () {
    final (world, system, [entity]) = _world();
    addTearDown(world.dispose);
    system.scheduleEffect(
      entity: entity,
      effect: SequenceEffect(
        children: [
          MoveEffect(to: Vector3(10, 0, 0), durationTicks: 2),
          ShakeEffect(amplitude: 4, durationTicks: 6),
        ],
      ),
    );
    world.update(1 / 60);
    final snapshot = system.snapshotState();
    final serializer = EffectSerializer();
    final copy = serializer.decodeSnapshot(serializer.encodeSnapshot(snapshot));
    expect(copy.tick, snapshot.tick);
    expect(copy.toJson(), snapshot.toJson());
    // And the copy restores into a player that encodes the same again.
    system.restoreSnapshot(copy, world);
    expect(system.snapshotState().toJson(), snapshot.toJson());
  });

  test('bytes with another version are refused', () {
    final (world, system, _) = _world();
    addTearDown(world.dispose);
    final bytes = Uint8List.fromList(system.snapshotToBytes());
    expect(bytes.first, 1);
    bytes[0] = 2;
    expect(
      () => EffectBinaryCodec.decode(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('a rollback drops effects scheduled after the snapshot', () {
    final (world, system, [a, b]) = _world(count: 2);
    addTearDown(world.dispose);
    system.scheduleEffect(
      entity: a,
      effect: MoveEffect(to: Vector3(100, 0, 0), durationTicks: 10),
    );
    world
      ..update(1 / 60)
      ..update(1 / 60);
    final snapshot = system.snapshotState(); // only A has effects
    expect(snapshot.entityEffects.keys, [a.id]);

    system.scheduleEffect(
      entity: b,
      effect: MoveEffect(to: Vector3(50, 0, 0), durationTicks: 10),
    );
    world
      ..update(1 / 60)
      ..update(1 / 60);
    expect(b.getComponent<EffectComponent>()!.player.isEmpty, isFalse);

    system.restoreSnapshot(snapshot, world);
    expect(system.currentTick, 2);
    expect(b.getComponent<EffectComponent>()!.player.isEmpty, isTrue);
    expect(a.getComponent<EffectComponent>()!.player.activeCount, 1);
    final bx = _x(b);
    world.update(1 / 60);
    expect(_x(b), bx, reason: "B's move is gone");
  });

  test('a switched-off entity is in the snapshot and is restored', () {
    final (world, system, [a, b]) = _world(count: 2);
    addTearDown(world.dispose);
    system.scheduleEffect(
      entity: b,
      effect: MoveEffect(to: Vector3(100, 0, 0), durationTicks: 10),
    );
    world.update(1 / 60);
    b.isActive = false;
    final snapshot = system.snapshotState();
    expect(snapshot.entityEffects.keys, [b.id]);

    // An effect scheduled on it after the snapshot goes in a rollback.
    system.scheduleEffect(
      entity: b,
      effect: ShakeEffect(amplitude: 3, durationTicks: 4),
    );
    expect(b.getComponent<EffectComponent>()!.player.activeCount, 2);
    system.restoreSnapshot(snapshot, world);
    expect(b.getComponent<EffectComponent>()!.player.activeCount, 1);
    expect(a.getComponent<EffectComponent>(), isNull);
  });
}
