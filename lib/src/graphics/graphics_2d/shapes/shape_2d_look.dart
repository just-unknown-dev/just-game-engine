/// What a 2-D shape component draws, as one cheap value.
library;

/// A 2-D shape component that can say, cheaply, what it draws: what a shape
/// drawn into an image — a 2-D material's sheet — is compared by, so it is
/// drawn again only when it changed.
///
/// The five built-in shapes (`Rectangle2DComponent`, `Circle2DComponent`,
/// `Polygon2DComponent`, `Line2DComponent`, `Capsule2DComponent`) are.
abstract interface class Shape2DLook {
  /// A value equal (`==`) to an earlier one exactly when the shape would
  /// draw the same: its size and geometry, its styles (by identity — they
  /// are immutable, see `ShapePaintCache`), whether it is filled, its
  /// outline's width, and the renderable it draws with. While nothing
  /// changes it is the same object, so comparing it costs nothing.
  Object get look;
}
