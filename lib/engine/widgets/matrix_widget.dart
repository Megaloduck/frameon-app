import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';

/// Contract for every widget renderer in the engine.
///
/// A [MatrixWidget] knows how to paint one [Layer] into a [PixelBuffer]
/// at a given point in time. It is completely stateless — all state comes
/// from the [Layer] model and [elapsedMs].
///
/// ## Implementing a new widget
///
/// 1. Create a class in `lib/engine/widgets/` that extends [MatrixWidget].
/// 2. Override [render] to draw into [buffer] (already cleared on entry).
/// 3. Register it in [MatrixWidgetRegistry.forLayer].
///
/// ```dart
/// class MyWidget extends MatrixWidget<MyLayer> {
///   const MyWidget();
///
///   @override
///   void render(MyLayer layer, PixelBuffer buffer, int elapsedMs) {
///     // draw into buffer...
///   }
/// }
/// ```
abstract class MatrixWidget<T extends Layer> {
  const MatrixWidget();

  /// Paint [layer] into [buffer] at time [elapsedMs].
  ///
  /// [buffer] is cleared to transparent black before this call.
  /// [elapsedMs] is the total animation time elapsed — used for effects,
  /// scrolling, blinking colons, etc.
  void render(T layer, PixelBuffer buffer, int elapsedMs);
}

// ─────────────────────────────────────────────────────────────────────────────
// Registry
// ─────────────────────────────────────────────────────────────────────────────

/// Dispatches a [Layer] to its concrete [MatrixWidget] renderer.
///
/// Import this file in [MatrixRenderer] and replace the inline switch with
/// `MatrixWidgetRegistry.forLayer(layer).render(layer, buffer, elapsedMs)`.
class MatrixWidgetRegistry {
  MatrixWidgetRegistry._();

  /// Returns the [MatrixWidget] for [layer], or throws if unregistered.
  static MatrixWidget<Layer> forLayer(Layer layer) {
    // Import the concrete widgets here to avoid circular imports.
    // They are registered lazily via a simple switch.
    throw UnimplementedError(
      'MatrixWidgetRegistry.forLayer: '
      'import concrete widgets and wire them in here.',
    );
  }
}