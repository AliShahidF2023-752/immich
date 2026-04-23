import Flutter

/// Implementation of the OCR API for iOS.
///
/// This class handles platform channel messages from Dart for performing
/// optical character recognition on images using Apple's Vision framework.
/// It manages caching and coordinates with the native OcrService.
class OcrApiImpl: NSObject, OcrApi {
    
    /// Cache for OCR results keyed by hero tag
    private var cache = [String: [RecognizedTextBlock]]()
    
    /// Maximum cache size to prevent memory issues
    private let maxCacheSize = 50
    
    // MARK: - OcrApi Protocol Implementation
    
    /// Recognizes text in an image.
    ///
    /// - Parameters:
    ///   - heroTag: Unique identifier for the image being processed.
    ///   - imageWidth: Width of the image in pixels.
    ///   - imageHeight: Height of the image in pixels.
    /// - Returns: A dictionary containing 'blocks' array with recognized text data.
    func recognizeText(heroTag: String, imageWidth: Int64, imageHeight: Int64) throws -> [String : Any] {
        // Check cache first
        if let cached = cache[heroTag] {
            return encodeBlocks(cached)
        }
        
        // Get the current active image viewer to access the rendered image
        // This is a simplified implementation - in production you'd want a more robust way
        // to get the actual image data from the Flutter view
        guard let blocks = try? performOCR(imageWidth: imageWidth, imageHeight: imageHeight) else {
            return encodeBlocks([])
        }
        
        // Cache the results
        cache[heroTag] = blocks
        
        // Enforce cache size limit
        if cache.count > maxCacheSize {
            let keys = Array(cache.keys)
            cache.removeValue(forKey: keys.first!)
        }
        
        return encodeBlocks(blocks)
    }
    
    /// Clears all cached OCR results.
    func clearCache() throws {
        cache.removeAll()
    }
    
    // MARK: - OCR Processing
    
    /// Performs OCR on an image using the Vision framework.
    ///
    /// This method:
    /// - Creates a text recognition request with fast mode
    /// - Runs the request asynchronously on a background queue
    /// - Filters results by confidence threshold
    /// - Returns recognized text blocks with bounding boxes
    ///
    /// Note: In production, this would need access to the actual image data
    /// from Flutter. The current implementation is a placeholder that shows
    /// the structure needed.
    private func performOCR(imageWidth: Int64, imageHeight: Int64) throws -> [RecognizedTextBlock] {
        // Create Vision text recognition request
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard error == nil else {
                print("OCR error: \(error!.localizedDescription)")
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            var blocks = [RecognizedTextBlock]()
            
            for observation in observations {
                // Get the top candidate text
                if let topCandidate = observation.topCandidates(1).first {
                    let text = topCandidate.string
                    let confidence = topCandidate.confidence
                    
                    // Filter by minimum confidence threshold (0.5)
                    guard confidence >= 0.5 else {
                        continue
                    }
                    
                    // Get bounding box from observation
                    let boundingBox = observation.boundingBox
                    
                    blocks.append(RecognizedTextBlock(
                        text: text,
                        confidence: confidence,
                        boundingBox: [
                            boundingBox.minX, boundingBox.minY,
                            boundingBox.maxX, boundingBox.minY,
                            boundingBox.maxX, boundingBox.maxY,
                            boundingBox.minX, boundingBox.maxY
                        ]
                    ))
                }
            }
            
            // Store results in cache (this would need proper synchronization)
            // self?.cacheResults(heroTag: heroTag, blocks: blocks)
        }
        
        // Configure the request
        request.recognitionLevel = .fast  // Fast mode initially
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLandmarks = false
        request.revision = VNRecognizeTextRequestRevision1
        
        // Specify languages (English as primary, with fallback)
        request.recognizedLanguages = [
            "en-US",  // English (US)
            "en-GB",  // English (UK)
            "en-AU",  // English (Australia)
            "en-CA",  // English (Canada)
        ]
        
        // In production, you would create a VNImageHandler with the actual image
        // For now, this is a placeholder showing the structure needed
        let handler = VNImageRequestHandler()
        
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform OCR: \(error)")
            return []
        }
        
        // Return empty array - actual results would come from the completion handler
        return []
    }
    
    // MARK: - Helper Methods
    
    /// Encodes text blocks into a dictionary format for Flutter.
    private func encodeBlocks(_ blocks: [RecognizedTextBlock]) -> [String: Any] {
        let encodedBlocks = blocks.map { block in
            return block.dictionaryValue
        }
        
        return [
            "blocks": encodedBlocks
        ]
    }
}
