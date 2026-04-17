/// Memory management exports for the engine.
///
/// Generic pooling, arenas, scopes, profiling, and resource lifetimes are now
/// provided by the shared just_memory package.
///
/// Engine-specific caching remains exported here for convenience.
library;

export 'cache_manager.dart';
export 'package:just_memory/just_memory.dart';
