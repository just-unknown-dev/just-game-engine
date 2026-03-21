/// Memory Management
///
/// Object Pool
///
/// A high-performance, generic object pool that minimises GC pressure by
/// recycling instances instead of allocating new ones each frame.
///
/// Usage:
/// ```dart
/// class Bullet implements Recyclable {
///   double x = 0, y = 0, speed = 0;
///   @override
///   void reset() { x = 0; y = 0; speed = 0; }
/// }
///
/// final pool = ObjectPool(() => Bullet(), initialSize: 200);
/// final b = pool.acquire();
/// // ... use b ...
/// pool.release(b);
/// ```
///
/// Cache Management
///
/// Implements caching for game assets and data using just_storage and just_database.
///
library;

export 'object_pool.dart';
export 'cache_manager.dart';
