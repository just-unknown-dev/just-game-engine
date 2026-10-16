// The engine reaches Flutter GPU only through just_graphics_engine's public
// libraries, whose web branch carries none of it (that package's own
// import_boundary_test checks), so the engine stays web-safe. And the 3-D
// code is reached only through Graphics3D.
@Tags(['graphics3d'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _directive = RegExp(
  r"""^\s*(?:import|export)\s+'([^']+)'""",
  multiLine: true,
);

Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('no engine file imports flutter_gpu itself', () {
    for (final f in _libFiles()) {
      for (final m in _directive.allMatches(f.readAsStringSync())) {
        expect(
          m.group(1)!.startsWith('package:flutter_gpu'),
          isFalse,
          reason: '${f.path} imports ${m.group(1)}',
        );
      }
    }
  });

  test('just_graphics_engine comes in through its public libraries', () {
    const public = {
      'package:just_graphics_engine/just_graphics_engine.dart',
      'package:just_graphics_engine/gpu.dart',
      'package:just_graphics_engine/assets.dart',
      'package:just_graphics_engine/renderer.dart',
    };
    final users = <String>{};
    for (final f in _libFiles()) {
      for (final m in _directive.allMatches(f.readAsStringSync())) {
        final u = m.group(1)!;
        if (!u.startsWith('package:just_graphics_engine/')) continue;
        expect(public, contains(u), reason: '${f.path} imports $u');
        users.add(f.path.replaceAll(r'\', '/'));
      }
    }
    // Only the 3-D graphics code and its library use it.
    for (final path in users) {
      expect(
        path.startsWith('lib/src/graphics_3d/') ||
            path == 'lib/graphics_3d.dart',
        isTrue,
        reason: path,
      );
    }
  });
}
