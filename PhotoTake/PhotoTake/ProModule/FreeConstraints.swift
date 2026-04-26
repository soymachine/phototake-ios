import CoreImage
import UIKit

// Helpers for free-tier image constraints, safe to call from any thread.

extension CIImage {
    /// Scales the image down so its longest side ≤ maxPx. No-op if already smaller.
    func limited(to maxPx: CGFloat) -> CIImage {
        let longest = max(extent.width, extent.height)
        guard longest > maxPx else { return self }
        let scale = maxPx / longest
        return transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}

enum Watermark {
    /// Burns a subtle "PhotoTake" text into the bottom-right corner.
    static func apply(to image: UIImage) -> UIImage {
        let text = "PhotoTake"
        let fontSize = max(image.size.width, image.size.height) * 0.032
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.38)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let strSize = str.size()
        let margin = image.size.width * 0.04

        return UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(at: .zero)
            str.draw(at: CGPoint(
                x: image.size.width  - strSize.width  - margin,
                y: image.size.height - strSize.height - margin
            ))
        }
    }
}
