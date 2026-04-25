import CoreImage

enum PerspectiveCorrector {
    // quad: [TL, TR, BR, BL] in CIImage pixel coords (origin bottom-left)
    static func correct(image: CIImage, quad: [CGPoint]) -> CIImage? {
        guard quad.count == 4,
              let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: quad[0]), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: quad[1]), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: quad[3]), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: quad[2]), forKey: "inputBottomRight")
        return filter.outputImage
    }

    // Convert view-space corners (UIKit, origin top-left) to CIImage pixel coords
    // imageSize: actual pixel dimensions of the CIImage
    // viewSize: SwiftUI view dimensions used for the overlay
    static func viewCornersToImagePixels(
        corners: [CGPoint],
        viewSize: CGSize,
        imageSize: CGSize
    ) -> [CGPoint] {
        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height
        return corners.map { pt in
            // UIKit Y is flipped relative to CIImage
            CGPoint(x: pt.x * scaleX,
                    y: imageSize.height - pt.y * scaleY)
        }
    }

    // Convert VNRectangleObservation (normalized, origin bottom-left) to view coords (origin top-left)
    static func vnObservationToViewCorners(
        _ obs: any VNRectangleObservationProtocol,
        viewSize: CGSize
    ) -> [CGPoint] {
        // Order: TL, TR, BR, BL
        let vnPoints = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        return vnPoints.map { pt in
            CGPoint(x: pt.x * viewSize.width,
                    y: (1 - pt.y) * viewSize.height)
        }
    }
}

protocol VNRectangleObservationProtocol {
    var topLeft: CGPoint { get }
    var topRight: CGPoint { get }
    var bottomLeft: CGPoint { get }
    var bottomRight: CGPoint { get }
}

import Vision
extension VNRectangleObservation: VNRectangleObservationProtocol {}
