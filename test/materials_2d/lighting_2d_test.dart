// 2-D lighting: a scene with Lighting2D on is drawn, then lit by its
// Light2Ds over the ambient light — shaded by the normal maps sprites'
// materials name, turned as the sprites are; emissive ones glowing in the
// dark; what is drawn over a shaded sprite hiding its normals — through the
// real shaders, pixel by pixel.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _bumpy = 'bumpy.material2d.json';
const _glow = 'glow.material2d.json';
const _grey = 'grey.material2d.json';
const _halves = 'halves.material2d.json';

final _files = {
  _bumpy: jsonEncode({
    'normalMap': {'map': 'right.png'},
  }),
  _glow: jsonEncode({
    'emissive': {'amount': 1},
  }),
  _grey: jsonEncode({
    'kind': 'screen',
    'greyscale': {'amount': 1},
  }),
  _halves: jsonEncode({
    'normalMap': {'map': 'halves.png'},
  }),
};

// An 8 × 8 normal map: its left half faces right (+x), its right half left.
Future<ui.Image> _halvesMap() {
  final r = ui.PictureRecorder();
  Canvas(r)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 4, 8),
      Paint()..color = const Color(0xFFFF8080),
    )
    ..drawRect(
      const Rect.fromLTWH(4, 0, 4, 8),
      Paint()..color = const Color(0xFF008080),
    );
  final p = r.endRecording();
  return p.toImage(8, 8).whenComplete(p.dispose);
}

// 16 × 16, white over its top [opaqueRows] rows, clear below.
Future<ui.Image> _big({int opaqueRows = 16}) {
  final r = ui.PictureRecorder();
  Canvas(r).drawRect(
    Rect.fromLTWH(0, 0, 16, opaqueRows.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final p = r.endRecording();
  return p.toImage(16, 16).whenComplete(p.dispose);
}

Future<ui.Image> _solid(int w, int h, Color c) {
  final r = ui.PictureRecorder();
  Canvas(r).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = c,
  );
  final p = r.endRecording();
  return p.toImage(w, h).whenComplete(p.dispose);
}

class _Images extends SpriteAssetLoader {
  _Images(this.images);
  final Map<String, ui.Image> images;

  @override
  Future<ui.Image> loadImage(String path) async =>
      images[path] ?? (throw StateError('no $path'));

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late ui.Image white;
  late ui.Image facingRight;
  late ui.Image halves;

  setUpAll(() async {
    white = await _solid(8, 8, const Color(0xFFFFFFFF));
    // A normal map whose every normal faces right: (1, 0, 0).
    facingRight = await _solid(8, 8, const Color(0xFFFF8080));
    halves = await _halvesMap();
  });

  setUp(() async {
    engine = Engine(
      config: const EngineConfig(defaultSystems: DefaultSystems.all),
    );
    await engine.initialize();
    engine.context.material2DText = (path) async =>
        _files[path] ?? (throw StateError('no $path'));
    engine.context.sprites = _Images({
      'right.png': facingRight,
      'halves.png': halves,
    });
    engine.rendering
      ..backgroundColor = const Color(0xFFFFFFFF)
      ..pixelRatio = 1
      ..overlayHooks.add(engine.world.render);
    // World points are view pixels: the camera looks at the view's middle.
    engine.rendering.camera.position = const Offset(20, 15);
    final library = Material2DLibrary.of(engine.context);
    for (var i = 0; i < 300; i++) {
      for (final p in _files.keys) {
        library.fileOf(p);
      }
      library.imageOf('right.png');
      library.imageOf('halves.png');
      library.shadowsProgram;
      library.screenProgram;
      if (library.lightingProgram != null &&
          library.shadowsProgram != null &&
          library.screenProgram != null &&
          library.normalsProgram != null &&
          library.program != null &&
          library.imageOf('right.png') != null &&
          library.imageOf('halves.png') != null &&
          _files.keys.every((p) => library.fileOf(p) != null)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(library.lightingProgram, isNotNull);
  });
  tearDown(() => engine.dispose());

  Future<ByteData> frame() async {
    final recorder = ui.PictureRecorder();
    engine.rendering.render(Canvas(recorder), const Size(40, 30));
    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 30);
    final data = (await image.toByteData())!;
    picture.dispose();
    image.dispose();
    return data;
  }

  (int, int, int) at(ByteData d, int x, int y) {
    final i = (y * 40 + x) * 4;
    return (d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2));
  }

  void lighting({
    Color ambient = const Color(0xFF000000),
    bool enabled = true,
  }) => engine.world.createEntityWithComponents([
    Lighting2D(ambient: ambient, enabled: enabled),
  ]);

  Entity light(
    Offset at, {
    Color colour = const Color(0xFFFF0000),
    double radius = 30,
    double height = 48,
    Light2DKind kind = Light2DKind.point,
    double angle = 0,
  }) => engine.world.createEntityWithComponents([
    TransformComponent(position: Vector3(at.dx, at.dy, 0), angle: angle),
    Light2D(
      kind: kind,
      colour: colour,
      radius: radius,
      height: height,
      falloff: 1,
    ),
  ]);

  Entity sprite(Offset at, {String? material, double angle = 0, int z = 0}) =>
      engine.world.createEntityWithComponents([
        TransformComponent(position: Vector3(at.dx, at.dy, 0), angle: angle),
        RenderableComponent(renderable: Sprite(image: white)),
        LayerComponent(zOrder: z),
        if (material != null) Material2D(material: material),
      ]);

  test('a dark scene, lit where its light reaches', () async {
    lighting();
    light(const Offset(20, 15));
    final d = await frame();
    final (r, g, b) = at(d, 20, 15);
    expect(r, greaterThan(240), reason: 'red at the light');
    expect(g + b, 0);
    expect(
      at(d, 32, 15).$1,
      inInclusiveRange(80, 200),
      reason: 'fading towards its radius',
    );
    expect(
      at(d, 0, 0).$1,
      lessThan(60),
      reason: 'near its edge: a sixth of the way in',
    );
  });

  test('with lighting off, drawn as it is', () async {
    lighting(enabled: false);
    light(const Offset(20, 15));
    final d = await frame();
    expect(at(d, 3, 3), (255, 255, 255));
  });

  test('a normal map turns the light; turned with its sprite', () async {
    lighting();
    final s = sprite(const Offset(20, 15), material: _bumpy);
    final l = light(
      const Offset(34, 15),
      colour: const Color(0xFFFFFFFF),
      height: 2,
    );
    var d = await frame();
    expect(
      at(d, 20, 15).$1,
      greaterThan(100),
      reason: 'facing the light on its right',
    );

    l.getComponent<TransformComponent>()!.position.setValues(6, 15, 0);
    d = await frame();
    expect(
      at(d, 20, 15).$1,
      lessThan(20),
      reason: 'facing away from it, on its left',
    );

    s.getComponent<TransformComponent>()!.angle = math.pi;
    d = await frame();
    expect(
      at(d, 20, 15).$1,
      greaterThan(100),
      reason: 'turned round, facing it again',
    );
  });

  group('a normal map smaller than its sprite', () {
    // A 16-px sprite at (20, 15): view x 12-28, its own x = view x - 12.
    Entity bigSprite(ui.Image image) =>
        engine.world.createEntityWithComponents([
          TransformComponent(position: Vector3(20, 15, 0)),
          RenderableComponent(renderable: Sprite(image: image)),
          Material2D(material: _halves),
        ]);

    test('repeats across it', () async {
      lighting();
      bigSprite(await _big());
      light(
        const Offset(38, 15),
        colour: const Color(0xFFFFFFFF),
        radius: 60,
        height: 2,
      );
      final d = await frame();
      expect(at(d, 13, 15).$1, greaterThan(80), reason: 'faces the light');
      expect(at(d, 17, 15).$1, lessThan(20), reason: 'faces away');
      expect(
        at(d, 21, 15).$1,
        greaterThan(80),
        reason:
            'the map again, past its edge: it used to streak its last '
            'column, facing away',
      );
      expect(at(d, 25, 15).$1, lessThan(20));
    });

    test("shades only the sprite's own shape", () async {
      lighting();
      bigSprite(await _big(opaqueRows: 8));
      light(
        const Offset(20, 15),
        colour: const Color(0xFFFFFFFF),
        radius: 60,
        height: 8,
      );
      final d = await frame();
      expect(
        at(d, 17, 11).$1,
        lessThan(30),
        reason: 'on the sprite, facing away from the light above its middle',
      );
      expect(
        at(d, 17, 20).$1,
        greaterThan(100),
        reason: 'below it, where it is clear: flat, lit from above',
      );
    });
  });

  test('emissive glows in the dark; plain stays dark', () async {
    lighting();
    sprite(const Offset(10, 15), material: _glow);
    sprite(const Offset(30, 15));
    final d = await frame();
    expect(at(d, 10, 15), (255, 255, 255));
    expect(at(d, 30, 15), (0, 0, 0));
  });

  test('a plain sprite over a shaded one hides its normals', () async {
    lighting();
    sprite(const Offset(20, 15), material: _bumpy, z: 0);
    sprite(const Offset(20, 15), z: 1);
    light(const Offset(6, 15), colour: const Color(0xFFFFFFFF), height: 8);
    final d = await frame();
    expect(
      at(d, 20, 15).$1,
      greaterThan(40),
      reason:
          'flat, so lit from the side a little; facing away it would be black',
    );
  });

  // Where layers can be filtered (Impeller) the screen material is a layer
  // the lighting draws into; elsewhere it draws from an image of it.
  test('under a screen material, the lit frame is what it draws', () async {
    lighting();
    light(const Offset(20, 15));
    engine.world.createEntityWithComponents([ScreenMaterial(material: _grey)]);
    final d = await frame();
    final (r, g, b) = at(d, 20, 15);
    expect(r, closeTo(76, 4), reason: 'the red light, as grey');
    expect([g, b], [closeTo(r, 2), closeTo(r, 2)]);
    expect(
      at(d, 0, 0).$1,
      lessThan(30),
      reason: 'dark where it does not reach',
    );
  });

  test('a spot shines along its turn', () async {
    lighting();
    light(const Offset(20, 15), kind: Light2DKind.spot, radius: 40);
    final d = await frame();
    expect(at(d, 30, 15).$1, greaterThan(60), reason: 'ahead of it (right)');
    expect(at(d, 10, 15).$1, lessThan(10), reason: 'behind it');
  });

  group('shadows', () {
    Entity box({bool caster = true}) =>
        engine.world.createEntityWithComponents([
          TransformComponent(position: Vector3(20, 15, 0)),
          RectangleComponent(width: 2, height: 4),
          if (caster) ShadowCaster2D(),
        ]);

    test('behind what casts them, from the light', () async {
      lighting();
      box();
      light(const Offset(5, 15), radius: 40, height: 8);
      final d = await frame();
      expect(at(d, 30, 15).$1, lessThan(8), reason: 'behind the box');
      expect(at(d, 30, 3).$1, greaterThan(12), reason: 'clear of its shadow');
      expect(at(d, 12, 15).$1, greaterThan(100), reason: 'in front of it');
      expect(
        at(d, 20, 15).$1,
        greaterThan(40),
        reason: 'the box itself, lit its depth in',
      );
      final pass = engine.rendering.screenPasses
          .whereType<Lighting2DPass>()
          .single;
      expect(pass.lastHadShadows, isTrue);
    });

    test(
      'none from a light that casts none, or from what does not cast them',
      () async {
        lighting();
        box();
        final l = light(const Offset(5, 15), radius: 40, height: 8);
        l.getComponent<Light2D>()!.castsShadows = false;
        var d = await frame();
        expect(at(d, 30, 15).$1, greaterThan(12));

        l.getComponent<Light2D>()!.castsShadows = true;
        for (final e in engine.world.query(const [ShadowCaster2D])) {
          e.getComponent<ShadowCaster2D>()!.enabled = false;
        }
        d = await frame();
        expect(at(d, 30, 15).$1, greaterThan(12));
        final pass = engine.rendering.screenPasses
            .whereType<Lighting2DPass>()
            .single;
        expect(pass.lastHadShadows, isFalse, reason: 'nothing to cast them');
      },
    );

    test('casters and shadow-casting layers are saved', () {
      final definitions = engine.context.definitions;
      final back =
          definitions.decode(
                jsonDecode(
                      jsonEncode(
                        definitions.encode(
                          ShadowCaster2D(depth: 3, enabled: false),
                        ),
                      ),
                    )
                    as Map<String, dynamic>,
              )!
              as ShadowCaster2D;
      expect([back.depth, back.enabled], [3.0, false]);
      final layer = MapLayerData(id: 1, castsShadows: true, shadowDepth: 5);
      final again = MapLayerData.fromJson(layer.toJson());
      expect([again.castsShadows, again.shadowDepth], [true, 5.0]);
      expect(MapLayerData(id: 2).toJson().containsKey('castsShadows'), isFalse);
    });
  });

  // Every layer and every image is a render target of its own, and a GPU
  // has only so much room: Impeller on OpenGL ES aborts when one cannot be
  // made. A cave of eighty casters crashed the editor that way.
  group('few render targets a frame', () {
    const size = Size(40, 30);
    RenderSystem render() => engine.world.getSystem<RenderSystem>()!;
    int layers(void Function(Canvas canvas) draw) {
      final canvas = TestRecordingCanvas();
      draw(canvas);
      return canvas.invocations
          .where((i) => i.invocation.memberName == #saveLayer)
          .length;
    }

    test('casters of one depth share a layer', () async {
      lighting();
      for (var i = 0; i < 8; i++) {
        engine.world.createEntityWithComponents([
          TransformComponent(position: Vector3(4.0 + i * 4, 15, 0)),
          RectangleComponent(width: 2, height: 4),
          ShadowCaster2D(depth: i < 5 ? 1 : 2),
        ]);
      }
      light(const Offset(20, 3), radius: 40, height: 8);
      await frame();
      var cast = false;
      expect(
        layers((c) => cast = render().renderOccluders(c, size)),
        2,
        reason: 'one a depth, not one a caster',
      );
      expect(cast, isTrue);
    });

    test('flat things over shaded ones share a layer', () async {
      lighting();
      for (var i = 0; i < 6; i++) {
        sprite(Offset(4.0 + i * 6, 15), z: 1);
      }
      await frame();
      var shaded = true;
      expect(layers((c) => shaded = render().renderNormals(c, size)), 0);
      expect(shaded, isFalse, reason: 'nothing shaded: no normals image');

      sprite(const Offset(20, 15), material: _bumpy);
      await frame();
      expect(
        layers((c) => shaded = render().renderNormals(c, size)),
        1,
        reason: 'one for the six, not one each',
      );
      expect(shaded, isTrue);
    });
  });

  test('Light2D and Lighting2D are saved with their entities', () {
    final definitions = engine.context.definitions;
    T back<T>(Component c) =>
        definitions.decode(
              jsonDecode(jsonEncode(definitions.encode(c)))
                  as Map<String, dynamic>,
            )!
            as T;
    final l = back<Light2D>(
      Light2D(
        kind: Light2DKind.spot,
        colour: const Color(0xFF00FF00),
        radius: 99,
        coneAngle: 30,
        castsShadows: false,
      ),
    );
    expect(
      [l.kind, l.colour, l.radius, l.coneAngle, l.castsShadows],
      [Light2DKind.spot, const Color(0xFF00FF00), 99.0, 30.0, false],
    );
    final g = back<Lighting2D>(
      Lighting2D(
        ambient: const Color(0xFF102030),
        ambientIntensity: 0.5,
        enabled: false,
      ),
    );
    expect(
      [g.ambient, g.ambientIntensity, g.enabled],
      [const Color(0xFF102030), 0.5, false],
    );
  });
}
