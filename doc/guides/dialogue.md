# Dialogue & subtitles

_Audio & content_ · Write branching dialogue in Yarn Spinner 2.x, run it with DialogueManager and DialogueRunner, show it with the ready-made widgets, and time subtitles with SubtitleController.

Dialogue is written in Yarn Spinner 2.x `.yarn` files. A `DialogueManager` loads them and runs them; each running conversation is a `DialogueRunner` that reports its lines and choices through signals; `DialogueBox` and `DialogueChoices` show them. Timed subtitles for cutscenes and voice-over use a `SubtitleController`.

## Write a script

A file holds one or more nodes. Each node has a `title:` header, `---`, its lines, and `===`.

```text assets/dialogue/innkeeper.yarn
title: Start
---
<<declare $visits = 0>>
Innkeeper: Welcome to the inn! #line:inn_welcome
<<if $visits > 0>>
Innkeeper: Back again, {$playerName}?
<<endif>>
<<set $visits = $visits + 1>>
-> I need a room. <<if $gold >= 10>>
    <<set $gold = $gold - 10>>
    <<play_sound coin>>
    Innkeeper: Up the stairs, second door.
-> Just looking.
    <<jump Goodbye>>
===
title: Goodbye
---
Innkeeper: Safe travels.
===
```

The parser supports:

- lines with an optional `Character:` prefix, and `#line:key`, `#audio:key` and other `#tags`;
- `{$name}` variables in lines;
- `->` options with indented bodies, made conditional with `<<if ...>>` after the text or an `#if` tag;
- `<<if>>`, `<<elseif>>`, `<<else>>` and `<<endif>>`;
- `<<jump Node>>`, `<<stop>>`, `<<set $name = value>>` (or `to`) and `<<declare $name = value>>`;
- your own commands, such as `<<play_sound coin>>`, and `// comments`.

Expressions support literals, `$variables`, arithmetic, comparisons (also as `eq`, `gt` and the other Yarn words), `and`, `or`, `xor` and `not`, and your own predicates written `[name]`. Yarn functions such as `visited("Shop")` are not supported, and a bare word without `$` is an error: the condition counts as false and a debug build logs it. A malformed file throws a `YarnParseException` that names the line.

## Load and run dialogue

```dart lib/dialogue.dart
import 'package:just_game_engine/just_game_engine.dart';

Future<DialogueManager> setUpDialogue(Engine engine) async {
  final narrative = DialogueManager(
    // Read #line: keys from the engine's strings, in the dialogue namespace.
    localizer: DialogueLocalizer(manager: engine.context.localization),
  );
  await narrative.loadGraph('assets/dialogue/innkeeper.yarn'); // id: innkeeper

  narrative.globalVariables
    ..set('playerName', 'Aria')
    ..set('gold', 25);
  narrative.conditions.register(
    'hasKey',
    (vars) => vars.get<bool>('key') ?? false,
  );
  narrative.commands.register('play_sound', (ctx) async {
    engine.world.getSystem<AudioSystem>()?.playOneShot(
      'assets/audio/${ctx.arg(0)}.wav',
    );
  });
  return narrative;
}
```

- `loadGraph(path)` registers a file under its name without the extension; `parseAndRegister(source, id: ...)` takes Yarn text.
- `createRunner(graphId)` makes a runner; `runner.start('Start')` runs it from a node. `startDialogue(graphId: ..., startNode: ...)` does both and returns the runner.
- Drive a runner with `advance()` after a line, `selectChoice(index)` for an option and `stop()` to end early. `isRunning` says whether it is still going.
- `runner.signals` holds `currentLine` (a `DialogueLine` with `character`, `text`, `lineKey`, `audioKey` and `tags`), `choices` (each `DialogueChoice` has `index`, `text` and `isAvailable`), `isDialogueActive`, `activeSpeaker` and `activeNodeTitle`. They are `ValueListenable`s, so `ValueListenableBuilder` works with them.
- `globalVariables` is shared by every runner of the manager. Names are read without the `$` and ignore case. Save them with `toMap()` and restore them with `loadFromMap(map)`.
- Command names ignore case; a command's arguments are in `ctx.args`, with `ctx.arg(0)` for one of them.

## Show it on screen

`DialogueBox` shows the current line with a typewriter effect: the first tap finishes the line, the next calls `onTap`. It hides itself when there is no line. `DialogueChoices` lists the options and calls `selectChoice` when one is tapped, showing unavailable options greyed out unless `showUnavailable: false`. Both are in `package:just_game_engine/widgets.dart`.

```dart lib/talk.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

Widget talkScreen(Engine engine, DialogueRunner runner) => GameWidget(
  engine: engine,
  overlay: Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogueChoices(runner: runner),
          DialogueBox(runner: runner, onTap: runner.advance),
        ],
      ),
    ),
  ),
);
```

> **Note:** The box starts listening to its runner when it is first built and shows the lines presented after that. Build it before you call `runner.start`.

The box also takes `typewriterSpeed`, `portraitBuilder` (a widget for the speaking character), `textStyle`, `characterNameStyle`, `boxDecoration` and `height`. Overlays and layers are covered in [GameWidget](/docs/game-widget).

## NPCs and trigger zones

Add `DialogueSystem(manager: narrative)` to the world for dialogue tied to entities; it is not a default system. It finds the player by tag (`player` unless you pass `playerTag`).

- `DialogueComponent(graphId: ..., startNode: ..., interactionRadius: 64)` on an NPC. The system sets `isInteractable` while the player is within the radius and `isInDialogue` while the NPC's runner runs. Start the conversation yourself, for example on an interact action: `narrative.createRunnerForEntity(npc.id, graphId)`, then `start(startNode)` on the runner it returns.
- `DialogueTriggerComponent(graphId: ..., triggerRadius: 64, triggerOnce: true)` on an invisible entity starts its dialogue as the player steps inside. A repeating trigger fires again only after the player leaves and comes back.
- Both take `autoAdvance` and `autoAdvanceDelay` (seconds per line) for cutscene-style monologues; choices still wait for the player.

`narrative.isAnyDialogueActive` and `narrative.activeGraphId` are signals for pausing gameplay or hiding the HUD while someone talks.

## Localized lines

A line tagged `#line:key` is looked up under that key in the `dialogue` namespace; when the key is missing, the line's own text is shown. Give the manager a `DialogueLocalizer` that uses the engine's `LocalizationManager`, as above, so dialogue follows the same locale as the rest of the game. Then load the strings with `l10n.load(locale, path, ns: LocalizationManager.dialogueNamespace)`, or call `localizer.loadLocale(locale)`, which reads `<basePath>_<locale>.json` (`basePath` is `assets/data/dialogue` unless you pass one) and falls back to the bare language and then English. `loadLocale` also sets that manager's locale, so with the engine's `LocalizationManager` it switches the whole game's language, not just the dialogue's. A `DialogueManager()` made without a localizer uses a manager of its own, not the engine's. See [Localization](/docs/localization).

## Subtitles

A `SubtitleTrack` is a list of `SubtitleCue`s (`start`, `end` in seconds, and `text`), in time order. A `SubtitleController` plays a track: you tell it the elapsed time with `update(seconds)` and it sets its `currentText` signal. `SubtitleOverlay`, from `widgets.dart`, draws the current text in a dark panel over its child.

```dart lib/subtitles.dart
final subtitles = SubtitleController(
  track: const SubtitleTrack([
    SubtitleCue(start: 0.5, end: 2.5, text: 'Wake up.'),
    SubtitleCue(start: 3.0, end: 6.0, text: 'The ship is sinking.'),
  ]),
);

/// Moves the subtitles on with the game's time, so pausing pauses them.
class SubtitleClockSystem extends System {
  SubtitleClockSystem(this.controller);

  final SubtitleController controller;
  double _elapsed = 0;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    _elapsed += deltaTime;
    controller.update(_elapsed);
  }
}

// engine.world.addSystem(SubtitleClockSystem(subtitles));
// SubtitleOverlay(controller: subtitles, child: GameWidget(engine: engine))
```

`SubtitleTrack.localized(entries: [(start: 0.5, end: 2.5, key: 'intro.wake')], l10n: l10n)` builds cues from localization keys, resolved once with the current locale. `reset()` clears the text, and `totalDuration` is the end of the last cue.
