import Flutter
import UIKit
import Vision

/// Flutter MethodChannel handler that exposes iOS Vision framework text
/// recognition (VNRecognizeTextRequest) to the Dart layer.
///
/// Channel name: `immich/local_ocr`
/// Methods:
///   - `recognizeText({ path: String, accuracy: Int }) → String`
///     Runs VNRecognizeTextRequest on the image at `path` and returns the
///     concatenated extracted text (newlines between blocks).
///     `accuracy`: 0=fast, 1=accurate (maps to VNRequestTextRecognitionLevel).
class LocalOcrChannel: NSObject, FlutterPlugin {
  static let channelName = "immich/local_ocr"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = LocalOcrChannel()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "recognizeText":
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "path is required", details: nil))
        return
      }
      let accuracyIdx = args["accuracy"] as? Int ?? 1
      recognizeText(at: path, accuracyIdx: accuracyIdx, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  private func recognizeText(
    at path: String,
    accuracyIdx: Int,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .utility).async {
      guard let image = UIImage(contentsOfFile: path),
            let cgImage = image.cgImage
      else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "IMAGE_NOT_FOUND",
              message: "Cannot load image at path: \(path)",
              details: nil
            )
          )
        }
        return
      }

      let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

      let level: VNRequestTextRecognitionLevel = accuracyIdx == 0 ? .fast : .accurate

      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "OCR_ERROR",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
          return
        }

        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        let text = observations
          .compactMap { $0.topCandidates(1).first?.string }
          .joined(separator: "\n")

        DispatchQueue.main.async {
          result(text)
        }
      }

      request.recognitionLevel = level
      request.usesLanguageCorrection = true

      do {
        try requestHandler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "OCR_PERFORM_ERROR",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }
}
