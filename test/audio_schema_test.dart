// What a scene keeps of its sounds: an Audio Source's 3-D settings and
// channel, and the Audio Listener — and that a scene saved before these
// existed still loads.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

final _defs = ComponentDefinitionRegistry.core();

T _roundTrip<T extends Component>(T component) =>
    _defs.decode(_defs.encode(component)!)! as T;

void main() {
  test('an Audio Source keeps how it is heard in 3-D', () {
    final back = _roundTrip(
      AudioSourceComponent(
        clipPath: 'assets/audio/orb_hum.wav',
        loop: true,
        volume: 0.7,
        channel: AudioChannel.ambient,
        is3d: true,
        minDistance: 1.5,
        maxDistance: 18,
        rolloff: AudioRolloff.linear,
        dopplerLevel: 1,
        farCutoff: 1200,
      ),
    );
    expect(back.clipPath, 'assets/audio/orb_hum.wav');
    expect(back.loop, isTrue);
    expect(back.volume, 0.7);
    expect(back.channel, AudioChannel.ambient);
    expect(back.is3d, isTrue);
    expect(back.minDistance, 1.5);
    expect(back.maxDistance, 18);
    expect(back.rolloff, AudioRolloff.linear);
    expect(back.dopplerLevel, 1);
    expect(back.farCutoff, 1200);
  });

  test('a flat Audio Source keeps its pan', () {
    final back = _roundTrip(
      AudioSourceComponent(clipPath: 'assets/audio/ui.wav', pan: -0.5),
    );
    expect(back.pan, -0.5);
    expect(back.is3d, isFalse);
  });

  test('a source saved before 3-D settings loads with the defaults', () {
    final back =
        _defs.decode({
              'type': 'AudioSourceComponent',
              'fields': {
                'path': 'assets/audio/old.wav',
                'loop': true,
                'playOnAdd': true,
                'volume': 0.5,
                'pitch': 1.0,
              },
            })!
            as AudioSourceComponent;
    expect(back.clipPath, 'assets/audio/old.wav');
    expect(back.is3d, isFalse);
    expect(back.channel, AudioChannel.sfx);
    expect(back.spatial, const AudioSpatial());
  });

  test('the Audio Listener is saved, both of its choices', () {
    final back = _roundTrip(AudioListenerComponent(faceCamera: true));
    expect(back.faceCamera, isTrue);
    expect(back.atCamera, isFalse);
    final def = _defs.definitionByType('AudioListenerComponent')!;
    expect(def.hints.name, 'Audio Listener');
    expect(def.hints.group, 'Audio');
  });

  test('a source\'s settings cannot make an invalid AudioSpatial', () {
    final odd = AudioSourceComponent(
      clipPath: 'a.wav',
      minDistance: 0,
      maxDistance: -3,
      dopplerLevel: -1,
      farCutoff: -5,
    );
    final spatial = odd.spatial;
    expect(spatial.minDistance, greaterThan(0));
    expect(spatial.maxDistance, greaterThanOrEqualTo(spatial.minDistance));
    expect(spatial.dopplerLevel, 0);
    expect(spatial.farCutoff, 0);
  });
}
