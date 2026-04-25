import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var store: GalleryStore
    @State private var selectedItem: GalleryItem?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ZStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.items) { item in
                                ThumbnailCell(item: item)
                                    .onTapGesture { selectedItem = item }
                            }
                        }
                    }
                }
            }
            .background(DS.Color.background.ignoresSafeArea())

            // Inline detail overlay — no sheet, no NavigationStack
            if let item = selectedItem {
                GalleryDetailOverlay(item: item, onDismiss: { selectedItem = nil })
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedItem?.id)
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Hide nav bar while detail is open so our custom bar is the only chrome
        .toolbar(selectedItem == nil ? .visible : .hidden, for: .navigationBar)
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

// MARK: - Thumbnail cell

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

// MARK: - Detail overlay (inline, no sheet)

struct GalleryDetailOverlay: View {
    let item: GalleryItem
    let onDismiss: () -> Void

    @EnvironmentObject var store: GalleryStore
    @State private var fullResImage: UIImage? = nil
    @State private var showShareSheet = false

    // Thumbnail decoded directly from in-memory Data — always available synchronously.
    // fullResImage replaces it once the background load completes.
    private var shownImage: UIImage? {
        fullResImage ?? item.thumbData.flatMap { UIImage(data: $0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.background.ignoresSafeArea()

            if let img = shownImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.2), value: fullResImage != nil)
            } else {
                ProgressView()
                    .tint(DS.Color.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Top bar
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Gallery")
                        .font(DS.Font.mono)
                }
                .foregroundStyle(DS.Color.accent)
                .padding(.leading, 16)

                Spacer()

                Menu {
                    Button(action: { showShareSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive, action: {
                        store.delete(item)
                        onDismiss()
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 22))
                        .padding(.trailing, 20)
                }
            }
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
        .task {
            guard fullResImage == nil else { return }
            let url = item.fullResURL
            let loaded: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }.value
            if let loaded { fullResImage = loaded }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shownImage { ShareSheet(items: [img]) }
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
