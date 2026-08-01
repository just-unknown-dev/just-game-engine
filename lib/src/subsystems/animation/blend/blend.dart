/// Animation Blend Tree — pure math
///
/// Parameter-driven clip-weighting algorithms (1D linear, 2D Gradient Band
/// Interpolation) and the weighted sprite-frame compositing primitive that
/// turns those weights into a correct visual blend. See
/// `ANIMATION_BLEND_TREE.md` at the package root for the full write-up.
library;

export 'blend_space_1d.dart';
export 'blend_space_2d.dart';
export 'blend_compositor.dart';
