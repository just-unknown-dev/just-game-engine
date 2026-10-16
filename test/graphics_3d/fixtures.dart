// Shared by the engine-glue tests: a cube model written on the fly, a bundle
// serving it, and scene JSON built through the definitions the game uses.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

/// Where [cubeGlb] is served by [TestBundle].
const cubePath = 'assets/models/cube.glb';

/// A unit cube in glTF axes (+Y up), raised so it rests on y = 0: its
/// bounds are 0..1 in Y. Coloured [rgba].
Uint8List cubeGlb({List<double> rgba = const [0.8, 0.05, 0.05, 1]}) {
  final positions = <double>[];
  final normals = <double>[];
  final indices = <int>[];
  const faces = [
    ([1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]),
    ([-1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]),
    ([0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [1.0, 0.0, 0.0]),
    ([0.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]),
    ([0.0, 0.0, 1.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]),
    ([0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]),
  ];
  for (final (n, u, v) in faces) {
    final base = positions.length ~/ 3;
    for (final (su, sv) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]) {
      for (var c = 0; c < 3; c++) {
        positions.add(0.5 * (n[c] + su * u[c] + sv * v[c]) + (c == 1 ? 0.5 : 0));
        normals.add(n[c]);
      }
    }
    indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }
  final w = GlbWriter();
  final mesh = w.addMesh([
    {
      'attributes': {
        'POSITION': w.addFloats(positions, 'VEC3', withBounds: true),
        'NORMAL': w.addFloats(normals, 'VEC3'),
      },
      'indices': w.addInts(indices, 'SCALAR', 5123, indices: true),
      'material': w.addMaterial({
        'pbrMetallicRoughness': {'baseColorFactor': rgba, 'metallicFactor': 0, 'roughnessFactor': 0.6},
      }),
    },
  ], name: 'Cube');
  w.setScene([w.addNode({'mesh': mesh})]);
  return w.toGlb();
}

/// Serves [files] by key; anything else is missing.
final class TestBundle extends CachingAssetBundle {
  /// A bundle of [files].
  TestBundle(this.files);

  /// Key → bytes.
  final Map<String, Uint8List> files;

  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw FlutterError('No asset $key');
    return ByteData.sublistView(bytes);
  }
}

/// A scene in the current format holding [entities] (name → components),
/// encoded through [context]'s definitions and sent through JSON text, as a
/// saved file would be.
Map<String, dynamic> sceneJson(
  EngineContext context,
  Map<String, List<Component>> entities,
) => jsonDecode(
  jsonEncode({
    'version': SceneFormat.current,
    'name': 'test',
    'mode': '3d',
    'entities': [
      for (final MapEntry(key: name, value: components) in entities.entries)
        {
          'name': name,
          'parentName': null,
          'components': [for (final c in components) context.definitions.encode(c)],
        },
    ],
  }),
) as Map<String, dynamic>;

/// A frame of [size] seen from [eye] looking at [target], 60° high.
FrameView frameView({
  required Vector3 eye,
  Vector3? target,
  Size size = const Size(64, 64),
}) {
  final camera = RenderView()..lookAt(eye, target ?? Vector3.zero());
  final view = FrameView()
    ..viewportSize = size
    ..isPlanar = false;
  view.view.setFrom(camera.view);
  view.projection.setPerspectiveYDown(math.pi / 3, size.width / size.height, 0.1, 100);
  view.viewProjection.setProduct(view.projection, view.view);
  view.cameraPosition.setFrom(eye);
  return view;
}
