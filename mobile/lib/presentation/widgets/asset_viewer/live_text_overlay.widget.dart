import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/services/live_text.service.dart';
import 'package:immich_mobile/widgets/photo_view/photo_view.dart';

class LiveTextOverlay extends StatelessWidget {
  final List<RecognizedTextBlock> blocks;
  final Size imageSize;
  final Size widgetSize;
  final PhotoViewControllerBase? viewController;

  const LiveTextOverlay({
    super.key,
    required this.blocks,
    required this.imageSize,
    required this.widgetSize,
    this.viewController,
  });

  @override
  Widget build(BuildContext context) {
    if (imageSize.width == 0 || imageSize.height == 0) return const SizedBox.shrink();

    double imageAspectRatio = imageSize.width / imageSize.height;
    double widgetAspectRatio = widgetSize.width / widgetSize.height;

    double renderWidth;
    double renderHeight;

    if (imageAspectRatio > widgetAspectRatio) {
      renderWidth = widgetSize.width;
      renderHeight = widgetSize.width / imageAspectRatio;
    } else {
      renderHeight = widgetSize.height;
      renderWidth = widgetSize.height * imageAspectRatio;
    }

    double offsetX = (widgetSize.width - renderWidth) / 2;
    double offsetY = (widgetSize.height - renderHeight) / 2;

    return StreamBuilder<PhotoViewControllerValue>(
      stream: viewController?.outputStateStream,
      initialData: viewController?.value,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final scale = state?.scale ?? 1.0;
        final position = state?.position ?? Offset.zero;

        return Transform(
          transform: Matrix4.identity()
            ..translate(position.dx, position.dy)
            ..scale(scale),
          alignment: Alignment.center,
          child: Stack(
            children: blocks.map((block) {
              final rect = block.boundingBox;
              final left = offsetX + (rect.left * renderWidth);
              final top = offsetY + (rect.top * renderHeight);
              final width = rect.width * renderWidth;
              final height = rect.height * renderHeight;

              return Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: Builder(builder: (context) {
                  return GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: block.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Text copied to clipboard')),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        block.text,
                        style: const TextStyle(
                          color: Colors.transparent, // Invisible text for native selection
                        ),
                      ),
                    ),
                  );
                }),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
