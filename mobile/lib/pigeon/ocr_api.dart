import 'package:pigeon/pigeon.dart';

/// Pigeon API definition for OCR functionality.
///
/// This file defines the platform channel messages between Dart and iOS Swift
/// for performing optical character recognition on images.
@FlutterApi()
class OcrApi {
  /// Recognizes text in an image.
  ///
  /// - [heroTag]: Unique identifier for the image being processed.
  /// - [imageWidth]: Width of the image in pixels.
  /// - [imageHeight]: Height of the image in pixels.
  ///
  /// Returns a map containing:
  /// - 'blocks': List of recognized text blocks with their coordinates and confidence scores.
  Map<String, dynamic> recognizeText(String heroTag, int imageWidth, int imageHeight) {
    throw UnimplementedError();
  }
  
  /// Clears all cached OCR results.
  void clearCache() {
    throw UnimplementedError();
  }
}
