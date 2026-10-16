// The example's input asset passes the input editor's checks: a reader copying
// it gets an asset with no errors.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_inputs/just_inputs.dart' show validateAsset, IssueSeverity;

import '../example/example.dart' as example;

void main() {
  test('the example input asset is valid', () {
    final issues = validateAsset(
      InputActionAsset.parse(example.inputAsset),
    ).where((i) => i.severity == IssueSeverity.error);
    expect(issues, isEmpty);
  });
}
