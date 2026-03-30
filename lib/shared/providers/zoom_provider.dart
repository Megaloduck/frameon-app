import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported zoom levels (pixel-multiplier for the preview dot grid).
const List<int> kZoomLevels = [4, 8, 10, 12, 14, 16];
const int kDefaultZoom = 12;

/// Currently selected zoom multiplier. UI reads this to highlight the
/// active button; MatrixPreview uses it to size the dot canvas.
final zoomProvider = StateProvider<int>((_) => kDefaultZoom);