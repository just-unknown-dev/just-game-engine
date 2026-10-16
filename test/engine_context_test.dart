// One context per engine: what it registers, who owns it, and that two never
// share anything.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Marker extends Component {
  _Marker([this.value = 0]);
  int value;
}

final _markerDefinition = ComponentDefinition<_Marker>(
  type: 'MarkerComponent',
  create: _Marker.new,
  fields: [
    SchemaField(
      name: 'value',
      kind: FieldTypes.integer,
      read: (c) => (c as _Marker).value,
      write: (c, v) => (c as _Marker).value = (v as num).toInt(),
    ),
  ],
);

final class _MarkerExtension implements ContextExtension {
  _MarkerExtension(this.installs);
  final List<String> installs;

  @override
  String get id => 'marker';

  @override
  void install(EngineContext context) {
    installs.add(id);
    context.definitions.register(_markerDefinition);
  }
}

/// Files from a map, for a context's bundle.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);
  final Map<String, String> files;
  final List<String> reads = [];

  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    final text = files[key];
    if (text == null) throw StateError('no $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

class _Disposable implements ContextResource {
  bool disposed = false;
  @override
  void dispose() => disposed = true;
}

void main() {
  group('EngineContext', () {
    test('starts with the core definitions and field types', () {
      final context = EngineContext();
      addTearDown(context.dispose);
      expect(
        context.definitions.definitionByType('TransformComponent'),
        isNotNull,
      );
      expect(context.definitions.byName('AnimatorComponent'), isNotNull);
      expect(context.fieldTypes.byId(FieldTypes.decimal.id), isNotNull);
    });

    test('withBuiltIns: false starts empty', () {
      final context = EngineContext(withBuiltIns: false);
      addTearDown(context.dispose);
      expect(context.definitions.types, isEmpty);
      expect(context.fieldTypes.all, isEmpty);
    });

    test('an extension is installed once, by id', () {
      final installs = <String>[];
      final context = EngineContext(extensions: [_MarkerExtension(installs)]);
      addTearDown(context.dispose);
      context.install(_MarkerExtension(installs));
      expect(installs, ['marker']);
      expect(context.isInstalled('marker'), isTrue);
      expect(context.installed, ['marker']);
      expect(
        context.definitions.definitionByType('MarkerComponent'),
        same(_markerDefinition),
      );
    });

    test('a slot is made once, and a resource in it is disposed with it', () {
      final context = EngineContext();
      final key = Object();
      final made = context.slot(key, _Disposable.new);
      expect(context.slot(key, _Disposable.new), same(made));
      context.dispose();
      expect(made.disposed, isTrue);
      expect(context.isDisposed, isTrue);
    });

    test("two contexts never see each other's registrations", () {
      final a = EngineContext(extensions: [_MarkerExtension([])]);
      final b = EngineContext();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(a.definitions.definitionByType('MarkerComponent'), isNotNull);
      expect(b.definitions.definitionByType('MarkerComponent'), isNull);
    });

    test('ComponentDefinitionRegistry.core() is fresh each time', () {
      final a = ComponentDefinitionRegistry.core();
      final b = ComponentDefinitionRegistry.core();
      a.register(_markerDefinition);
      expect(b.definitionByType('MarkerComponent'), isNull);
      expect(b.definitionByType('TransformComponent'), isNotNull);
    });
  });

  group('assets', () {
    test("load from the context's bundle, through its manager", () async {
      final bundle = _MapBundle({'a.txt': 'hello', 'b.json': '{"v": 1}'});
      final context = EngineContext(bundle: bundle);
      addTearDown(context.dispose);

      final text = await context.assets.loadText('a.txt');
      expect(text.content, 'hello');
      expect(text.manager, same(context.assets));
      expect((await context.assets.loadJson('b.json')).data, {'v': 1});
      expect(bundle.reads, ['a.txt', 'b.json']);
    });

    test('an atlas asset needs a manager to load', () async {
      expect(AtlasAsset('x.json').load(), throwsStateError);
    });

    test('two contexts cache separately', () async {
      final a = EngineContext(bundle: _MapBundle({'t.txt': 'a'}));
      final b = EngineContext(bundle: _MapBundle({'t.txt': 'b'}));
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect((await a.assets.loadText('t.txt')).content, 'a');
      expect((await b.assets.loadText('t.txt')).content, 'b');
    });
  });

  group('loaders', () {
    test('overrideLoaders swaps the seams of one context only', () async {
      final a = EngineContext(bundle: _MapBundle({'m.txt': 'bundle'}));
      final b = EngineContext();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final bSprites = b.sprites;
      final bText = b.tiles.readText;

      Future<String> files(String path) async => 'file';
      final override = a.overrideLoaders(tileText: files);
      expect(await a.tiles.readText('m.txt'), 'file');
      expect(b.tiles.readText, same(bText));
      expect(b.sprites, same(bSprites));

      override.restore();
      expect(await a.tiles.readText('m.txt'), 'bundle');
    });

    test('restore leaves a seam someone changed since', () {
      final context = EngineContext();
      addTearDown(context.dispose);
      final original = context.sprites;
      final mine = BundleSpriteAssetLoader(context.assets);
      final later = BundleSpriteAssetLoader(context.assets);
      final override = context.overrideLoaders(sprites: mine);
      expect(context.sprites, same(mine));
      context.sprites = later;
      override.restore();
      expect(context.sprites, same(later));
      context.useBundle();
      expect(context.sprites, same(original));
    });

    test('useBundle puts the tile reader back and forgets what it read', () {
      final context = EngineContext(bundle: _MapBundle({}));
      addTearDown(context.dispose);
      context.overrideLoaders(tileText: (_) async => '{}');
      context.tiles.putTileset('t.tileset.json', TilesetData());
      final before = context.tiles.revision;
      context.useBundle();
      expect(context.tiles.loadedTileset('t.tileset.json'), isNull);
      expect(context.tiles.revision, greaterThan(before));
      expect(context.tiles.readText('t.tileset.json'), throwsStateError);
    });
  });

  group('registries', () {
    test('each context has its own; the built-in tables cannot change', () {
      final a = EngineContext();
      final b = EngineContext();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      a.easings.register('snap', (t) => t < 0.5 ? 0 : 1);
      a.animatorBindings.register('seven', (_) => 7);
      a.collisionKinds.register(
        const MapCollisionKind(id: 'ice', label: 'Ice'),
      );
      a.trackKinds.register('noop', (json) => UnknownTrack(json));
      a.effectTypes.register('none', (json, s) => DelayEffect());

      expect(a.easings.apply('snap', 0.7), 1);
      expect(b.easings.apply('snap', 0.7), 0.7, reason: 'linear fallback');
      expect(b.animatorBindings.of('seven'), isNull);
      expect(b.collisionKinds.byId('ice'), isNull);
      expect(b.trackKinds.has('noop'), isFalse);
      expect(b.effectTypes.decoderFor('none'), isNull);

      expect(
        () => KeyEasings.builtIn.register('x', (t) => t),
        throwsUnsupportedError,
      );
      expect(
        () => MapCollisionKinds.builtIn.register(MapCollisionKinds.solid),
        throwsUnsupportedError,
      );
      expect(
        () => TimelineTrackKinds.builtIn.register('x', UnknownTrack.new),
        throwsUnsupportedError,
      );
      expect(
        () => EffectTypes.builtIn.register('x', (j, s) => DelayEffect()),
        throwsUnsupportedError,
      );
      expect(TimelineTrackKinds.builtIn.kinds, hasLength(7));
      expect(MapCollisionKinds.builtIn.all, [
        MapCollisionKinds.solid,
        MapCollisionKinds.oneWay,
      ]);
    });

    test('resolve leaves an asset with nothing to read again as it is', () {
      final asset = TimelineAsset(
        tracks: [
          UnknownTrack({'kind': 'x'}),
        ],
      );
      expect(TimelineTrackKinds().resolve(asset), same(asset));
    });

    test('effects decode through the types given', () {
      final types = EffectTypes()
        ..register('custom', (json, s) => DelayEffect(durationTicks: 3));
      final nested = {
        'type': 'sequence',
        'children': [
          {'type': 'custom'},
        ],
        'loop': false,
      };
      final effect = EffectSerializer(types).decodeEffect(nested);
      expect((effect as SequenceEffect).children.single.durationTicks, 3);
      expect(
        () => EffectSerializer().decodeEffect(nested),
        throwsArgumentError,
      );
    });
  });

  group('signals', () {
    test('reach every world on a context, and no other', () {
      final shared = EngineContext();
      addTearDown(shared.dispose);
      final level = World(context: shared);
      final screens = World(context: shared);
      final other = World();
      addTearDown(other.dispose);
      final heard = <String>[];
      final elsewhere = <String>[];
      final a = level.context.signals.stream.listen(heard.add);
      final b = other.context.signals.stream.listen(elsewhere.add);
      addTearDown(a.cancel);
      addTearDown(b.cancel);

      screens.context.signals.emit('open');
      expect(heard, ['open']);
      expect(elsewhere, isEmpty);
    });

    test('a disposed bus sends nothing, and says it ended', () async {
      final context = EngineContext();
      var done = false;
      context.signals.stream.listen((_) {}, onDone: () => done = true);
      context.dispose();
      await pumpEventQueue();
      expect(done, isTrue);
      context.signals.emit('late'); // No throw.
      expect(context.signals.isDisposed, isTrue);
    });
  });

  group('World and its context', () {
    test('a bare World owns a fresh context and disposes it', () {
      final world = World();
      final context = world.context;
      expect(
        context.definitions.definitionByType('TransformComponent'),
        isNotNull,
      );
      world.dispose();
      expect(context.isDisposed, isTrue);
    });

    test('a world given a context leaves it to its owner', () {
      final context = EngineContext();
      addTearDown(context.dispose);
      final world = World(context: context)..dispose();
      expect(world.context, same(context));
      expect(context.isDisposed, isFalse);
    });

    test('two bare worlds have separate contexts', () {
      final a = World();
      final b = World();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.context.definitions.register(_markerDefinition);
      expect(b.context.definitions.definitionByType('MarkerComponent'), isNull);
    });

    test("the scene loader reads with the world's definitions", () {
      final world = World(
        context: EngineContext(extensions: [_MarkerExtension([])]),
      );
      addTearDown(() {
        world.dispose();
        world.context.dispose();
      });
      final loaded = SceneLoader.load(world, {
        'version': SceneFormat.current,
        'entities': [
          {
            'name': 'M',
            'components': [
              {
                'type': 'MarkerComponent',
                'fields': {'value': 7},
              },
            ],
          },
        ],
      });
      expect(loaded.single.getComponent<_Marker>()!.value, 7);

      final bare = World();
      addTearDown(bare.dispose);
      expect(
        () => SceneLoader.load(bare, {
          'version': SceneFormat.current,
          'entities': [
            {
              'name': 'M',
              'components': [
                {'type': 'MarkerComponent', 'fields': <String, dynamic>{}},
              ],
            },
          ],
        }),
        throwsA(
          isA<UnknownComponentTypeException>().having(
            (e) => e.toString(),
            'message',
            contains('world.context'),
          ),
        ),
      );
    });
  });
}
