/// Scenes and prefabs: loading a scene into a world, prefab files, the
/// library that loads them, and the components that mark an instance.
library;

export 'scene_loader.dart';
export 'prefab_components.dart';
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
export 'prefab_library.dart';
export 'prefabs_context.dart' show ContextPrefabs, PrefabLoader;
