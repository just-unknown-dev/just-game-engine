// A camera shot ending exactly at the end of a once timeline: it holds while
// the timeline is there, and gives the camera its priority back once the
// timeline has finished — the game gets its camera back whether or not the
// author snapped the block to the end. A ping-pong turning round there
// keeps it.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  late VirtualCameraComponent close;

  setUp(() {
    world = World(extensions: [BuiltInComponents.extension]);
    close = VirtualCameraComponent(priority: 1);
    world.createEntityWithComponents([close], name: 'Close');
  });
  tearDown(() => world.dispose());

  TimelinePlayback cutscene(TimelineWrap wrap) => TimelinePlayback(
    TimelineAsset(
      duration: 5,
      wrap: wrap,
      tracks: [
        CameraShotTrack(
          blocks: const [
            TimelineBlock(start: 0, length: 5, value: 'Close', amount: 100),
          ],
        ),
      ],
    ),
    world: world,
    owner: world.createEntity(),
  )..play();

  test('a once timeline gives the shot back when it finishes', () {
    final p = cutscene(TimelineWrap.once)..update(4);
    expect(close.priority, 101);
    p.update(1);
    expect(p.isFinished, isTrue);
    expect(close.priority, 1);
  });

  test('a ping-pong turning round on the end keeps the shot', () {
    final p = cutscene(TimelineWrap.pingPong)..update(5);
    expect(p.time, 5);
    expect(close.priority, 101);
    p.update(1);
    expect(close.priority, 101);
    p.dispose();
    expect(close.priority, 1);
  });
}
