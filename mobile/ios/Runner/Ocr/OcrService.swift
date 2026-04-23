import Vision

/// Represents a single block of recognized text with its bounding box.
///
/// This struct is used to store OCR results including the detected text,
/// confidence score, and normalized bounding box coordinates.
///
/// ## Bounding Box Format
///
/// The `boundingBox` contains 8 values representing the four corners
/// of the text region in clockwise order starting from top-left:
///
/// ```
/// [x1, y1, x2, y2, x3, y3, x4, y4]
///   ^    ^    ^    ^    ^    ^    ^    ^
///  TL   TR   BR   BL   TL   TR   BR   BL
/// ```
///
struct RecognizedTextBlock: Equatable {
    /// The recognized text string
    let text: String
    
    /// Confidence score for the recognition (0.0 - 1.0)
    let confidence: Double
    
    /// Bounding box in normalized coordinates (0.0 - 1.0)
    /// Format: [x1, y1, x2, y2, x3, y3, x4, y4]
    /// Where corners are ordered: top-left, top-right, bottom-right, bottom-left
    let boundingBox: [Double]
}

extension RecognizedTextBlock {
    /// Converts the text block to a dictionary for Flutter compatibility.
    var dictionaryValue: [String: Any] {
        return [
            "text": text,
            "score": confidence,
            "x1": boundingBox[0], "y1": boundingBox[1],
            "x2": boundingBox[2], "y2": boundingBox[3],
            "x3": boundingBox[4], "y3": boundingBox[5],
            "x4": boundingBox[6], "y4": boundingBox[7]
        ]
    }
}

/// OCR Service that uses Apple's Vision framework for on-device text recognition.
/// All processing is done locally with no external API calls.
class OcrService {
    /// Shared singleton instance
    static let shared = OcrService()
    
    private init() {}
    
    /// Cache for OCR results, keyed by image hash
    private let resultCache = NSCache<NSString, [RecognizedTextBlock]>()
    
    /// Maximum resolution to use for OCR processing (downscale larger images)
    private static let maxOcrResolution: Int = 2048
    
    /// Minimum confidence threshold for accepting recognized text
    private static let minConfidence: Double = 0.5
    
    /// Performs OCR on the given image and returns recognized text blocks.
    ///
    /// - Parameters:
    ///   - cgImage: The Core Graphics image to analyze
    ///   - imageHash: A unique hash for the image (used for caching)
    /// - Returns: Array of recognized text blocks, sorted by vertical position
    func recognizeText(in cgImage: CGImage, imageHash: String) async -> [RecognizedTextBlock] {
        // Check cache first
        if let cachedResult = resultCache.object(forKey: imageHash as NSString) {
            return cachedResult
        }
        
        // Downscale image for OCR if needed
        let processedImage = await downscaleImage(cgImage, maxDimension: Self.maxOcrResolution)
        
        // Perform text recognition using Vision framework
        let results = await performTextRecognition(on: processedImage)
        
        // Cache the results
        resultCache.setObject(results, forKey: imageHash as NSString)
        
        return results
    }
    
    /// Downscale an image to fit within the specified maximum dimension.
    private func downscaleImage(_ cgImage: CGImage, maxDimension: Int) -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        
        // No scaling needed if image is already small enough
        if width <= maxDimension && height <= maxDimension {
            return cgImage
        }
        
        let scale = min(maxDimension / CGFloat(width), maxDimension / CGFloat(height))
        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)
        
        guard let colorSpace = cgImage.colorSpace else {
            return cgImage
        }
        
        // Create bitmap context
        let bitsPerComponent = cgImage.bitsPerComponent
        let bitsPerPixel = cgImage.bitsPerPixel
        
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else {
            return cgImage
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        guard let downscaledImage = context.makeImage() else {
            return cgImage
        }
        
        return downscaledImage
    }
    
    /// Performs text recognition on the given image using Vision framework.
    private func performTextRecognition(on cgImage: CGImage) async -> [RecognizedTextBlock] {
        var results: [RecognizedTextBlock] = []
        
        // Create text recognition request with fast mode first
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard error == nil else {
                print("OCR Error: \(error!.localizedDescription)")
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            var blocks: [RecognizedTextBlock] = []
            
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else {
                    continue
                }
                
                let text = topCandidate.string
                let confidence = topCandidate.confidence
                
                // Filter by confidence threshold
                guard confidence >= Self.minConfidence else {
                    continue
                }
                
                // Get bounding box in image coordinates
                let boundingBox = self?.getBoundingBox(from: observation, cgImage: cgImage) ?? []
                
                blocks.append(RecognizedTextBlock(
                    text: text,
                    confidence: confidence,
                    boundingBox: boundingBox
                ))
            }
            
            // Sort by vertical position (y-coordinate of top-left corner)
            results = blocks.sorted { $0.boundingBox[1] < $1.boundingBox[1] }
        }
        
        // Configure request for fast mode initially
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        
        // Specify languages (English as primary, with fallback to others)
        request.recognizedLanguages = ["en-US", "en-GB"]
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try await requestHandler.perform([request])
        } catch {
            print("Failed to perform text recognition: \(error.localizedDescription)")
        }
        
        return results
    }
    
    /// Converts Vision bounding box coordinates to normalized image coordinates.
    private func getBoundingBox(from observation: VNRecognizedTextObservation, cgImage: CGImage) -> [Double] {
        // Get the bounding box in image coordinates (normalized 0-1)
        let rect = observation.boundingBox
        
        // Convert from image coordinate system (bottom-left origin) to standard (top-left origin)
        // Vision uses normalized coordinates where (0,0) is bottom-left
        let x1 = Double(rect.minX)
        let y1 = Double(1.0 - rect.maxY)  // top-left corner
        let x2 = Double(rect.maxX)
        let y2 = Double(1.0 - rect.maxY)  // top-right corner
        let x3 = Double(rect.maxX)
        let y3 = Double(1.0 - rect.minY)  // bottom-right corner
        let x4 = Double(rect.minX)
        let y4 = Double(1.0 - rect.minY)  // bottom-left corner
        
        return [x1, y1, x2, y2, x3, y3, x4, y4]
    }
    
    /// Clears the OCR result cache.
    func clearCache() {
        resultCache.removeAllObjects()
    }
}
