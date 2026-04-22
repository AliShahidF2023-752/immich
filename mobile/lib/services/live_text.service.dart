import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class RecognizedTextBlock {
  final String text;
  final Rect boundingBox;

  RecognizedTextBlock({required this.text, required this.boundingBox});

  factory RecognizedTextBlock.fromMap(Map<dynamic, dynamic> map) {
    final rectMap = map['rect'] as Map<dynamic, dynamic>;
    return RecognizedTextBlock(
      text: map['text'] as String,
      boundingBox: Rect.fromLTWH(
        (rectMap['x'] as num).toDouble(),
        (rectMap['y'] as num).toDouble(),
        (rectMap['width'] as num).toDouble(),
        (rectMap['height'] as num).toDouble(),
      ),
    );
  }
}

class LiveTextService {
  static const _channel = MethodChannel('immich/local_ocr');
  static final _log = Logger('LiveTextService');

  /// Runs OCR asynchronously on the provided image bytes
  static Future<List<RecognizedTextBlock>?> recognizeTextBlocks(Uint8List imageBytes, {int accuracy = 0}) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('recognizeTextBlocks', {
        'data': imageBytes,
        'accuracy': accuracy,
      });

      if (result == null) return null;

      return result.map((e) => RecognizedTextBlock.fromMap(e as Map<dynamic, dynamic>)).toList();
    } on PlatformException catch (e) {
      _log.warning('LiveTextService OCR failed: ${e.message}');
      return null;
    } catch (e) {
      _log.warning('LiveTextService unknown error: $e');
      return null;
    }
  }
}
