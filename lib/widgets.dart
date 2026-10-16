/// Ready-made Flutter widgets for a game's screen UI. Optional: a game runs
/// without them, so the main library leaves them out.
///
/// ```dart
/// import 'package:just_game_engine/just_game_engine.dart';
/// import 'package:just_game_engine/widgets.dart';
/// ```
///
/// - Dialogue: `DialogueBoxWidget` and `DialogueChoicesWidget`, UI for a
///   `DialogueRunner`.
/// - Subtitles: `SubtitleOverlay`, which shows a `SubtitleController`'s
///   cues.
/// - Localization: `LocalizationBuilder`, `LocalizedText`, `LocaleSelector`
///   and `context.t()` / `context.tr()` (`L10nContext`). They read the
///   `LocalizationScope` that `GameWidget` puts around the game when
///   `engine.context.localization` is set.
/// - Camera: `GameCameraControls` — wheel and pinch zoom, drag to pan, and
///   on-screen zoom buttons.
/// - Input, from `just_inputs`: `OnScreenControls` (touch sticks and
///   buttons, with `OnScreenVisibility`, `OnScreenButtonFace` and
///   `OnScreenStickPainter`) and the rebinding UI — `RebindList`,
///   `RebindButton`, `RebindRow`, `rebindRows` and `BindingLabel`.
library;

export 'package:just_inputs/just_inputs.dart'
    show
        BindingLabel,
        OnScreenButtonFace,
        OnScreenControls,
        OnScreenStickPainter,
        OnScreenVisibility,
        RebindButton,
        RebindList,
        RebindRow,
        rebindRows;

export 'src/subsystems/camera/camera_controls.dart' show GameCameraControls;
export 'src/subsystems/localization/localization_widget.dart'
    show L10nContext, LocaleSelector, LocalizationBuilder, LocalizedText;
export 'src/subsystems/narrative/ui/dialogue_box_widget.dart';
export 'src/subsystems/narrative/ui/dialogue_choices_widget.dart';
export 'src/subsystems/subtitle/subtitle_overlay.dart';
