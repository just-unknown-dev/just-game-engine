/// The prefab file format lives in `package:just_game_engine_formats`,
/// which is pure Dart so the editor and the `just` tool share it.
/// Re-exported here for the engine's own imports and its public API.
library;

export 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show
        PrefabApply,
        PrefabCollapse,
        PrefabEntity,
        PrefabExpander,
        PrefabFile,
        PrefabInstance,
        PrefabNode,
        PrefabOverride;
