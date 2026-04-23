 # OCR (Optical Character Recognition) Implementation

 This directory contains the iOS implementation of the OCR feature for the Immich mobile app, inspired by Apple's Live Text functionality.

 ## Overview

 The OCR system allows users to detect and interact with text in photos directly within the image viewer. When a photo is opened and fully loaded, the system automatically runs OCR in the background. If text is detected, a toggle button appears, allowing users to show/hide selectable text regions overlaid on the image.

 ## Architecture

 ### Components

 #### Swift (iOS Native)

 1. **OcrService.swift** - Core OCR service using Apple's Vision framework
    - Handles image preprocessing and downscaling
    - Manages OCR result caching
    - Performs asynchronous text recognition

 2. **OCROverlayView.swift** - Custom overlay view for displaying text regions
    - Draws bounding boxes around detected text
    - Synchronizes with PhotoView transform/scale
    - Handles touch detection on text blocks

 3. **OcrApiImpl.swift** - Pigeon platform channel implementation
    - Bridges Dart ↔ Swift communication
    - Handles OCR requests from Flutter layer
    - Manages caching of results

 #### Dart (Flutter Layer)

 1. **ocr_service.dart** - High-level OCR service
    - Debounces rapid image switching
    - Manages cache and result persistence
    - Provides async API for OCR operations

 2. **ocr_overlay.widget.dart** - Flutter widget for interactive overlays
    - Custom painter for text block rendering
    - Gesture handling for text selection
    - Integration with PhotoView transform system

 3. **recognized_text_block.dart** - Data model for OCR results
    - Represents detected text with bounding box coordinates
    - JSON serialization/deserialization support

 ## How It Works

 ### 1. Image Loading & OCR Trigger

 When an image is opened in the viewer:

 ```dart
 // asset_page.widget.dart
 void _resolveImageForOCR(BaseAsset asset) {
     final provider = getFullImageProvider(asset, size: context.sizeData);
     final newStream = provider.resolve(const ImageConfiguration());
     
     _ocrImageListener = ImageStreamListener((imageInfo, synchronousCall) async {
         // OCR runs after image is fully loaded
         final blocks = await ocrService.recognizeText(imageInfo.image, asset.heroTag);
         setState(() => _ocrBlocks = blocks);
     });
 }
 ```

 ### 2. OCR Processing (iOS)

 The `OcrService` performs:

 1. **Downscaling**: Large images are downscaled to max 2048px for faster processing
 2. **Text Recognition**: Uses `VNRecognizeTextRequest` with fast mode
 3. **Confidence Filtering**: Only accepts results above 50% confidence
 4. **Caching**: Results cached by image hash to avoid re-processing

 ### 3. Overlay Display

 When the user toggles OCR overlay:

 ```dart
 if (_showOcrOverlay) {
     OcrOverlayWidget(
         blocks: _ocrBlocks,
         imageSize: _loadedImageSize!,
         controller: _viewController!,
     )
 }
 ```

 The `OCROverlayView` synchronizes with PhotoView's transform to ensure accurate placement of text regions during zoom and pan operations.

 ## Features

 ### ✅ Implemented

 - **Automatic OCR**: Triggers when image is fully loaded
 - **Caching**: Results cached per-image to avoid re-processing
 - **Debouncing**: Prevents excessive OCR calls during rapid navigation
 - **Live Text UI**: Toggle button appears only when text detected
 - **Transform Sync**: Bounding boxes stay aligned during zoom/pan
 - **Text Selection**: Tap on blocks to copy text
 - **On-device Processing**: No external API calls, fully private

 ### 📋 Future Enhancements

 - Multi-language detection (beyond English variants)
 - Accurate mode fallback for low-confidence results
 - Export OCR results to file
 - Search within OCR results
 - Manual trigger option in settings

 ## Configuration

 ### Confidence Threshold

 Minimum confidence score: `0.5` (50%)

 ```swift
 private static let minConfidence: Double = 0.5
 ```

 ### Max Resolution

 Images larger than 2048px are downscaled:

 ```swift
 private static let maxOcrResolution: Int = 2048
 ```

 ### Supported Languages

 - English (US, UK, Australia, Canada)

 ## Performance Considerations

 1. **Background Processing**: OCR runs on background queue, never blocks UI
 2. **Image Downscaling**: Large images downscaled before processing
 3. **Caching**: Results cached in memory with size limits
 4. **Debouncing**: 300ms delay for rapid image switching
 5. **Lazy Loading**: Only processes currently visible image

 ## Testing

 ### Manual Testing Checklist

 - [ ] Open photo with text → OCR runs automatically
 - [ ] Wait for toggle button to appear (if text detected)
 - [ ] Tap toggle button → bounding boxes appear
 - [ ] Zoom/pan image → boxes stay aligned
 - [ ] Tap text block → copy dialog appears
 - [ ] Toggle OFF → overlay removed
 - [ ] Navigate between images → caching works
 - [ ] Open same image again → uses cache

 ### Edge Cases Handled

 - No text detected → no button shown
 - Low confidence results → filtered out
 - Very large images → downscale before OCR
 - Rapid navigation → debounced OCR calls

 ## Privacy & Security

 - **100% on-device processing** - No image data leaves the device
 - **No external API calls** - All processing done with Vision framework
 - **Cleared cache on demand** - `clearCache()` method available

 ## Files

 ```
 mobile/ios/Runner/Ocr/
 ├── OcrService.swift          # Core OCR service (Vision framework)
 ├── OCROverlayView.swift      # Custom overlay view
 ├── OcrApiImpl.swift          # Pigeon platform channel
 └── README.md                 # This file
 ```

 ## Integration

 The OCR feature is integrated into the asset viewer (`asset_page.widget.dart`) and adds:

 1. Automatic OCR trigger on image load
 2. Toggle button in bottom-right corner (when text detected)
 3. Interactive overlay with selectable text regions

 ```dart
 // In asset_page.widget.dart
 bool _showOcrOverlay = false;
 List<RecognizedTextBlock> _ocrBlocks = [];
 Size? _loadedImageSize;

 void _resolveImageForOCR(BaseAsset asset) {
     // Triggers OCR when image is fully loaded
 }

 // Toggle button in UI
 IconButton(
     icon: Icon(Icons.text_fields, color: _showOcrOverlay ? Colors.blue : Colors.white),
     onPressed: () => setState(() => _showOcrOverlay = !_showOcrOverlay)
 )

 // Overlay widget
 if (_showOcrOverlay) OcrOverlayWidget(...)
 ```
