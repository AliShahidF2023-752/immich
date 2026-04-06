import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/presentation/widgets/images/one_frame_multi_image_stream_completer.dart';
import 'package:immich_mobile/services/placeholder.service.dart';
import 'package:logging/logging.dart';

/// An [ImageProvider] that loads a pre-generated low-resolution placeholder
/// stored on-device for the given [assetId].
///
/// Used in grid views (always) and in the detail viewer before the full image
/// has finished loading or when the device is offline.
class PlaceholderImageProvider extends CancellableImageProvider<PlaceholderImageProvider>
    with CancellableImageProviderMixin<PlaceholderImageProvider> {
  static final _log = Logger('PlaceholderImageProvider');

  /// The asset identifier (remote UUID or local device id).
  final String assetId;

  /// Back-reference to the service that owns the on-device storage.
  final PlaceholderService placeholderService;

  PlaceholderImageProvider({
    required this.assetId,
    required this.placeholderService,
  });

  @override
  Future<PlaceholderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    PlaceholderImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFramePlaceholderImageStreamCompleter(
      _codec(key, decode),
      informationCollector: () => [
        DiagnosticsProperty<String>('Asset id', key.assetId),
      ],
      onLastListenerRemoved: cancel,
    );
  }

  Stream<ImageInfo> _codec(
    PlaceholderImageProvider key,
    ImageDecoderCallback decode,
  ) async* {
    try {
      final bytes = await key.placeholderService.getPlaceholderBytes(key.assetId);
      if (bytes == null || bytes.isEmpty) {
        _log.fine('No placeholder for ${key.assetId}');
        PaintingBinding.instance.imageCache.evict(this);
        return;
      }

      if (isCancelled) {
        PaintingBinding.instance.imageCache.evict(this);
        return;
      }

      final buffer = await ImmutableBuffer.fromUint8List(bytes);
      final codec = await decode(buffer);
      final frame = await codec.getNextFrame();
      yield ImageInfo(image: frame.image, scale: 1.0);
    } catch (e, st) {
      _log.fine('Placeholder load failed for ${key.assetId}', e, st);
      PaintingBinding.instance.imageCache.evict(this);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaceholderImageProvider && assetId == other.assetId;
  }

  @override
  int get hashCode => assetId.hashCode;
}
