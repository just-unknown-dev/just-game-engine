// Keeps 3-D physics out of 2-D games. Everything 3-D lives under
// lib/src/physics_3d/ and is reached only through a Physics3D a game gives
// the engine (EngineConfig.physics3D). A 2-D game never makes one, so the
// compiler drops all of it, along with just_physics_engine's Jolt engine and
// just_jolt's bindings. That holds only while nothing else in the engine
// names the 3-D code; this test fails when something does.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files outside the folder that may import it, and what they may take.
const Map<String, String> _seams = {
  'lib/src/core/engine_config.dart': 'EngineConfig.physics3D names the type',
  'lib/src/core/engine.dart': 'installs and starts it, and Engine.physics3D returns it',
};

/// Code (not comments) outside the folder must not call these: each one
/// reaches the 3-D engine or its native library without a Physics3D.
const List<String> _forbiddenCalls = [
  'create3D(',
  'JoltPhysicsEngine(',
  'Physics3DSchemas.',
  'PhysicsSystem3D(',
  'PhysicsSystem3D.lazy(',
];

String _path(FileSystemEntity f) => f.path.replaceAll(r'\', '/');

Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !_path(f).contains('lib/src/physics_3d/'))
    // The 3-D library itself, which a 3-D game imports.
    .where((f) => !_path(f).endsWith('lib/physics_3d.dart'));

final RegExp _directive = RegExp(r"^\s*(import|export)\s+'([^']+)'([^;]*);", multiLine: true);

bool _reaches3D(String uri) =>
    uri == 'package:just_game_engine/physics_3d.dart' ||
    uri.contains('physics_3d/') && !uri.startsWith('package:just_physics_engine/');

void main() {
  test('only the config seams import the 3-D folder, and only Physics3D', () {
    final offenders = <String>[];
    for (final file in _libFiles()) {
      final path = _path(file);
      final rel = path.substring(path.indexOf('lib/'));
      for (final m in _directive.allMatches(file.readAsStringSync())) {
        final uri = m.group(2)!;
        if (!_reaches3D(uri)) continue;
        final combinators = m.group(3)!.trim();
        if (_seams.containsKey(rel) && m.group(1) == 'import' && combinators == 'show Physics3D') continue;
        offenders.add('$rel: ${m.group(0)!.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'only ${_seams.keys.join(', ')} may import the 3-D folder, as `show Physics3D`');
  });

  test('the main library leaves 3-D to package:just_game_engine/physics_3d.dart', () {
    final main = File('lib/just_game_engine.dart').readAsStringSync();
    for (final m in _directive.allMatches(main)) {
      expect(_reaches3D(m.group(2)!), isFalse, reason: m.group(0));
    }
  });

  test('no code outside the folder calls into 3-D physics', () {
    final offenders = <String>[];
    for (final file in _libFiles()) {
      final path = _path(file);
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trimLeft();
        if (code.startsWith('//')) continue;
        for (final call in _forbiddenCalls) {
          if (code.contains(call)) offenders.add('${path.substring(path.indexOf('lib/'))}:${i + 1}: $call');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the seams are still there (or this test needs updating)', () {
    for (final path in _seams.keys) {
      expect(File(path).readAsStringSync(), contains('Physics3D'), reason: path);
    }
  });
}
