import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/ocr/recognized_text_block.dart';

/// A widget that displays OCR text regions as interactive overlays on top of an image.
///
/// This overlay synchronizes with the PhotoView's transform and scale to ensure
/// accurate placement of text bounding boxes during zoom and pan operations.
class OcrOverlayWidget extends ConsumerStatefulWidget {
  /// The recognized text blocks to display.
  final List<RecognizedTextBlock> blocks;
  
  /// The original size of the image in pixels (for coordinate conversion).
  final Size imageSize;
  
  /// The PhotoView controller for getting transform and scale information.
  final dynamic controller;
  
  /// Creates a new [OcrOverlayWidget].
  const OcrOverlayWidget({
    super.key,
    required this.blocks,
    required this.imageSize,
    required this.controller,
  });
  
  @override
  ConsumerState<OcrOverlayWidget> createState() => _OcrOverlayWidgetState();
}

class _OcrOverlayWidgetState extends ConsumerState<OcrOverlayWidget> {
  /// Map of text blocks to their corresponding gesture detectors.
  final Map<int, GlobalKey> _blockKeys = {};

  @override
  void initState() {
    super.initState();
    // Initialize keys for each block
    for (int i = 0; i < widget.blocks.length; i++) {
      _blockKeys[i] = GlobalKey();
    }
  }

  /// Gets the current transform from the controller.
  dynamic _getCurrentTransform() {
    try {
      return widget.controller.value.transform;
    } catch (e) {
      // Fallback if transform is not available
      return Matrix4.identity();
    }
  }

  /// Gets the current scale from the controller.
  double _getCurrentScale() {
    try {
      return widget.controller.value.scale;
    } catch (e) {
      return 1.0;
    }
  }

  /// Handles tap on a text block - shows copy dialog.
  void _onBlockTap(int index, String text) {
    // Show copy action in a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Text Detected'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () {
              final data = ClipboardData(text: text);
              Clipboard.setData(data);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Text copied to clipboard')),
              );
              Navigator.pop(context);
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transform = _getCurrentTransform();
    final scale = _getCurrentScale();

    return Listener(
      onPointerDown: (details) {
        // Check if tap is on a text block
        for (int i = 0; i < widget.blocks.length; i++) {
          final block = widget.blocks[i];
          if (_isPointInBlock(details.localPosition, block)) {
            _onBlockTap(i, block.text);
            return;
          }
        }
      },
      child: CustomPaint(
        painter: OcrOverlayPainter(
          blocks: widget.blocks,
          imageSize: widget.imageSize,
          transform: transform,
          scale: scale,
        ),
        child: Container(), // Empty container for layout
      ),
    );
  }

  /// Checks if a point is inside a text block's bounding box.
  bool _isPointInBlock(Offset point, RecognizedTextBlock block) {
    final rect = _getBlockRect(block);
    return rect.contains(point);
  }

  /// Gets the screen rectangle for a text block.
  Rect _getBlockRect(RecognizedTextBlock block) {
    final scale = _getCurrentScale();

    // Convert normalized coordinates to image pixel coordinates
    final x1 = block.boundingBox[0] * widget.imageSize.width;
    final y1 = block.boundingBox[1] * widget.imageSize.height;
    final x2 = block.boundingBox[2] * widget.imageSize.width;
    final y2 = block.boundingBox[3] * widget.imageSize.height;
    final x3 = block.boundingBox[4] * widget.imageSize.width;
    final y3 = block.boundingBox[5] * widget.imageSize.height;
    final x4 = block.boundingBox[6] * widget.imageSize.width;
    final y4 = block.boundingBox[7] * widget.imageSize.height;

    // Apply scale transform
    final scaledX1 = x1 * scale;
    final scaledY1 = y1 * scale;
    final scaledX2 = x2 * scale;
    final scaledY2 = y2 * scale;
    final scaledX3 = x3 * scale;
    final scaledY3 = y3 * scale;
    final scaledX4 = x4 * scale;
    final scaledY4 = y4 * scale;

    // Create bounding rectangle
    final minX = <double>[scaledX1, scaledX2, scaledX3, scaledX4].reduce(math.min);
    final maxX = <double>[scaledX1, scaledX2, scaledX3, scaledX4].reduce(math.max);
    final minY = <double>[scaledY1, scaledY2, scaledY3, scaledY4].reduce(math.min);
    final maxY = <double>[scaledY1, scaledY2, scaledY3, scaledY4].reduce(math.max);

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Custom painter that draws text block bounding boxes on an overlay.
class OcrOverlayPainter extends CustomPainter {
  /// The recognized text blocks to draw.
  final List<RecognizedTextBlock> blocks;

  /// The original size of the image in pixels.
  final Size imageSize;

  /// Current transform from the image viewer.
  final dynamic transform;

  /// Current scale factor from the image viewer.
  final double scale;

  /// Creates a new [OcrOverlayPainter].
  OcrOverlayPainter({
    required this.blocks,
    required this.imageSize,
    required this.transform,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (blocks.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.blue.withAlpha(102) // Blue with 40% opacity
      ..strokeWidth = 2.0;

    for (final block in blocks) {
      _drawBlock(canvas, paint, block);
    }
  }

  /// Draws a single text block's bounding box.
  void _drawBlock(Canvas canvas, Paint paint, RecognizedTextBlock block) {
    final x1 = block.boundingBox[0] * imageSize.width * scale;
    final y1 = block.boundingBox[1] * imageSize.height * scale;
    final x2 = block.boundingBox[2] * imageSize.width * scale;
    final y2 = block.boundingBox[3] * imageSize.height * scale;
    final x3 = block.boundingBox[4] * imageSize.width * scale;
    final y3 = block.boundingBox[5] * imageSize.height * scale;
    final x4 = block.boundingBox[6] * imageSize.width * scale;
    final y4 = block.boundingBox[7] * imageSize.height * scale;

    // Draw the quadrilateral
    final path = Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2)
      ..lineTo(x3, y3)
      ..lineTo(x4, y4)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant OcrOverlayPainter oldDelegate) {
    return blocks != oldDelegate.blocks ||
        imageSize != oldDelegate.imageSize ||
        scale != oldDelegate.scale;
  }
}
