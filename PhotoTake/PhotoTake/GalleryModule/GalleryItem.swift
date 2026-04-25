import Foundation

struct GalleryItem: Identifiable, Codable {
    let id: String
    let thumbData: Data?
    let fullResURL: URL
    let date: Date
}
