/// Mixin / interface for objects that can be returned to an [ObjectPool].
///
/// Implementors must clear all per-instance state in [reset] so the object
/// can be safely reused without leaking data from a previous lifecycle.
abstract mixin class Recyclable {
  /// Reset all mutable state to defaults before the object is reused.
  void reset();
}

/// Generic object pool.
///
/// Maintains a LIFO free-list so the most recently released (and therefore
/// most cache-hot) object is the next one acquired.
class ObjectPool<T extends Recyclable> {
  final List<T> _pool;
  final T Function() _factory;

  /// Maximum number of objects the pool will hold. Objects released beyond
  /// this limit are discarded (left to GC). `null` means unbounded.
  final int? maxSize;

  /// Number of objects currently sitting in the pool (available).
  int get available => _pool.length;

  /// Total number of objects acquired over the pool's lifetime.
  int _totalAcquired = 0;

  /// Peak number of objects held in the pool at any point.
  int _peakAvailable = 0;

  /// Total acquisitions since creation.
  int get totalAcquired => _totalAcquired;

  /// Peak pool size reached.
  int get peakAvailable => _peakAvailable;

  /// Create a pool.
  ///
  /// [factory] — zero-arg constructor / factory for new instances.
  /// [initialSize] — pre-warm the pool with this many objects.
  /// [maxSize] — optional upper bound; excess released objects are discarded.
  ObjectPool(this._factory, {int initialSize = 0, this.maxSize})
    : _pool = List<T>.generate(initialSize, (_) => _factory()) {
    _peakAvailable = initialSize;
  }

  /// Obtain an object — reuses a pooled instance when possible, otherwise
  /// allocates a new one via the factory.
  T acquire() {
    _totalAcquired++;
    return _pool.isNotEmpty ? _pool.removeLast() : _factory();
  }

  /// Return an object to the pool after calling [Recyclable.reset].
  void release(T object) {
    object.reset();
    if (maxSize != null && _pool.length >= maxSize!) return;
    _pool.add(object);
    if (_pool.length > _peakAvailable) _peakAvailable = _pool.length;
  }

  /// Release every object in [items] back to the pool.
  void releaseAll(Iterable<T> items) {
    for (final item in items) {
      item.reset();
      if (maxSize != null && _pool.length >= maxSize!) continue;
      _pool.add(item);
    }
    if (_pool.length > _peakAvailable) _peakAvailable = _pool.length;
  }

  /// Discard all pooled objects (e.g. on scene teardown).
  void clear() => _pool.clear();
}
