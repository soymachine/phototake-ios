import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var store: GalleryStore
    @State private var selectedItem: GalleryItem?
    @State private var showingDetail = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(store.items) { item in
                            ThumbnailCell(item: item)
                                .onTapGesture {
                                    selectedItem = item
                                    showingDetail = true
                                }
                        }
                    }
                }
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingDetail) {
            if let item = selectedItem {
                GalleryDetailView(item: item)
                    .environmentObject(store)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(DS.Color.textSecondary)
            Text("No scans yet")
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textSecondary)
            Text("Tap the shutter button to scan\nyour first document or photo")
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ThumbnailCell: View {
    let item: GalleryItem

    var body: some View {
        GeometryReader { geo in
            Group {
                if let data = item.thumbData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    DS.Color.surface
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct GalleryDetailView: View {
    let item: GalleryItem
    @EnvironmentObject var store: GalleryStore
    @Environment(\.dismiss) var dismiss
    // Pre-loaded with thumbnail so first render is never blank
    @State private var displayImage: UIImage?
    @State private var showShareSheet = false

    init(item: GalleryItem) {
        self.item = item
        self._displayImage = State(initialValue: item.thumbData.flatMap { UIImage(data: $0) })
    }

    var body: some View {
        NavigationStack {
            // Color.black has a definite size inside NavigationStack;
            // overlay inherits that size so scaledToFit always has a reference.
            DS.Color.background.ignoresSafeArea()
                .overlay {
                    if let img = displayImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(DS.Spacing.md)
                    } else {
                        ProgressView().tint(DS.Color.accent)
                    }
                }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DS.Color.accent)
                        .font(DS.Font.mono)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive, action: {
                            store.delete(item)
                            dismiss()
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(DS.Color.accent)
                    }
                }
            }
        }
        .task {
            let url = item.fullResURL
            let loaded: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }.value
            if let loaded { displayImage = loaded }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = displayImage { ShareSheet(items: [img]) }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
