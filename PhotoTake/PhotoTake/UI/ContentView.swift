import SwiftUI
import Metal

struct ContentView: View {
    @StateObject private var galleryStore = GalleryStore()
    @StateObject private var proStore    = ProStore()
    private let ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)

    var body: some View {
        NavigationStack {
            ScanView(ciContext: ciContext)
        }
        .environmentObject(galleryStore)
        .environmentObject(proStore)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
    }
}
