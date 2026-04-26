import Photos
import CoreImage
import UIKit

enum ExportController {
    static func saveToPhotos(_ image: CIImage,
                             context: CIContext,
                             completion: @escaping (Bool, Error?) -> Void) {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            completion(false, ExportError.renderFailed)
            return
        }
        saveToPhotos(UIImage(cgImage: cgImage), completion: completion)
    }

    static func saveToPhotos(_ image: UIImage,
                             completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false, ExportError.permissionDenied) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { ok, error in
                DispatchQueue.main.async { completion(ok, error) }
            }
        }
    }

    static func makeShareImage(_ image: CIImage, context: CIContext) -> UIImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

enum ExportError: LocalizedError {
    case renderFailed, permissionDenied
    var errorDescription: String? {
        switch self {
        case .renderFailed: return "Failed to render image"
        case .permissionDenied: return "Photo library access denied"
        }
    }
}
