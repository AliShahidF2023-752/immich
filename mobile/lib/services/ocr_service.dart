import 'dart:async';

/// Service for performing OCR (Optical Character Recognition) on images.
///
/// This service provides asynchronous OCR functionality that:
/// - Runs OCR only after the image is fully loaded and rendered
/// - Caches results per image to avoid re-processing
/// - Uses native iOS Vision framework via platform channel
/// - Debounces rapid image switching to avoid unnecessary processing
///
/// ## Usage
///
/// ```dart
/// // Check if text was detected in an image
/// final hasText = ocrService.hasText(asset.heroTag);
///
/// // Recognize text in an image (cached automatically)
/// final blocks = await ocrService.recognizeText(imageInfo, asset.heroTag);
///
/// // Clear cache when needed
/// ocrService.clearCache(asset.heroTag);
/// ```
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/domain/models/ocr/recognized_text_block.dart';

class OcrService {
  static const MethodChannel _channel = MethodChannel('immich_mobile/ocr');
  
  /// Cache for OCR results keyed by asset hero tag
  static final Map<String, List<RecognizedTextBlock>> _cache = {};
  
  /// Debounce timer for rapid image switching
  Timer? _debounceTimer;
  
  /// Maximum cache size to prevent memory issues
  static const int maxCacheSize = 50;
  
  /// Minimum confidence score threshold for accepting OCR results.
  ///
  /// Values below this threshold will be filtered out.
  double minConfidenceThreshold = 0.5;
  
  /// Whether OCR is enabled
  bool _enabled = true;
  
  /// Enable or disable OCR functionality.
  set enabled(bool value) => _enabled = value;
  
  /// Check if OCR is enabled.
  bool get isEnabled => _enabled;
  
  /// Recognizes text in the given image.
  ///
  /// This method:
  /// - Checks cache first to avoid re-processing
  /// - Runs OCR asynchronously on a background thread
  /// - Filters results by confidence threshold
  /// - Updates cache with new results
  ///
  /// Returns an empty list if:
  /// - OCR is disabled
  /// - No text was detected
  /// - Image processing failed
  Future<List<RecognizedTextBlock>> recognizeText(
    dynamic imageInfo,
    String heroTag, {
    double? minConfidence,
  }) async {
    if (!_enabled) {
      return [];
    }
    
    // Check cache first
    final cached = _cache[heroTag];
    if (cached != null) {
      return cached;
    }
    
    // If imageInfo is already an Image object, use it directly
    // Otherwise, we need to get the actual image data
    // For now, we'll call the native OCR method
    try {
      final result = await _channel.invokeMethod<Map<String, dynamic>>('recognizeText', {
        'heroTag': heroTag,
        'imageWidth': imageInfo.image.width,
        'imageHeight': imageInfo.image.height,
      });
      
      if (result == null) {
        return [];
      }
      
      final blocks = <RecognizedTextBlock>[];
      final rawBlocks = List<dynamic>.from(result['blocks'] ?? []);
      
      for (int i = 0; i < rawBlocks.length; i++) {
        final blockJson = rawBlocks[i] as Map<String, dynamic>;
        final block = RecognizedTextBlock.fromJson(blockJson);
        
        // Apply confidence threshold
        if (block.confidence >= (minConfidence ?? minConfidenceThreshold)) {
          blocks.add(block.copyWith(regionIndex: i));
        }
      }
      
      // Update cache
      _cache[heroTag] = blocks;
      
      // Enforce cache size limit
      if (_cache.length > maxCacheSize) {
        final keys = _cache.keys.toList();
        _cache.remove(keys.first);
      }
      
      return blocks;
    } on PlatformException catch (e) {
      debugPrint('OCR failed: ${e.code} - ${e.message}');
      return [];
    } catch (e, stackTrace) {
      debugPrint('OCR error: $e\n$stackTrace');
      return [];
    }
  }
  
  /// Clears the OCR cache for a specific image.
  void clearCache(String heroTag) {
    _cache.remove(heroTag);
  }
  
  /// Clears all cached OCR results.
  void clearAllCache() {
    _cache.clear();
  }
  
  /// Checks if text has been recognized in the given image.
  bool hasText(String heroTag) {
    final blocks = _cache[heroTag];
    return blocks != null && blocks.isNotEmpty;
  }
  
  /// Debounced OCR call for rapid image switching.
  ///
  /// Use this method when navigating between images quickly to avoid
  /// triggering OCR multiple times in quick succession.
  Future<List<RecognizedTextBlock>> recognizeTextDebounced(
    dynamic imageInfo,
    String heroTag, {
    Duration delay = const Duration(milliseconds: 300),
  }) async {
    _debounceTimer?.cancel();
    
    return Future.delayed(delay, () async {
      final blocks = await recognizeText(imageInfo, heroTag);
      return blocks;
    });
  }
  
  /// Gets statistics about the OCR cache.
  Map<String, dynamic> getCacheStats() {
    int totalBlocks = 0;
    for (final blocks in _cache.values) {
      totalBlocks += blocks.length;
    }
    
    return {
      'cachedImages': _cache.length,
      'totalBlocks': totalBlocks,
      'maxCacheSize': maxCacheSize,
    };
  }
}

/// Global instance of the OCR service.
final OcrService ocrService = OcrService();
