// The rendering contracts use the output camera, so the output camera and
// what it is made of must import nothing from the rest of the camera
// feature (the brain, the stages): that would loop rendering and camera.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The camera files the rendering contracts reach, and so may only import
/// each other, `interfaces/` and `foundation/`.
const _lowFiles = [
  'output_camera.dart',
  'camera_state.dart',
  'camera_effects.dart',
];

void main() {
  test('the output camera imports only interfaces/, foundation/ and its own '
      'state and effects', () {
    final import = RegExp(r'''^import\s+'([^']+)'(?:\s|;)''', multiLine: true);
    for (final name in _lowFiles) {
      final source = File('lib/src/camera/$name').readAsStringSync();
      for (final match in import.allMatches(source)) {
        final path = match.group(1)!;
        if (path.startsWith('package:') || path.startsWith('dart:')) {
          expect(
            path,
            isNot(startsWith('package:just_game_engine/')),
            reason: '$name imports the engine library',
          );
          continue;
        }
        final ok =
            _lowFiles.contains(path) ||
            path.startsWith('../interfaces/') ||
            path.startsWith('../foundation/');
        expect(ok, isTrue, reason: '$name imports $path');
      }
    }
  });
}
