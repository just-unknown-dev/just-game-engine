/// What a camera can see, for culling.
library;

import 'dart:ui';

import 'package:just_dart/just_dart.dart';

/// The region of the world a camera sees.
///
/// A 2-D camera sees a rectangle of the world plane ([PlanarViewVolume]); a
/// camera in space sees a frustum ([FrustumViewVolume]). Culling asks
/// [intersectsAabb] and never needs to know which.
abstract interface class ViewVolume {
  /// The part of the world plane z = 0 in view — what 2-D culling uses.
  Rect get planarBounds;

  /// Whether [box] may be in view. Conservative: a box reported in view may
  /// just miss; one reported out of view is out.
  bool intersectsAabb(Aabb3 box);
}

/// What a 2-D camera sees: a rectangle of the world, at every depth.
class PlanarViewVolume implements ViewVolume {
  PlanarViewVolume([this.planarBounds = Rect.zero]);

  @override
  Rect planarBounds;

  @override
  bool intersectsAabb(Aabb3 box) =>
      !box.isEmpty &&
      box.min.x <= planarBounds.right &&
      box.max.x >= planarBounds.left &&
      box.min.y <= planarBounds.bottom &&
      box.max.y >= planarBounds.top;
}

/// What a camera in space sees: its frustum.
class FrustumViewVolume implements ViewVolume {
  /// The six planes, from the camera's view-projection.
  final Frustum frustum = Frustum();

  @override
  Rect planarBounds = Rect.zero;

  /// Rebuild from the camera's [viewProjection] and the part of the world
  /// plane it sees.
  void update(Matrix4 viewProjection, Rect planar) {
    frustum.setFromViewProjection(viewProjection);
    planarBounds = planar;
  }

  @override
  bool intersectsAabb(Aabb3 box) => frustum.intersectsAabb(box);
}
