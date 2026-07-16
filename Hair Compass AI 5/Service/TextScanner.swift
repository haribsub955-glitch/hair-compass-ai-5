import Foundation
import UIKit
@preconcurrency import Vision

/// On-device text recognition via Apple's **Vision** framework — reads the printed text off a
/// photo with no network and nothing leaving the device. Used to pull the visible text from an
/// ingredient label (or a lab printout) instantly and privately, before any optional cloud call.
enum TextScanner {

    /// Recognizes printed text in `image`, returning the lines joined by newlines (empty when
    /// nothing is found or recognition fails). Runs Vision's accurate path off the main thread.
    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.cgImagePropertyOrientation,
                options: [:]
            )
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

extension UIImage {
    /// Maps `UIImage.Orientation` to the `CGImagePropertyOrientation` Vision expects, so text is
    /// read the right way up regardless of how the photo was captured.
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
