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
      
    case "recognizeTextBlocks":
      guard
        let args = call.arguments as? [String: Any],
        let data = args["data"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "data is required", details: nil))
        return
      }
      let accuracyIdx = args["accuracy"] as? Int ?? 1
      OCRService.recognizeText(from: data.data, accuracyIdx: accuracyIdx) { response in
          DispatchQueue.main.async {
              switch response {
              case .success(let blocks):
                  let blocksArray = blocks.map { block -> [String: Any] in
                      return [
                          "text": block.text,
                          "rect": [
                              "x": block.boundingBox.origin.x,
                              "y": block.boundingBox.origin.y,
                              "width": block.boundingBox.size.width,
                              "height": block.boundingBox.size.height
                          ]
                      ]
                  }
                  result(blocksArray)
              case .failure(let error):
                  result(FlutterError(code: "OCR_PERFORM_ERROR", message: error.localizedDescription, details: nil))
              }
          }
      }

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
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
          result(FlutterError(code: "IMAGE_NOT_FOUND", message: "Cannot load image at path", details: nil))
          return
      }
      OCRService.recognizeText(from: data, accuracyIdx: accuracyIdx) { response in
          DispatchQueue.main.async {
              switch response {
              case .success(let blocks):
                  let text = blocks.map { $0.text }.joined(separator: "\n")
                  result(text)
              case .failure(let error):
                  result(FlutterError(code: "OCR_PERFORM_ERROR", message: error.localizedDescription, details: nil))
              }
          }
      }
  }
}
