import Vision
import CoreImage

final class RectangleDetector {
    private let request: VNDetectRectanglesRequest = {
        let r = VNDetectRectanglesRequest()
        r.minimumConfidence = 0.8
        r.minimumAspectRatio = 0.3
        r.maximumObservations = 1
        return r
    }()

    private let queue = DispatchQueue(label: "rectangle.detection", qos: .userInitiated)

    func detect(in pixelBuffer: CVPixelBuffer,
                completion: @escaping (VNRectangleObservation?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                               orientation: .up)
            try? handler.perform([self.request])
            let result = self.request.results?.first
            DispatchQueue.main.async { completion(result) }
        }
    }

    // Convert normalized Vision coords to pixel coords in CIImage space
    static func vnToPixel(_ pt: CGPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(x: pt.x * imageSize.width,
                y: (1 - pt.y) * imageSize.height)
    }

    // Convert normalized Vision coords to UIKit/SwiftUI view coords
    static func vnToView(_ pt: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(x: pt.x * viewSize.width,
                y: (1 - pt.y) * viewSize.height)
    }

    // Convert view coords back to normalized Vision coords
    static func viewToVN(_ pt: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(x: pt.x / viewSize.width,
                y: 1 - (pt.y / viewSize.height))
    }
}
