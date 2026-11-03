// Keeps 3-D physics out of 2-D games. Everything 3-D lives under
// lib/src/physics_3d/ and is reached only through a Physics3D a game gives
// the engine (EngineConfig.services). A 2-D game never makes one, so the
// compiler drops all of it, along with just_physics_engine's Jolt engine and
// just_jolt's bindings. That holds only while nothing else in the engine
// names the 3-D code; this test fails when something does.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  test('nothing outside the folder imports it', () {
    final offenders = <String>[];
    for (final file in _libFiles()) {
      final path = _path(file);
      final rel = path.substring(path.indexOf('lib/'));
      for (final m in _directive.allMatches(file.readAsStringSync())) {
        final uri = m.group(2)!;
        if (!_reaches3D(uri)) continue;
        offenders.add('$rel: ${m.group(0)!.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'the engine reaches 3-D physics only through the Physics3D a game gives it');
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

}
