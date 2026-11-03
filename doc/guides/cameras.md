# Cameras

_Graphics_ · Describe shots with virtual cameras and let the camera brain pick, blend, frame, confine and shake them, in 2D and 3D.

`engine.cameraSystem.mainCamera` is the camera the world is drawn through. You can move it yourself, but most games describe shots instead: entities with a `VirtualCameraComponent`. Each frame the camera brain (`engine.cameraSystem.brain`) picks the enabled shot with the highest priority, blends to it, and writes the result into the main camera.

## Moving the main camera yourself

With no virtual camera in the world, the brain leaves the main camera alone and it is yours to move:

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show Offset;
import 'package:just_game_engine/just_game_engine.dart';

void lookAround(Engine engine, Offset tap) {
  final camera = engine.cameraSystem.mainCamera;
  camera
    ..lookAt(const Offset(400, 300))
    ..zoom = 2.0;

  // Where a tap on the screen lands in the world, and back.
  final world = camera.screenToWorld(tap);
  final screen = camera.worldToScreen(world);
  debugPrint('$world is at $screen; in view: ${camera.getVisibleBounds()}');
}
```

`position` is the world point at the centre of the screen. At `zoom` 1 a world unit is one pixel, and larger is closer; `setZoom` keeps it between `minZoom` and `maxZoom`. `rotation` rolls the view, and `moveBy`, `zoomBy` and `zoomToPoint` help with panning and zooming. Moves are immediate: smoothing belongs to shots. `GameCameraControls` in `widgets.dart` adds wheel, pinch and button zoom (see [Game widget](/docs/game-widget)).

## Shots and the camera brain

A shot is an entity with a `VirtualCameraComponent`:

- `priority`: 10 by default. Higher wins; between equals, the one activated most recently (`brain.activate(entity)`).
- `follow`: an `EntityTarget` by tag or name, looked up every frame, so a camera authored in a level finds a player spawned later.
- `zoom`, `dutch` (extra roll, in radians) and `enabled`.
- `standbyUpdate`: `CameraStandbyUpdate.always` keeps a shot settled on its target while it isn't live, instead of snapping when it goes live.

Other components on the same entity shape the shot, as the rest of this page shows. `DefaultSystem.cameras` adds the systems: `CameraTargetGroupSystem` (priority 47), `CameraTriggerSystem` (46) and `CameraBrainSystem` (45), which runs after everything has moved and before rendering, so a shot frames where its target is. Without the default set, call `registerCameraSystems(world, engine.cameraSystem)` once. When you replace a level's entities, call `engine.cameraSystem.brain.reset()` to forget the old cameras.

Blends: `brain.defaultBlend` is a `CameraBlend`, half a second with an ease-in-out `curve` unless you say otherwise, and `CameraBlend.cut` switches at once. `brain.blendTable.rules` holds `CameraBlendRule`s for pairs of cameras by entity name, with `CameraBlendRule.any` (`*`) matching any; the most specific rule wins. `brain.liveCamera` is the live shot, and `brain.onCameraActivated` hears every change.

```dart lib/cameras.dart
import 'package:flutter/painting.dart' show Offset;
import 'package:just_game_engine/just_game_engine.dart';

void addCameras(Engine engine) {
  final world = engine.world;

  // Follows whoever is tagged "player", so it keeps working after a
  // respawn makes a new player entity.
  world.createEntityWithComponents([
    TransformComponent(),
    VirtualCameraComponent(follow: const EntityTarget.tag('player'), zoom: 1.5),
    CameraFramingComponent(
      screenY: 0.1, // the target sits a little below the middle
      deadZoneWidth: 0.15,
      dampingX: 0.3,
      lookaheadTime: 0.25,
    ),
    CameraConfinerComponent(boundsName: 'LevelBounds'),
    CameraImpulseListenerComponent(),
  ], name: 'FollowCam');

  // The view never shows anything outside this rectangle.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(2000, 400, 0)),
    CameraBoundsComponent(width: 4000, height: 800),
  ], name: 'LevelBounds');

  // A fixed shot of the boss room. Its trigger raises its priority from 5
  // to 25 while a player is inside, so it wins there.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(3600, 300, 0)),
    VirtualCameraComponent(priority: 5, zoom: 0.8),
    CameraTriggerComponent(
      width: 800,
      height: 600,
      mode: CameraTriggerMode.boostPriority,
      amount: 20,
    ),
  ], name: 'BossCam');

  // Blend over 0.8 s, but cut straight back when leaving the boss room.
  engine.cameraSystem.brain
    ..defaultBlend = const CameraBlend(duration: 0.8)
    ..blendTable.rules.add(
      const CameraBlendRule(from: 'BossCam', blend: CameraBlend.cut),
    );
}

/// A landing, an explosion: every listening shot near it shakes.
void thud(Engine engine, Offset where) {
  engine.cameraSystem.brain.emitImpulse(
    CameraImpulse(position: where, amplitude: 16, duration: 0.3),
  );
}
```

## Framing the target

`CameraFramingComponent` keeps the followed target where you want it on screen. Everything is in screen fractions, so a shot reads the same at any zoom and window size:

- `screenX`, `screenY`: where the target sits, from the centre. -0.5 is the left or top edge and 0.5 the right or bottom. A platformer often wants a small positive `screenY`.
- `deadZoneWidth`, `deadZoneHeight` (0.1): the target moves freely inside this without the camera moving.
- `softZoneWidth`, `softZoneHeight` (0.8): the target never leaves this, however heavy the damping.
- `dampingX`, `dampingY` (0.5): seconds for the camera to close 99% of the gap; 0 is rigid.
- `lookaheadTime`: looks this many seconds ahead along the target's velocity (0, off), with `lookaheadSmoothing` (0.3 s) calming changes of direction.
- `followX`, `followY`: turn one off to hold that axis at the camera entity's own position, for a room that scrolls only sideways.

## Keeping the view inside the level

Put a `CameraBoundsComponent` (a `width` by `height` rectangle centred on its entity) on an entity of its own, and a `CameraConfinerComponent(boundsName: ...)` on the shot. The confiner keeps the whole view inside the bounds, not just its centre; where the bounds are narrower than the view, it centres on them. Its `damping` (0, a hard wall) softens the edge. Any component that implements `CameraBoundsSource` can serve as bounds.

## Shake: noise and impulses

- `CameraNoiseComponent` adds continuous handheld motion from a `CameraNoisePreset`: `handheldMild`, `handheldNormal` (the default), `handheldStrong` or `shake`, scaled by `amplitudeGain` and `frequencyGain`.
- Impulses replace 1.x's `camera.shake`. Give shots a `CameraImpulseListenerComponent` (`gain`, and a `channels` bit mask), then call `brain.emitImpulse(CameraImpulse(position: ...))` when something happens. Every listening shot reacts by its distance; a `radius` above 0 limits the reach. The same impulses in the same order shake the same way on every run.
- A `CameraImpulseSourceComponent` stores an authored impulse on an entity, and `brain.emitImpulseFrom(entity)` sends it from wherever that entity is.

## Groups, triggers and rails

- Target groups: a `CameraTargetGroupComponent` moves its own entity to the weighted centre of its `members` (each a `CameraGroupMember` with a `target`, `weight` and `radius`; one member tagged `player` covers every player). Follow that entity by name, and add a `CameraGroupFramingComponent` (`padding`, `minZoom`, `maxZoom`, `zoomDamping`) to zoom out as the group spreads.
- Trigger areas: a `CameraTriggerComponent` (640 by 360 by default, centred on its entity) switches a camera while a target is inside. `CameraTriggerMode.enableWhileInside`, the default, makes a shot exist only inside; `boostPriority` adds `amount` to its priority. It drives the camera on its own entity unless `cameraName` names another, and is set off by the `player` tag unless `target` says otherwise.
- Dolly path: a `CameraDollyComponent` rides the shot along `waypoints` in world space (`closed` joins the ends). With `autoDolly` on, the default, it goes to the point nearest the followed entity; turn it off and animate `pathPosition` (0 to 1 along the track) for a scripted move.

## Cameras made of cameras

A manager is a virtual camera whose shot comes from its child entities' virtual cameras, the children being parented to it with `ParentComponent`. The children are not candidates on their own: the brain sees only the manager, at the manager's priority.

- `CameraStateDrivenComponent` shows the child mapped to the `CameraStateComponent.state` of a `source` entity (the first tagged `player` by default).
- `CameraBlendListComponent` plays its children as a sequence of `CameraBlendStep`s (`child`, `hold`, `blend`): a cut-scene. It starts over each time it goes live, so raise its priority to start one and lower it to end it.
- `CameraMixerComponent` shows a weighted mix of its children by name; animate its `weights` to steer between shots.

```dart
import 'package:just_game_engine/just_game_engine.dart';

void addPlayerRig(World world, Entity player) {
  final rig = world.createEntityWithComponents([
    TransformComponent(),
    VirtualCameraComponent(priority: 20),
    CameraStateDrivenComponent(
      states: {'grounded': 'NearCam', 'falling': 'WideCam'},
      defaultChild: 'NearCam',
      blend: 0.4,
    ),
  ], name: 'PlayerRig');

  // The children are ordinary virtual cameras under the rig.
  world.createEntityWithComponents([
    TransformComponent(),
    ParentComponent(parentId: rig.id),
    VirtualCameraComponent(follow: const EntityTarget.tag('player'), zoom: 1.5),
    CameraFramingComponent(),
  ], name: 'NearCam');
  world.createEntityWithComponents([
    TransformComponent(),
    ParentComponent(parentId: rig.id),
    VirtualCameraComponent(follow: const EntityTarget.tag('player'), zoom: 0.8),
    CameraFramingComponent(screenY: -0.2),
  ], name: 'WideCam');

  // The game writes the state; the rig shows the matching child.
  player.addComponent(CameraStateComponent(state: 'grounded'));
}
```

A timeline can also take the shot for a while with a `cameraShot` track (see [Timelines](/docs/timelines)).

## 3D rigs

A shot with `projection: CameraProjection.perspective` sees in perspective, with a `fieldOfView` (in radians, 60 degrees by default), `nearClip` and `farClip`. The default `nearClip` is behind the camera, which a perspective shot replaces with 1, so set a small one for a world in metres. Three components aim a 3D shot:

- `OrbitFollowComponent`: a third-person camera circling its target at `distance` (4 m by default, kept between `minDistance` and `maxDistance`), turned by `yaw` and `pitch` within `minPitch` and `maxPitch`. A pitch below 0 looks down, since +Y is down. It circles a `pivot` (head height by default), with a sideways `shoulder` offset and `damping`.
- `FirstPersonComponent`: the camera at the target's `eye`, turned by `yaw` and `pitch`.
- `LookAtComponent`: aims at the target, raised by `offset`, wherever the rest of the shot put the camera.

Your input code turns the shot by writing `yaw` and `pitch`. For smooth motion at any frame rate, set `brain.updateMode = CameraUpdateMode.frame`: the brain then runs once per rendered frame, following targets between their fixed updates. With 3D physics, `CameraCollision3D` keeps an orbiting camera out of walls; see [3D physics](/docs/physics-3d).

```dart
import 'package:just_game_engine/just_game_engine.dart';

Entity addThirdPersonCamera(World world) => world.createEntityWithComponents([
  TransformComponent(),
  VirtualCameraComponent(
    follow: const EntityTarget.tag('player'),
    projection: CameraProjection.perspective,
    nearClip: 0.1,
    farClip: 500,
  ),
  OrbitFollowComponent(distance: 5, pitch: -0.35, shoulder: 0.5),
], name: 'ThirdPersonCam');

/// Mouse or right-stick look, in radians per unit of input.
void look(Entity camera, double dx, double dy) {
  final orbit = camera.getComponent<OrbitFollowComponent>()!;
  orbit
    ..yaw += dx * 0.005
    ..pitch += dy * 0.005;
}
```

## Screen effects

The main camera also carries screen effects, added with `mainCamera.effectManager.addEffect(...)`: `ScreenFadeEffect` (`fadeIn`, `fadeOut`, `flash`), `LetterboxEffect` (`show`, `hide`) and `MotionBlurEffect`. Fades and letterbox bars keep running on real time while the game is paused.
