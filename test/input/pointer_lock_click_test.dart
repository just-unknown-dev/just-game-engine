// A click on the game holds the mouse for looking when the game asks for it
// (`input.lockPointerOnClick`), through the Windows plugin's channel.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  testWidgets('a mouse click on the game takes the pointer lock only when '
      'the game asks for it', (tester) async {
    const channel = MethodChannel('just_inputs/pointer_lock');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'lock' ? true : null;
    });
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      await tester.runAsync(PointerLock.instance.dispose);
    });

    final engine = Engine();
    addTearDown(() => tester.runAsync(engine.dispose));
    await tester.runAsync(engine.initialize);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(engine: engine),
      ),
    );

    final centre = tester.getCenter(find.byType(GameWidget));
    Future<void> click() async {
      final mouse = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    await click();
    expect(calls, isNot(contains('lock')), reason: 'the game did not ask');

    engine.input.lockPointerOnClick = true;
    await click();
    expect(calls.where((c) => c == 'lock'), hasLength(1));
    expect(engine.input.pointerLock.isRequested, isTrue);

    await click();
    expect(
      calls.where((c) => c == 'lock'),
      hasLength(1),
      reason: 'already held',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
