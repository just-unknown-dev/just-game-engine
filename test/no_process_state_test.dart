// Guards against process-wide mutable state in the engine.
//
// Everything an engine knows lives in its EngineContext; everything a world
// knows, in the World. A static field that is not const — or a top-level
// variable, which is the same thing — is shared by every engine and every
// test in the process: the way one test's registration used to leak into
// the next, and one engine's loader into another. This test finds every
// such field under lib/ and fails on any that is not on the list below,
// each with the reason it is safe.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `path:field` → why it may be static.
const Map<String, String> _allowed = {
  // Immutable data: constants computed once, read-only tables, frozen
  // registries holding only the engine's own entries.
  'ecs/tag_component.dart:_valid': 'a RegExp',
  'ecs/serialization/tag_library.dart:empty': 'an empty, immutable library',
  'physics/physics_layers.dart:defaults': 'the default layers; immutable',
  'animation/animator_bindings.dart:builtIn': 'frozen registry',
  'animation/animator_bindings.dart:_engine':
      "the engine's own bindings; private, never written",
  'effects/networking/effect_serializer.dart:builtIn': 'frozen registry',
  'effects/networking/effect_serializer.dart:_engine':
      "the engine's own decoders; private, never written",
  'level_map/collision/map_collision_kinds.dart:builtIn': 'frozen registry',
  'timeline/timeline_keys.dart:builtIn': 'frozen registry',
  'timeline/timeline_keys.dart:empty': 'an empty, immutable curve',
  'timeline/timeline_track.dart:builtIn': 'frozen registry',
  'timeline/timeline_track.dart:_engine':
      "the engine's own track readers; private, never written",
  'level_map/built_in_tilesets.dart:_shapes': 'a constant table',
  'graphics/graphics_2d/materials/material_2d_overrides_field_type.dart:_channels':
      "a constant table computed once from the effects' list; unmodifiable",
  'level_map/wang/wang_template.dart:_blobMasks': 'a constant table',
  'graphics/graphics_2d/shape_batch.dart:_circle16': 'a constant table',
  'graphics/graphics_2d/shape_batch.dart:_circle24': 'a constant table',
  'camera/camera_stage.dart:_ln100': 'a constant',

  // Slot keys: an identity each feature keeps its per-engine state under
  // (EngineContext.slot); never written.
  'animation/animation_context.dart:_key': 'a slot key',
  'level_map/level_map_context.dart:_key': 'a slot key',
  'graphics/graphics_2d/materials/materials_2d_context.dart:_key': 'a slot key',
  'physics/physics_context.dart:_key': 'a slot key',
  'scenes/prefabs_context.dart:_key': 'a slot key',
  'sprites/sprites_context.dart:_key': 'a slot key',
  'timeline/timeline_context.dart:_key': 'a slot key',

  // Scratch space for single-threaded math: overwritten before every read.
  'ecs/transform/euler_rotation.dart:_scratch': 'scratch',
  'ecs/transform/transform_component.dart:_scratch': 'scratch',
  'ecs/transform/transform_component.dart:_scratchTurn': 'scratch',
  'ecs/transform/hierarchy_math.dart:_qa': 'scratch',
  'ecs/transform/hierarchy_math.dart:_qb': 'scratch',
  'ecs/transform/hierarchy_math.dart:_v': 'scratch',
  'camera/output_camera.dart:_zero': 'a constant vector',
  'camera/output_camera.dart:_one': 'a constant vector',

  // Paints for debug outlines: configured once, never changed.
  'gameplay/checkpoint_system.dart:_inactivePaint': 'paint',
  'gameplay/checkpoint_system.dart:_activatedPaint': 'paint',

  // Caches keyed by object identity or type, invisible from outside.
  'ecs/world.dart:_zobristKeys':
      'per-Type query hash keys: which key a type gets varies with order, '
      'what a query returns does not',
  'ecs/world.dart:_zodRng': "the zobrist keys' seeded source",
  'sprites/atlas/atlas_animation_clip.dart:_timings':
      'an Expando: per-clip timings, weakly held',

  // The renderer is the process's: whether it can filter with shaders is a
  // fact about the process, and its warning is said once per process.
  'rendering/shader_filter_support.dart:debugSupportedOverride':
      'test seam for a platform capability',
  'rendering/shader_filter_support.dart:_warned':
      'log-once for a platform capability',

  // Top-level finals.
  'effects/effects_context.dart:_effectTypesKey': 'a slot key',
  'localization/localization_context.dart:_localizationKey': 'a slot key',
  'narrative/parser/yarn_parser.dart:_optionCondition': 'a RegExp',
  'narrative/parser/yarn_parser.dart:_assignment': 'a RegExp',
  'narrative/parser/yarn_parser.dart:_declaredType': 'a RegExp',
  'narrative/parser/yarn_parser.dart:_escape': 'a RegExp',
  'narrative/runtime/dialogue_command_registry.dart:_argument': 'a RegExp',
  'narrative/runtime/dialogue_runner.dart:_stringLiteral': 'a RegExp',
  'narrative/runtime/dialogue_runner.dart:_variableOnly': 'a RegExp',
  'narrative/runtime/expression_evaluator.dart:_number': 'a RegExp',
  'narrative/runtime/expression_evaluator.dart:_identChar': 'a RegExp',
};

/// Every `static` field under lib/src that is not `const`, and every
/// top-level variable, as `path:name`.
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
      final m =
          RegExp(
            r'^(?:@\w+(?:\([^)]*\))?\s+)*static\s+(.*)$',
          ).firstMatch(line) ??
          _topLevel(lines[i]);
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

/// [line] as a top-level declaration that may be a variable — at column 0,
/// not a directive, a type, an extension, a comment or a closing brace —
/// with the declaration in group 1; null otherwise.
RegExpMatch? _topLevel(String line) {
  if (line.isEmpty || line.startsWith(RegExp(r'[\s/}*@)\]]'))) return null;
  if (RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
    r'(?:class|mixin|enum|extension|typedef|import|export|part|library)\b',
  ).hasMatch(line)) {
    return null;
  }
  return RegExp(r'^(.*)$').firstMatch(line);
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
    expect(_fieldName('FieldDefinition _d<T extends Component>('), isNull);
    expect(_fieldName('(double, double)? _bounds(Map m) {'), isNull);
    expect(_fieldName('bool isVirtual(String path) =>'), isNull);
    expect(_fieldName('Vector3 get up => Vector3(0, 1, 0);'), isNull);
    expect(_fieldName('void join(String a, {String b = ""}) {'), isNull);
  });

  test('the scanner finds top-level variables, not types or functions', () {
    String? top(String line) {
      final m = _topLevel(line);
      return m == null ? null : _fieldName(m.group(1)!);
    }

    expect(top('var _count = 0;'), '_count');
    expect(top('late Engine _engine;'), '_engine');
    expect(top('final _cache = <String, int>{};'), '_cache');
    expect(top('final RegExp _id = RegExp(r"x");'), '_id');
    expect(top('const int limit = 3;'), isNull);
    expect(top('final class Foo {'), isNull);
    expect(top('abstract final class Foo {'), isNull);
    expect(top('typedef Load = Future<void> Function();'), isNull);
    expect(top('extension Tags on Entity {'), isNull);
    expect(top('void main() {'), isNull);
    expect(top('int get answer => 42;'), isNull);
    expect(top('  final indented = 1;'), isNull);
  });
}
