// ScreenPassPlan: where layers can be filtered, the last screen passes that
// can be filters are layers around the drawing — nothing made of what they
// filter — and only the passes before them draw from images of the frame.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Pass implements ScreenPass {
  _Pass(this.name, this.log, {this.filters = false});

  final String name;
  final List<String> log;
  final bool filters;
  late final ui.ImageFilter own = ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1);

  @override
  bool get active => true;

  @override
  void paint(Canvas canvas, ui.Image frame, Size size, double pixelRatio) =>
      log.add('$name from ${frame.width}x${frame.height}');

  @override
  ui.ImageFilter? filter(Size size, double pixelRatio) => filters ? own : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = Size(10, 8);
  final log = <String>[];
  late _Pass light, grey, vignette;
  setUp(() {
    log.clear();
    light = _Pass('light', log);
    grey = _Pass('grey', log, filters: true);
    vignette = _Pass('vignette', log, filters: true);
  });

  test('the last passes that can filter are layers; the rest, images', () {
    var plan = ScreenPassPlan.of(
      [light, grey, vignette],
      size,
      1,
      filterLayers: true,
    );
    expect(plan.imagePasses, [light]);
    expect(plan.layers, [same(grey.own), same(vignette.own)]);
    expect(plan.needsImage, isTrue);

    plan = ScreenPassPlan.of([grey, light], size, 1, filterLayers: true);
    expect(plan.imagePasses, [
      grey,
      light,
    ], reason: 'one drawing from what an image pass drew is not a layer');
    expect(plan.layers, isEmpty);

    plan = ScreenPassPlan.of([grey, vignette], size, 1, filterLayers: true);
    expect(plan.needsImage, isFalse, reason: 'no image of the frame at all');

    plan = ScreenPassPlan.of([light, grey], size, 1, filterLayers: false);
    expect(plan.imagePasses, [
      light,
      grey,
    ], reason: 'where layers cannot be filtered: every pass from images');
    expect(plan.layers, isEmpty);
  });

  test('layers open around the drawing, the last pass outermost', () {
    final plan = ScreenPassPlan.of(
      [grey, vignette],
      size,
      1,
      filterLayers: true,
    );
    final canvas = TestRecordingCanvas();
    plan.begin(canvas, size);
    canvas.drawRect(Offset.zero & size, Paint());
    plan.end(canvas);
    final calls = [for (final i in canvas.invocations) i.invocation.memberName];
    expect(calls, [#saveLayer, #saveLayer, #drawRect, #restore, #restore]);
    final filters = [
      for (final i in canvas.invocations)
        if (i.invocation.memberName == #saveLayer)
          (i.invocation.positionalArguments[1] as Paint).imageFilter,
    ];
    expect(filters, [same(vignette.own), same(grey.own)]);
  });

  test('image passes draw in turn, each from the one before', () {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Offset.zero & size, Paint());
    final picture = recorder.endRecording();
    final frame = picture.toImageSync(20, 16);
    picture.dispose();
    final kept = <ui.Image>[];
    final dark = _Pass('dark', log);
    ScreenPassPlan.of(
      [light, dark],
      size,
      2,
      filterLayers: true,
    ).paintImages(TestRecordingCanvas(), frame, size, 2, keep: kept.add);
    expect(log, ['light from 20x16', 'dark from 20x16']);
    expect(kept, hasLength(1), reason: "light's drawing, for dark");
    for (final i in [frame, ...kept]) {
      i.dispose();
    }
  });
}
