# Guides

The Just Game Engine's guides, as the docs site at https://engine.justunknown.com/docs shows them,
shipped with the package so each version carries the guides written for it. Tools read this
list for the order: `just game mcp` serves the guides to AI assistants, and
`tool/llms_txt.dart` turns them into the site's `llms.txt`.

Each guide is `<slug>.md` (the site's page is `/docs/<slug>`): a `# Title`, then
`_Section_ · Summary`, then the guide.

## Getting started

- [Introduction](introduction.md): What Just Game Engine is, the tools that come with it, the platforms it runs on and where the 2.0 release stands.
- [Installation](installation.md): Start a new game with the just CLI, or add the engine to an existing Flutter app, then opt into 3D where you need it.
- [Your first game](quick-start.md): Draw shapes, move one, load a level from scene JSON, and learn the five things that trip people up.
- [Migrating from 1.x](migration.md): Upgrade a 1.6 game to 2.0: the checklist first, then each breaking change with before-and-after code.

## Tools

- [Level editor](editor.md): Install the level editor, give it an entry point that never ships, register your components, and find your way around its tools.
- [The just CLI](cli.md): Install just, create a game with it, and run, build, check, upgrade and migrate the game with the just game commands.

## Core

- [Engine & lifecycle](engine.md): Create an Engine, configure it with EngineConfig, take it through initialize, start and dispose, and reach its subsystems, game loop and context.
- [World, entities & systems](ecs.md): Model a game as entities that carry components, and its rules as systems that query them every fixed step.
- [Scenes & saving](scenes.md): Load levels from JSON scene files, describe your own components so scenes can hold them, and handle format versions and loading errors.

## Graphics

- [Rendering & layers](rendering.md): How the engine draws your world: the render system, draw order, self-drawing shapes, culling, render hooks and passes, parallax backgrounds and render stats.
- [Sprites & animation](sprites.md): Show images and atlas regions, play clips from TexturePacker and Aseprite atlases, and let animator graphs pick the clip for you.
- [Timelines](timelines.md): Animate any component field over time, and play clips, cut cameras, switch entities, play sounds and fire events from one asset.
- [Cameras](cameras.md): Describe shots with virtual cameras and let the camera brain pick, blend, frame, confine and shake them, in 2D and 3D.
- [Particles, effects & post-processing](particles.md): Particle emitters and presets, deterministic tick-based effects that replay and serialize, and fragment-shader passes over the frame.
- [3D graphics](graphics-3d.md): Opt in to 3D drawing on Flutter GPU: glTF models, lights, sky, skeletal animation and eleven built-in shapes, in metres with +Y down.

## Gameplay

- [2D physics](physics-2d.md): Give entities bodies and shapes with RigidBody2D and Collider2D, move them with forces or a CharacterBody2D, and react to collisions, sensors and queries.
- [3D physics](physics-3d.md): Opt into Jolt-based 3D physics with Physics3D, then use RigidBody3D, Collider3D and CharacterBody3D, which mirror the 2D components.
- [Input](input.md): Read named actions from keyboard, mouse, gamepads and touch through engine.input, with local multiplayer, rebinding and on-screen controls.
- [Level maps](level-maps.md): Draw tile maps from the scene, a .map.json file or a Tiled .tmx/.tmj with LevelMapComponent, give layers collision, and change tiles while the game runs.
- [Tags, targets & spawners](tags-spawners.md): Label entities with tags, point at entities by name or tag with EntityTarget, and create players and enemies at spawn points with your own spawners.

## Audio & content

- [Audio](audio.md): Play music and sound effects through engine.music and engine.sfx, attach sounds to entities, place them in 3D, and start audio correctly on the web.
- [Assets & storage](assets.md): Load images, JSON, text and sounds through engine.assets, group and reference-count them, and keep data between runs with engine.cache.
- [Localization](localization.md): Translate your game with a LocalizationManager on engine.context.localization: string files per locale, namespaces, fallbacks, plurals, selects and widgets that follow the locale.
- [Dialogue & subtitles](dialogue.md): Write branching dialogue in Yarn Spinner 2.x, run it with DialogueManager and DialogueRunner, show it with the ready-made widgets, and time subtitles with SubtitleController.

## Flutter & shipping

- [UI over the game](game-widget.md): Host the game in a GameWidget, draw a HUD with its overlay, put menus and text fields on engine.layers, and use the ready-made widgets.
- [Services & plugins](services.md): Run your own code beside the engine with EngineService, observe a running engine with EnginePlugin, and add achievements, currency and more from just_game_services.
- [Debugging & stats](debugging.md): Read the engine's performance and per-subsystem stats, switch on the debug overlay and the developer terminal, and fix the most common problems.
- [Testing](testing.md): Test game logic with a bare World or a headless Engine, step time yourself, and load scenes and assets without a device.
- [Platforms & the web](platforms.md): Where the engine runs, what changes on the web and WebAssembly, what Linux builds need, and where 3D graphics and 3D physics are available.
