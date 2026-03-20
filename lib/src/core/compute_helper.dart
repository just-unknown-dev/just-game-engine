/// Isolate Compute Helpers
///
/// Thin convenience wrappers around Flutter's [compute] for offloading
/// heavy work (physics batches, map parsing, pathfinding, etc.) to a
/// background isolate without blocking the UI / game-loop thread.
library;

import 'package:flutter/foundation.dart';

/// Run a pure function [work] on a background isolate, passing [message] as
/// input and returning the result.
///
/// This is a direct re-export of Flutter's [compute] wrapped with an
/// engine-idiomatic name so call-sites read more clearly:
///
/// ```dart
/// final result = await offload(heavyParse, rawBytes);
/// ```
///
/// **Requirements** – [work] must be a **top-level** or **static** function
/// (closures that capture state are not allowed because they cannot be sent
/// across isolate boundaries).
Future<R> offload<M, R>(ComputeCallback<M, R> work, M message) {
  return compute(work, message);
}

/// Variant of [offload] for functions that take no meaningful input.
///
/// ```dart
/// final grid = await offloadUnit((_) => buildNavGrid());
/// ```
Future<R> offloadUnit<R>(ComputeCallback<void, R> work) {
  return compute(work, null);
}
