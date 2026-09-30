// Tags and targets: an entity carries several tags, the world finds them
// through an index that never goes stale, and everything that points at
// another entity says so with one EntityTarget.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  setUp(() => world = World());
  tearDown(() => world.dispose());

  Entity tagged(List<String> tags, {String? name}) =>
      world.createEntityWithComponents([
        TransformComponent(),
        TagComponent.of(tags),
      ], name: name);

  group('TagComponent', () {
    test('carries several tags, trimmed, without blanks or repeats', () {
      final tags = TagComponent.of([' enemy', 'boss', '', 'enemy']);
      expect(tags.tags, ['enemy', 'boss']);
      expect(tags.has('boss'), isTrue);
      expect(tags.add('boss'), isFalse);
      expect(tags.add('flying'), isTrue);
      expect(tags.remove('enemy'), isTrue);
      expect(tags.tags, ['boss', 'flying']);
      expect(TagComponent().isEmpty, isTrue);
    });

    test('the one-tag constructor and field still work', () {
      final tags = TagComponent('player');
      // ignore: deprecated_member_use_from_same_package
      expect(tags.tag, 'player');
      // ignore: deprecated_member_use_from_same_package
      tags.tag = 'enemy';
      expect(tags.tags, ['enemy']);
    });
  });

  group('the tag index', () {
    test('finds the oldest active entity, and all of them', () {
      final a = tagged(['player'], name: 'A');
      final b = tagged(['player', 'hero'], name: 'B');
      tagged(['enemy']);
      expect(world.findTagged('player'), a);
      expect(world.allTagged('player'), [a, b]);
      expect(world.findTagged('hero'), b);
      expect(world.findTagged('nobody'), isNull);
      expect(world.tagsInUse, {'player', 'hero', 'enemy'});

      a.isActive = false;
      expect(world.findTagged('player'), b);
      expect(world.allTagged('player', includeInactive: true), [a, b]);
    });

    test('keeps up with tags added, removed and changed', () {
      final e = world.createEntityWithComponents([TransformComponent()]);
      expect(world.findTagged('coin'), isNull);

      e.addTag('coin');
      expect(world.findTagged('coin'), e);
      expect(e.hasTag('coin'), isTrue);

      e.getComponent<TagComponent>()!.tags = ['gem'];
      expect(world.findTagged('coin'), isNull);
      expect(world.findTagged('gem'), e);

      e.removeTag('gem');
      expect(world.findTagged('gem'), isNull);

      e.addTag('gem');
      e.removeComponent<TagComponent>();
      expect(world.findTagged('gem'), isNull);
      expect(e.tags, isEmpty);
    });

    test('forgets destroyed entities', () {
      final e = tagged(['enemy']);
      expect(world.findTagged('enemy'), e);
      world.destroyEntity(e);
      expect(world.findTagged('enemy'), isNull);
      tagged(['enemy']);
      world.destroyAllEntities();
      expect(world.allTagged('enemy'), isEmpty);
    });
  });

  group('TagNames', () {
    test('takes letters, digits, _ and - only', () {
      expect(TagNames.isValid('player_2'), isTrue);
      expect(TagNames.isValid('boss-fight'), isTrue);
      expect(TagNames.isValid('two words'), isFalse);
      expect(TagNames.problemWith(''), isNotNull);
      expect(TagNames.problemWith('a b'), isNotNull);
    });

    test('knows a near duplicate and a likely typo', () {
      expect(TagNames.areNearDuplicates('Players', 'player'), isTrue);
      expect(TagNames.areNearDuplicates('power_up', 'power-up'), isTrue);
      expect(TagNames.areNearDuplicates('enemy', 'player'), isFalse);
      expect(TagNames.closest('players', ['player', 'enemy']), 'player');
      expect(TagNames.closest('enemmy', ['player', 'enemy']), 'enemy');
      expect(TagNames.closest('checkpoint', ['player', 'enemy']), isNull);
      expect(TagNames.closest('player', ['player']), isNull);
    });
  });

  group('EntityTarget', () {
    test('means one entity by name, or entities by tag', () {
      final door = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Door');
      final a = tagged(['player']);
      final b = tagged(['player']);
      expect(const EntityTarget.name('Door').resolve(world, null), door);
      expect(const EntityTarget.tag('player').resolve(world, null), a);
      expect(const EntityTarget.tag('player').resolveAll(world, null), [a, b]);
      expect(const EntityTarget.self().resolve(world, door), door);
      expect(EntityTarget.none.resolveAll(world, door), isEmpty);
    });

    test('is saved in the shape timeline bindings always were', () {
      for (final (target, json) in [
        (const EntityTarget.self(), 'self'),
        (const EntityTarget.name('Door'), {'name': 'Door'}),
        (const EntityTarget.tag('enemy'), {'tag': 'enemy'}),
        (EntityTarget.none, null),
      ]) {
        expect(target.toJson(), json);
        expect(EntityTarget.fromJson(json), target);
      }
      expect(EntityTarget.parse('#enemy'), const EntityTarget.tag('enemy'));
      expect(EntityTarget.parse('Door'), const EntityTarget.name('Door'));
      expect(const TrackBinding.tag('lift'), const EntityTarget.tag('lift'));
      expect(TrackBinding.fromJson(null), TrackBinding.owner);
    });

    test('an old name and tag pair means the name, else the tag', () {
      expect(
        EntityTarget.fromNameOrTag('Boss', 'player'),
        const EntityTarget.name('Boss'),
      );
      expect(
        EntityTarget.fromNameOrTag('', 'player'),
        const EntityTarget.tag('player'),
      );
      final camera = VirtualCameraComponent();
      // ignore: deprecated_member_use_from_same_package
      camera.followTag = 'player';
      expect(camera.follow, const EntityTarget.tag('player'));
      // ignore: deprecated_member_use_from_same_package
      camera.followName = 'Boss';
      // ignore: deprecated_member_use_from_same_package
      camera.followTag = 'enemy';
      expect(camera.follow, const EntityTarget.name('Boss'));
    });
  });

  group('scene format v6 → v7', () {
    Map<String, dynamic> scene(List<Map<String, dynamic>> entities) => {
      'version': 6,
      'name': 'test',
      'entities': entities,
    };
    Map<String, dynamic>? fieldsOf(Map out, String name, String type) {
      for (final e in out['entities'] as List) {
        if (e['name'] != name) continue;
        for (final c in e['components'] as List) {
          if (c['type'] == type) return c['fields'] as Map<String, dynamic>;
        }
      }
      return null;
    }

    Map<String, dynamic> c(String type, Map<String, dynamic> fields) => {
      'type': type,
      'fields': fields,
    };

    test('a tag becomes a list, and a spawn point names a spawner', () {
      final out = SceneFormat.migrate(
        scene([
          {
            'name': 'Coin',
            'components': [
              c('TagComponent', {'tag': 'coin'}),
            ],
          },
          {
            'name': 'Blank',
            'components': [
              c('TagComponent', {'tag': ''}),
            ],
          },
          {
            'name': 'Spawn',
            'components': [
              c('SpawnComponent', {'tag': 'player'}),
            ],
          },
        ]),
      );
      expect(out['version'], 7);
      expect(fieldsOf(out, 'Coin', 'TagComponent'), {
        'tags': ['coin'],
      });
      expect(fieldsOf(out, 'Blank', 'TagComponent'), {'tags': []});
      expect(fieldsOf(out, 'Spawn', 'SpawnComponent'), {'spawner': 'player'});
    });

    test('name and tag pairs become one target, and say what they chose', () {
      final out = SceneFormat.migrate(
        scene([
          {
            'name': 'Cam',
            'components': [
              // Nothing is called Players: the tag was always what it used.
              c('VirtualCameraComponent', {
                'followName': 'Players',
                'followTag': 'player',
              }),
              c('CameraTriggerComponent', {
                'targetName': 'Door',
                'targetTag': 'player',
              }),
              c('CameraStateDrivenComponent', {
                'sourceName': '',
                'sourceTag': 'player',
              }),
              c('TimelineTriggerComponent', {
                'targetName': '',
                'targetTag': '',
              }),
              c('CameraTargetGroupComponent', {
                'members': [
                  {'name': 'Door', 'tag': '', 'weight': 1.0, 'radius': 0.0},
                ],
              }),
            ],
          },
          {'name': 'Door', 'components': <Object>[]},
        ]),
      );
      expect(fieldsOf(out, 'Cam', 'VirtualCameraComponent'), {
        'follow': {'tag': 'player'},
      });
      expect(fieldsOf(out, 'Cam', 'CameraTriggerComponent'), {
        'target': {'name': 'Door'},
      });
      expect(fieldsOf(out, 'Cam', 'CameraStateDrivenComponent'), {
        'source': {'tag': 'player'},
      });
      expect(fieldsOf(out, 'Cam', 'TimelineTriggerComponent'), {
        'target': null,
      });
      expect(
        (fieldsOf(out, 'Cam', 'CameraTargetGroupComponent')!['members']
            as List)
            .single,
        {
          'target': {'name': 'Door'},
          'weight': 1.0,
          'radius': 0.0,
        },
      );
      expect(V6ToV7.report, hasLength(2));
      expect(V6ToV7.report.first, contains('Players'));
    });

    test('what it writes decodes through the definitions', () {
      ComponentCodecRegistry.instance.clear();
      registerCoreCodecs();
      final out = SceneFormat.migrate(
        scene([
          {
            'name': 'E',
            'components': [
              c('TagComponent', {'tag': 'enemy'}),
              c('SpawnComponent', {'tag': 'wave'}),
              c('VirtualCameraComponent', {
                'followName': '',
                'followTag': 'player',
              }),
            ],
          },
        ]),
      );
      final components = [
        for (final json
            in ((out['entities'] as List).single as Map)['components'] as List)
          ComponentCodecRegistry.instance.decode(json as Map<String, dynamic>),
      ];
      expect((components[0]! as TagComponent).tags, ['enemy']);
      expect((components[1]! as SpawnComponent).spawner, 'wave');
      expect(
        (components[2]! as VirtualCameraComponent).follow,
        const EntityTarget.tag('player'),
      );
    });
  });

  group('TagLibrary', () {
    test('merges declared tags, keeping what the file set on them', () {
      final file = TagLibrary.fromJson({
        'version': 1,
        'tags': [
          {'name': 'coin', 'color': 0xFFFFD54F},
          {'name': 'player', 'description': 'Our hero'},
        ],
      });
      final merged = file.withDeclared(EngineTags.declared);
      expect(merged.names, ['coin', 'player']);
      expect(merged['player']!.isDeclared, isTrue);
      expect(merged['player']!.description, 'Our hero');
      expect(merged['player']!.color, EngineTags.declared.single.color);
      expect(merged['coin']!.isDeclared, isFalse);
      // Declared is never written: code says so every time.
      expect(merged.toJson()['tags'], [
        {'name': 'coin', 'color': 0xFFFFD54F},
        {
          'name': 'player',
          'color': EngineTags.declared.single.color!.toARGB32(),
          'description': 'Our hero',
        },
      ]);
    });

    test('renames in place, and merges into an existing tag', () {
      final lib = TagLibrary([
        const TagDefinition('a'),
        const TagDefinition('b', color: Color(0xFF000000)),
        const TagDefinition('c'),
      ]);
      expect(lib.rename('b', 'bee').names, ['a', 'bee', 'c']);
      expect(lib.rename('bee', 'x'), same(lib));
      expect(lib.rename('a', 'c').names, ['b', 'c']);
      expect(lib.nearDuplicateOf('Bs'), 'b');
      expect(lib.withNames(['a', 'z']).names, ['a', 'b', 'c', 'z']);
      expect(TagLibrary.colorFor('coin'), TagLibrary.colorFor('coin'));
    });
  });

  group('spawn points', () {
    test('are found and spawned the same way everywhere', () {
      Entity point(String spawner) => world.createEntityWithComponents([
        TransformComponent(),
        SpawnComponent(spawner: spawner),
      ]);
      final first = point('player');
      point('player');
      final unknown = point('players');
      expect(SpawnPoints.first(world, 'player'), first);
      expect(SpawnPoints.of(world, 'player'), hasLength(2));

      final missing = <(Entity, String)>[];
      final spawned = SpawnPoints.spawnAll(
        world,
        [
          Spawner(
            id: 'player',
            tags: const {'player'},
            spawn: (w, at) => w.createEntityWithComponents([
              TransformComponent(),
              TagComponent('player'),
            ]),
          ),
        ],
        onMissing: (p, id) => missing.add((p, id)),
      );
      expect(spawned, hasLength(2));
      expect(world.allTagged('player'), spawned);
      expect(missing, [(unknown, 'players')]);
    });

    test('the old field name still works', () {
      // ignore: deprecated_member_use_from_same_package
      final spawn = SpawnComponent(tag: 'wave');
      expect(spawn.spawner, 'wave');
    });
  });

  test('a timeline trigger on a tag fires for any of them', () {
    world.addSystem(TimelineTriggerSystem());
    final trigger = world.createEntityWithComponents([
      TransformComponent(),
      TimelineTriggerComponent(
        width: 100,
        height: 100,
        onEnter: TimelineTriggerAction.nothing,
      ),
    ]);
    tagged(['player']).getComponent<TransformComponent>()!.setPositionXY(
      500,
      0,
    );
    final second = tagged(['player']);
    world.update(1 / 60);
    expect(
      trigger.getComponent<TimelineTriggerComponent>()!.isInside,
      isTrue,
      reason: 'the second player is inside, though the first is not',
    );
    second.getComponent<TransformComponent>()!.setPositionXY(500, 0);
    world.update(1 / 60);
    expect(trigger.getComponent<TimelineTriggerComponent>()!.isInside, isFalse);
  });
}
