import Foundation
import Vision
import UIKit

/// Model representing a recognized text block along with its bounding box
public struct RecognizedTextBlock: Codable {
    public let text: String
    public let boundingBox: CGRect // Normalized coordinates (0..1)
}

/// Dedicated service for performing on-device OCR using Apple's Vision framework
public class OCRService {
    
    /// Performs text recognition on the given image path.
    ///
    /// - Parameters:
    ///   - path: The file path to the image.
    ///   - accuracyIdx: 0 for fast mode, 1 for accurate mode.
    ///   - completion: Completion block with the recognized text blocks or an error.
    public static func recognizeText(
        from imageData: Data,
        accuracyIdx: Int,
        completion: @escaping (Result<[RecognizedTextBlock], Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = UIImage(data: imageData),
                  let cgImage = image.cgImage else {
                let error = NSError(domain: "OCRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot decode image data"])
                completion(.failure(error))
                return
            }
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let level: VNRequestTextRecognitionLevel = accuracyIdx == 0 ? .fast : .accurate
            
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var blocks = [RecognizedTextBlock]()
                
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first,
                          candidate.confidence >= 0.5 else { continue }
                    
                    // The bounding box is in normalized coordinates (0..1), with origin at bottom-left
                    // We flip the y-axis to match typical top-left UI coordinate systems
                    let flippedBox = CGRect(
                        x: observation.boundingBox.minX,
                        y: 1.0 - observation.boundingBox.maxY,
                        width: observation.boundingBox.width,
                        height: observation.boundingBox.height
                    )
                    
                    let block = RecognizedTextBlock(
                        text: candidate.string,
                        boundingBox: flippedBox
                    )
                    blocks.append(block)
                }
                
                completion(.success(blocks))
            }
            
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            // Support multi-language detection
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }
            request.recognitionLanguages = ["en-US", "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR", "zh-Hans", "ja-JP", "ko-KR"]
            
            do {
                try requestHandler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
}
