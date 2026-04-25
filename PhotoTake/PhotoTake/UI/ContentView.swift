import SwiftUI

struct ContentView: View {
    @StateObject private var galleryStore = GalleryStore()
    // Single shared CIContext backed by Metal — created once, never per-frame
    private let ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)

    var body: some View {
        TabView {
            NavigationStack {
                ScanView(ciContext: ciContext)
                    .navigationTitle("PhotoTake")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(DS.Color.background, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .tabItem {
                Label("Scan", systemImage: "viewfinder")
            }

            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
        }
        .environmentObject(galleryStore)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
    }
}
