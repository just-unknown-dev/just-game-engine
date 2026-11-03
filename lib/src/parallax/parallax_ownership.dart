/// Which system draws a [ParallaxBackground] — not exported.
library;

import 'parallax_background.dart';

/// The `ParallaxRenderSystem` that draws a background, for as long as it
/// does.
///
/// A background both on a `ParallaxComponent` and in the deprecated
/// `engine.parallax` list — as the component's documentation used to ask
/// for — would otherwise scroll and draw twice. The list skips any
/// background marked here.
final Expando<Object> parallaxDrawnBy = Expando<Object>('parallaxDrawnBy');

/// Whether a `ParallaxRenderSystem` draws [background].
bool isDrawnByComponent(ParallaxBackground background) =>
    parallaxDrawnBy[background] != null;
