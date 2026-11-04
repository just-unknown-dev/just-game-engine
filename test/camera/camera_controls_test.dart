// The on-screen zoom controls follow the camera's zoom whoever changes it
// — a camera brain, the game — and a camera swapped in a rebuild.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

void main() {
  Widget controls(Camera camera) => MaterialApp(
    home: GameCameraControls(
      camera: camera,
      showZoomLevel: true,
      child: const ColoredBox(color: Colors.black),
    ),
  );

  FloatingActionButton button(WidgetTester tester, String tooltip) =>
      tester.widget<FloatingActionButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(FloatingActionButton),
        ),
      );

  testWidgets('a zoom changed elsewhere enables the buttons again', (
    tester,
  ) async {
    final camera = Camera(minZoom: 0.5, maxZoom: 2);
    await tester.pumpWidget(controls(camera));
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
    }
    expect(camera.zoom, 0.5);
    expect(button(tester, 'Zoom out').onPressed, isNull);

    camera.setZoom(1); // a camera brain, say
    await tester.pump(); // the game draws a frame
    await tester.pump();
    expect(button(tester, 'Zoom out').onPressed, isNotNull);
    expect(find.text('1.0x'), findsOneWidget);
  });

  testWidgets('a camera swapped in a rebuild shows its own zoom', (
    tester,
  ) async {
    await tester.pumpWidget(controls(Camera(zoom: 1)));
    expect(find.text('1.0x'), findsOneWidget);
    await tester.pumpWidget(controls(Camera(zoom: 2)));
    await tester.pump();
    expect(find.text('2.0x'), findsOneWidget);
  });
}
