import CoreImage
import SwiftUI

@MainActor
final class GalleryStore: ObservableObject {
    @Published var items: [GalleryItem] = []
    @Published var saveError: Error?

    private let dir: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gallery", isDirectory: true)
    }()

    private let manifestURL: URL

    init() {
        manifestURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gallery/manifest.json")
        load()
    }

    func save(image: CIImage, context: CIContext) {
        let capturedDir = self.dir
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: capturedDir,
                                                        withIntermediateDirectories: true)
                let id = UUID().uuidString
                let url = capturedDir.appendingPathComponent("\(id).jpg")

                // Render via CGImage then UIImage — more reliable than heifRepresentation
                guard let cgImage = context.createCGImage(image, from: image.extent),
                      let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92)
                else { throw GalleryError.encodingFailed }

                try data.write(to: url)
                let thumbData = GalleryStore.makeThumbnail(image: image, context: context, maxPx: 400)
                let item = GalleryItem(id: id, thumbData: thumbData, fullResURL: url, date: .now)

                await MainActor.run {
                    self.items.insert(item, at: 0)
                    try? self.persist()
                }
            } catch {
                await MainActor.run { self.saveError = error }
            }
        }
    }

    func delete(_ item: GalleryItem) {
        try? FileManager.default.removeItem(at: item.fullResURL)
        items.removeAll { $0.id == item.id }
        try? persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([GalleryItem].self, from: data)
        else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.fullResURL.path) }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: manifestURL)
    }

    nonisolated private static func makeThumbnail(image: CIImage, context: CIContext, maxPx: CGFloat) -> Data? {
        let extent = image.extent
        let scale = min(maxPx / extent.width, maxPx / extent.height, 1)
        let thumb = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(thumb, from: thumb.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.75)
    }
}

enum GalleryError: LocalizedError {
    case encodingFailed
    var errorDescription: String? { "Failed to encode image" }
}
