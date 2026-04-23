import 'package:flutter/foundation.dart';

/// Represents a block of text recognized from an image by the OCR system.
///
/// This model contains both the recognized text content and its bounding box
/// coordinates in normalized format (0.0 to 1.0 relative to image dimensions).
///
/// ## Bounding Box Format
///
/// The [boundingBox] is a list of 8 doubles representing the four corners
/// of the text region in clockwise order starting from top-left:
///
/// ```
/// [x1, y1, x2, y2, x3, y3, x4, y4]
///   ^    ^    ^    ^    ^    ^    ^    ^
///  TL   TR   BR   BL   TL   TR   BR   BL
/// ```
class RecognizedTextBlock {
  /// The recognized text string
  final String text;
  
  /// Confidence score for the text recognition (0.0 to 1.0)
  final double confidence;
  
  /// Bounding box coordinates in normalized format.
  ///
  /// Format: [x1, y1, x2, y2, x3, y3, x4, y4]
  /// where (x, y) are the four corners of the text region in clockwise order
  /// starting from top-left.
  final List<double> boundingBox;
  
  /// The text region index for this block
  final int regionIndex;
  
  /// Creates a new [RecognizedTextBlock].
  ///
  /// - [text]: The recognized text string.
  /// - [confidence]: Confidence score between 0.0 and 1.0.
  /// - [boundingBox]: List of 8 normalized coordinates (x, y pairs for 4 corners).
  /// - [regionIndex]: Index identifying which region this belongs to.
  RecognizedTextBlock({
    required this.text,
    required this.confidence,
    required this.boundingBox,
    required this.regionIndex,
  }) : assert(
          boundingBox.length == 8,
          'Bounding box must contain exactly 8 coordinates (x1, y1, x2, y2, x3, y3, x4, y4)',
        );
  
  /// Creates a [RecognizedTextBlock] from JSON data.
  ///
  /// Expected format:
  /// {
  ///   'text': String,
  ///   'score': double,
  ///   'x1': double, 'y1': double,
  ///   'x2': double, 'y2': double,
  ///   'x3': double, 'y3': double,
  ///   'x4': double, 'y4': double
  /// }
  factory RecognizedTextBlock.fromJson(Map<String, dynamic> json) {
    return RecognizedTextBlock(
      text: json['text'] as String,
      confidence: (json['score'] as num?)?.toDouble() ?? 0.0,
      boundingBox: [
        json['x1'] as double,
        json['y1'] as double,
        json['x2'] as double,
        json['y2'] as double,
        json['x3'] as double,
        json['y3'] as double,
        json['x4'] as double,
        json['y4'] as double,
      ],
      regionIndex: 0, // Will be set by the OCR service
    );
  }
  
  /// Converts this [RecognizedTextBlock] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'score': confidence,
      'x1': boundingBox[0],
      'y1': boundingBox[1],
      'x2': boundingBox[2],
      'y2': boundingBox[3],
      'x3': boundingBox[4],
      'y3': boundingBox[5],
      'x4': boundingBox[6],
      'y4': boundingBox[7],
    };
  }
  
  /// Creates a copy of this [RecognizedTextBlock] with updated fields.
  RecognizedTextBlock copyWith({
    String? text,
    double? confidence,
    List<double>? boundingBox,
    int? regionIndex,
  }) {
    return RecognizedTextBlock(
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      boundingBox: boundingBox ?? this.boundingBox,
      regionIndex: regionIndex ?? this.regionIndex,
    );
  }
  
  @override
  String toString() => 'RecognizedTextBlock(text: $text, confidence: $confidence)';
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecognizedTextBlock &&
        other.text == text &&
        other.confidence == confidence &&
        listEquals(other.boundingBox, boundingBox);
  }
  
  @override
  int get hashCode => Object.hash(text, confidence, Object.hashAll(boundingBox));
}
