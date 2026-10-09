// Guards against process-wide mutable state in the engine.
//
// Everything an engine knows lives in its EngineContext; everything a world
// knows, in the World. A static field that is not const is shared by every
// engine and every test in the process — the way one test's registration
// used to leak into the next, and one engine's loader into another. This
// test finds every such field under lib/ and fails on any that is not on
// the list below, each with the reason it is safe.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `path:field` → why it may be static.
const Map<String, String> _allowed = {
  // Immutable data: constants computed once, read-only tables, frozen
  // registries holding only the engine's own entries.
  'ecs/base/tags.dart:_valid': 'a RegExp',
  'ecs/serialization/tag_library.dart:empty': 'an empty, immutable library',
  'subsystems/physics/physics_layers.dart:defaults':
      'the default layers; immutable',
  'ecs/components/animation/animator_bindings.dart:builtIn': 'frozen registry',
  'ecs/components/animation/animator_bindings.dart:_engine':
      "the engine's own bindings; private, never written",
  'subsystems/effects/networking/effect_serializer.dart:builtIn':
      'frozen registry',
  'subsystems/effects/networking/effect_serializer.dart:_engine':
      "the engine's own decoders; private, never written",
  'subsystems/level_map/collision/map_collision_kinds.dart:builtIn':
      'frozen registry',
  'subsystems/timeline/timeline_keys.dart:builtIn': 'frozen registry',
  'subsystems/timeline/timeline_keys.dart:empty': 'an empty, immutable curve',
  'subsystems/timeline/timeline_track.dart:builtIn': 'frozen registry',
  'subsystems/timeline/timeline_track.dart:_engine':
      "the engine's own track readers; private, never written",
  'subsystems/level_map/built_in_tilesets.dart:_shapes': 'a constant table',
  'subsystems/level_map/wang/wang_templates.dart:_blobMasks':
      'a constant table',
  'ecs/systems/rendering/shape_batch.dart:_circle16': 'a constant table',
  'ecs/systems/rendering/shape_batch.dart:_circle24': 'a constant table',
  'ecs/systems/camera/camera_stage.dart:_ln100': 'a constant',

  // Scratch space for single-threaded math: overwritten before every read.
  'ecs/base/transform/euler_rotation.dart:_scratch': 'scratch',
  'ecs/base/transform/transform_component.dart:_scratch': 'scratch',
  'ecs/base/transform/hierarchy_math.dart:_qa': 'scratch',
  'ecs/base/transform/hierarchy_math.dart:_qb': 'scratch',
  'ecs/base/transform/hierarchy_math.dart:_v': 'scratch',
  'subsystems/camera/camera_system.dart:_zero': 'a constant vector',
  'subsystems/camera/camera_system.dart:_one': 'a constant vector',

  // Paints for debug outlines: configured once, never changed.
  'ecs/systems/gameplay/checkpoint_system.dart:_inactivePaint': 'paint',
  'ecs/systems/gameplay/checkpoint_system.dart:_activatedPaint': 'paint',
  'ecs/systems/physics/physics_system.dart:_debugStaticPaint': 'paint',
  'ecs/systems/physics/physics_system.dart:_debugDynamicPaint': 'paint',
  'ecs/systems/physics/physics_system.dart:_debugSensorPaint': 'paint',
  'ecs/systems/physics/physics_system.dart:_debugKinematicPaint': 'paint',
  'ecs/systems/physics/physics_system.dart:_debugSleepingPaint': 'paint',

  // Caches keyed by object identity or type, invisible from outside.
  'ecs/base/world.dart:_zobristKeys':
      'per-Type query hash keys: which key a type gets varies with order, '
      'what a query returns does not',
  'ecs/base/world.dart:_zodRng': "the zobrist keys' seeded source",
  'subsystems/sprite_atlas/impl/atlas_animation_clip.dart:_timings':
      'an Expando: per-clip timings, weakly held',

  // The renderer is the process's: whether it can filter with shaders is a
  // fact about the process, and its warning is said once per process.
  'subsystems/rendering/shader_filter_support.dart:debugSupportedOverride':
      'test seam for a platform capability',
  'subsystems/rendering/shader_filter_support.dart:_warned':
      'log-once for a platform capability',
};

/// Every `static` field under lib/src that is not `const`, as `path:name`.
Map<String, int> _staticFields() {
  final root = Directory('lib/src');
  final found = <String, int>{};
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final path = file.path
        .substring(root.path.length + 1)
        .replaceAll(r'\', '/');
    final lines = file.readAsLinesSync();
    var inComment = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('/*')) inComment = true;
      if (inComment) {
        if (line.contains('*/')) inComment = false;
        continue;
      }
      final m = RegExp(
        r'^(?:@\w+(?:\([^)]*\))?\s+)*static\s+(.*)$',
      ).firstMatch(line);
      if (m == null) continue;
      var decl = m.group(1)!;
      for (var j = i + 1; j < lines.length && !_ends(decl); j++) {
        decl += ' ${lines[j].trim()}';
      }
      final name = _fieldName(decl);
      if (name != null) found['$path:$name'] = i + 1;
    }
  }
  return found;
}

bool _ends(String decl) =>
    decl.contains(';') || decl.contains('=') || decl.contains('{');

/// The field [decl] declares — the text after `static` — or null when it is
/// a constant, a method, a getter or a setter.
String? _fieldName(String decl) {
  if (RegExp(r'^const\b').hasMatch(decl)) return null;
  if (RegExp(
    r'(^|\s)(get|set|operator)\s',
  ).hasMatch(decl.split(RegExp(r'[=(;{]')).first)) {
    return null;
  }
  var depth = 0; // Inside <...>.
  for (var k = 0; k < decl.length; k++) {
    final c = decl[k];
    if (c == '<') depth++;
    if (c == '>' && k > 0 && decl[k - 1] != '=') depth--;
    if (depth > 0) continue;
    if (c == '(') {
      // A parameter list follows the name (or a method's type parameters);
      // a record type or a Function type's parameters do not.
      final before = decl.substring(0, k).trimRight();
      final word = RegExp(r'(\w+)$').firstMatch(before)?.group(1);
      if (before.endsWith('>') || (word != null && word != 'Function')) {
        final head = before.endsWith('>')
            ? before
            : before.substring(0, before.length - word!.length).trimRight();
        // `Future<T> Function(...)` field types end in `Function`.
        if (!head.endsWith('Function')) return null;
      }
    }
    if (c == '=' && k + 1 < decl.length && decl[k + 1] == '>') return null;
    if (c == '=' || c == ';') {
      return RegExp(r'(\w+)\s*$').firstMatch(decl.substring(0, k))?.group(1);
    }
    if (c == '{') return null;
  }
  return null;
}

void main() {
  test('lib/ holds no process-wide mutable state', () {
    final unexpected = [
      for (final MapEntry(key: field, value: line) in _staticFields().entries)
        if (!_allowed.containsKey(field)) '$field (line $line)',
    ];
    expect(
      unexpected,
      isEmpty,
      reason:
          'A static field that is not const is shared by every engine in the '
          'process. Keep per-engine state in EngineContext (a registry, or '
          'context.slot for a package), per-world state in World; or, if it '
          'truly is immutable, add it to the list in this test with why.',
    );
  });

  test('every allowed field still exists', () {
    final fields = _staticFields();
    expect(
      [
        for (final field in _allowed.keys)
          if (!fields.containsKey(field)) field,
      ],
      isEmpty,
      reason: 'take a field off the list when it goes',
    );
  });

  test('the scanner tells fields from methods', () {
    expect(_fieldName('final Vector3 _scratch = Vector3.zero();'), '_scratch');
    expect(_fieldName('int _next = 0;'), '_next');
    expect(_fieldName('Engine? _instance;'), '_instance');
    expect(
      _fieldName(
        'Future<String> Function(String path) readText = _fromBundle;',
      ),
      'readText',
    );
    expect(
      _fieldName('final List<(String, TileShape)> _shapes = ['),
      '_shapes',
    );
    expect(_fieldName('const int current = 7;'), isNull);
    expect(_fieldName('SchemaField _d<T extends Component>('), isNull);
    expect(_fieldName('(double, double)? _bounds(Map m) {'), isNull);
    expect(_fieldName('bool isVirtual(String path) =>'), isNull);
    expect(_fieldName('Vector3 get up => Vector3(0, 1, 0);'), isNull);
    expect(_fieldName('void join(String a, {String b = ""}) {'), isNull);
  });
}
