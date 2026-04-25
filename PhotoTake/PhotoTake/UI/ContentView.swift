import SwiftUI
import Metal

struct ContentView: View {
    @StateObject private var galleryStore = GalleryStore()
    private let ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)

    var body: some View {
        NavigationStack {
            ScanView(ciContext: ciContext)
        }
        .environmentObject(galleryStore)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
    }
}
