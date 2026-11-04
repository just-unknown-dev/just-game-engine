// The 2-D material library: which images it may dispose (only its own), a
// variant whose missing parent appears later, materials that cannot be
// resolved yet, what it lets go of between levels, and where an engine
// keeps its library.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _normals = 'assets/fx/rock_normal.png';

Future<ui.Image> _image() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFF8080FF),
  );
  final picture = recorder.endRecording();
  return picture.toImage(4, 4).whenComplete(picture.dispose);
}

/// A loader keeping one image per path and handing that same image to
/// everyone, as an editor's file loader does: never the caller's to dispose.
class _SharedImages extends SpriteAssetLoader {
  _SharedImages(this.image);
  final ui.Image image;
  int reads = 0;

  @override
  Future<ui.Image> loadImage(String path) async {
    reads++;
    return image;
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

/// A loader handing out a clone each time, the caller's own to dispose.
class _ClonedImages extends SpriteAssetLoader {
  _ClonedImages(this.image);
  final ui.Image image;
  final List<ui.Image> given = [];

  @override
  bool get callerDisposesImages => true;

  @override
  Future<ui.Image> loadImage(String path) async {
    final clone = image.clone();
    given.add(clone);
    return clone;
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

Future<void> _settle() => pumpEventQueue();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image source;
  setUpAll(() async => source = await _image());

  group('images a material names', () {
    test(
      'a shared image is never disposed: not on reload, not on clear',
      () async {
        final context = EngineContext();
        final loader = _SharedImages(source.clone());
        context.sprites = loader;
        final library = context.material2DLibrary;

        expect(library.imageOf(_normals), isNull, reason: 'being read');
        await _settle();
        expect(library.imageOf(_normals), same(loader.image));

        // Saved again: the loader still hands out its one image.
        library.reload(_normals);
        await _settle();
        expect(loader.reads, 2);
        expect(loader.image.debugDisposed, isFalse);
        expect(library.imageOf(_normals), same(loader.image));

        library.clear();
        expect(loader.image.debugDisposed, isFalse);
        context.dispose();
        expect(loader.image.debugDisposed, isFalse);
        loader.image.dispose();
      },
    );

    test(
      'its own clones are disposed when replaced and with the context',
      () async {
        final context = EngineContext();
        final loader = _ClonedImages(source);
        context.sprites = loader;
        final library = context.material2DLibrary;

        library.imageOf(_normals);
        await _settle();
        final first = library.imageOf(_normals)!;
        library.reload(_normals);
        await _settle();
        final second = library.imageOf(_normals)!;
        expect(second, isNot(same(first)));
        expect(first.debugDisposed, isTrue, reason: 'replaced');
        expect(second.debugDisposed, isFalse);

        context.dispose();
        expect(second.debugDisposed, isTrue, reason: 'the context is gone');
        expect(loader.given.every((i) => i.debugDisposed), isTrue);
      },
    );

    test(
      'a superseded read is disposed only when it is the library\'s',
      () async {
        final shared = _SharedImages(source.clone());
        final sharedLibrary = Material2DLibrary(
          (path) async => '{}',
          readImage: shared.loadImage,
        );
        sharedLibrary.imageOf(_normals);
        sharedLibrary.reload(_normals); // The first read is now stale.
        await _settle();
        expect(shared.image.debugDisposed, isFalse);
        sharedLibrary.dispose();
        expect(shared.image.debugDisposed, isFalse);
        shared.image.dispose();

        final cloned = _ClonedImages(source);
        final ownLibrary = Material2DLibrary(
          (path) async => '{}',
          readImage: cloned.loadImage,
          ownsImages: () => true,
        );
        ownLibrary.imageOf(_normals);
        ownLibrary.reload(_normals);
        await _settle();
        expect(cloned.given, hasLength(2));
        expect(cloned.given.first.debugDisposed, isTrue, reason: 'stale');
        expect(cloned.given.last.debugDisposed, isFalse);
        ownLibrary.dispose();
        expect(cloned.given.last.debugDisposed, isTrue);
      },
    );
  });

  group('variants', () {
    late Map<String, String> files;
    late Material2DLibrary library;
    setUp(() {
      files = {
        'a.material2d.json':
            '{"parent": "base.material2d.json", "glow": {"radius": 3}}',
      };
      library = Material2DLibrary(
        (path) async => files[path] ?? (throw StateError('no $path')),
      );
    });

    test(
      'a parent created after its variant was read is used once read',
      () async {
        library.fileOf('a.material2d.json');
        await _settle();
        expect(
          library.problemsOf('a.material2d.json').single,
          contains('base.material2d.json'),
        );
        expect(library.fileOf('a.material2d.json')!.isOn('outline'), isFalse);

        files['base.material2d.json'] = '{"outline": {"width": 2}}';
        library.reload('base.material2d.json');
        await _settle();
        expect(library.problemsOf('a.material2d.json'), isEmpty);
        final file = library.fileOf('a.material2d.json')!;
        expect(file.isOn('outline'), isTrue, reason: 'the parent, found');
        expect(file.isOn('glow'), isTrue);
      },
    );

    test('a parent previewed after its variant was read is used', () async {
      library.fileOf('a.material2d.json');
      await _settle();
      expect(library.problemsOf('a.material2d.json'), isNotEmpty);

      library.preview(
        'base.material2d.json',
        Material2DFile.parse('{"flash": {"amount": 0.5}}'),
      );
      expect(library.problemsOf('a.material2d.json'), isEmpty);
      expect(library.fileOf('a.material2d.json')!.isOn('flash'), isTrue);
    });
  });

  group('materials not read yet', () {
    test('ask again and again without reading again, then appear', () async {
      final files = <String, String>{};
      var reads = 0;
      final library = Material2DLibrary((path) async {
        reads++;
        return files[path] ?? (throw StateError('no $path'));
      });
      for (var i = 0; i < 100; i++) {
        expect(library.fileOf('gone.material2d.json'), isNull);
      }
      await _settle();
      for (var i = 0; i < 100; i++) {
        expect(library.fileOf('gone.material2d.json'), isNull);
        expect(library.problemsOf('gone.material2d.json'), isEmpty);
      }
      expect(reads, 1);
      expect(library.errorOf('gone.material2d.json'), isNotNull);

      files['gone.material2d.json'] = '{"tint": {}}';
      library.reload('gone.material2d.json');
      expect(library.fileOf('gone.material2d.json'), isNull, reason: 'read');
      await _settle();
      expect(library.fileOf('gone.material2d.json')!.isOn('tint'), isTrue);
      expect(reads, 2);
    });

    test('a variant waits for its parent, then draws with it', () async {
      final files = <String, String>{
        'v.material2d.json': '{"parent": "p.material2d.json"}',
        'p.material2d.json': '{"greyscale": {}}',
      };
      final library = Material2DLibrary(
        (path) async => files[path] ?? (throw StateError('no $path')),
      );
      expect(library.fileOf('v.material2d.json'), isNull);
      await _settle();
      expect(library.fileOf('v.material2d.json')!.isOn('greyscale'), isTrue);
    });
  });

  group('between levels', () {
    test('retainOnly keeps the files kept, their parents and previews, and '
        'what they name; the rest goes', () async {
      final files = <String, String>{
        'kept.material2d.json': '{"parent": "base.material2d.json"}',
        'base.material2d.json': '{"normalMap": {"map": "assets/base_n.png"}}',
        'gone.material2d.json': '{"normalMap": {"map": "assets/gone_n.png"}}',
      };
      var reads = 0;
      final loader = _ClonedImages(source);
      final library = Material2DLibrary(
        (path) async {
          reads++;
          return files[path] ?? (throw StateError('no $path'));
        },
        readImage: loader.loadImage,
        ownsImages: () => true,
      );
      addTearDown(library.dispose);
      library
        ..preview(
          'edited.material2d.json',
          Material2DFile.parse('{"normalMap": {"map": "assets/edited_n.png"}}'),
        )
        ..fileOf('kept.material2d.json')
        ..fileOf('gone.material2d.json');
      await _settle();
      const images = [
        'assets/base_n.png',
        'assets/gone_n.png',
        'assets/edited_n.png',
      ];
      images.forEach(library.imageOf);
      await _settle();
      final [base, gone, edited] = [
        for (final i in images) library.imageOf(i)!,
      ];
      final before = reads;

      expect(library.retainOnly(['kept.material2d.json']), [
        'assets/gone_n.png',
      ]);
      expect(gone.debugDisposed, isTrue, reason: 'its own, let go');
      expect(base.debugDisposed, isFalse, reason: "the kept one's parent's");
      expect(edited.debugDisposed, isFalse, reason: "an unsaved preview's");
      expect(library.fileOf('kept.material2d.json'), isNotNull);
      expect(library.isPreviewing('edited.material2d.json'), isTrue);
      expect(library.imageOf('assets/base_n.png'), same(base));
      expect(reads, before, reason: 'nothing kept is read again');

      expect(library.fileOf('gone.material2d.json'), isNull, reason: 'gone');
      await _settle();
      expect(reads, before + 1, reason: 'asked for again, read again');
      expect(library.fileOf('gone.material2d.json'), isNotNull);
    });
  });

  test("an engine's library is on its context, made once", () {
    final context = EngineContext();
    final library = context.material2DLibrary;
    expect(context.material2DLibrary, same(library));
    expect(EngineContext().material2DLibrary, isNot(same(library)));
    context.material2DText = (path) async => '{"tint": {}}';
    expect(library.fileOf('x.material2d.json'), isNull, reason: 'being read');
  });
}
