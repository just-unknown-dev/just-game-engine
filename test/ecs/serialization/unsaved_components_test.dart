// Every component class under lib/src either has a definition — a saved
// type name — or is listed here with why it is never saved. A new component
// with neither is a component a scene cannot hold: an editor save drops it
// silently.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Component classes with no definition, and why.
const Map<String, String> _unsaved = {
  'CullStateComponent': 'runtime state the culling system adds and removes',
  'GeneratedEntityComponent': 'marks what a system generated, never saved',
  'MapBodyComponent': 'a collision body the level map generates',
  'PhysicsBodyRefComponent': 'the live physics body handle',
  'PrefabInstanceComponent': "saved as the entry's prefab block",
  'PrefabLinkComponent': "saved as the entry's prefab block",
  'RenderableComponent': 'holds a renderable built in code',
  'RenderItemsComponent': 'holds renderables built in code',
  'ShaderComponent': 'holds a shader made at run time',
  'ParallaxComponent': 'holds a background built in code',
  'ParticleEmitterComponent': 'holds an emitter built in code',
  'RaycastColliderComponent': 'set up from code',
  'DialogueComponent': 'set up from code; no definition yet',
  'DialogueTriggerComponent': 'set up from code; no definition yet',
  'NavigationObstacleComponent': 'set up from code; no definition yet',
};

void main() {
  test('every component class has a definition or a reason', () {
    final classes = <String, String>{};
    final saved = <String>{};
    final classPattern = RegExp(
      r'^(?:(?:base|final|sealed|interface)\s+)*class\s+([A-Za-z]\w*Component)\b',
      multiLine: true,
    );
    final typePattern = RegExp(r"type:\s*'(\w+)'");
    for (final file in Directory('lib/src').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final m in classPattern.allMatches(source)) {
        classes[m.group(1)!] = file.path;
      }
      saved.addAll(typePattern.allMatches(source).map((m) => m.group(1)!));
    }
    expect(classes, isNotEmpty);
    final unexplained = [
      for (final MapEntry(key: name, value: path) in classes.entries)
        if (!saved.contains(name) && !_unsaved.containsKey(name))
          '$name ($path)',
    ];
    expect(
      unexplained,
      isEmpty,
      reason:
          'Give the component a definition (a ComponentDefinition in its '
          "feature's …Definitions), or list it here with why it is never "
          'saved.',
    );
    expect(
      [
        for (final name in _unsaved.keys)
          if (!classes.containsKey(name) || saved.contains(name)) name,
      ],
      isEmpty,
      reason: 'take a component off the list once it is gone or saved',
    );
  });
}
