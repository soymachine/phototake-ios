import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var store: GalleryStore
    @State private var selectedItem: GalleryItem?
    @State private var showingDetail = false

    let columns = [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 2)]

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingDetail) {
            if let item = selectedItem {
                GalleryDetailView(item: item)
                    .environmentObject(store)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No scans yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Scan a document or negative to get started")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
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
                    Rectangle().fill(Color.secondary.opacity(0.2))
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
    @State private var image: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let img = image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
                    }
                }
            }
        }
        .task {
            if let data = try? Data(contentsOf: item.fullResURL) {
                image = UIImage(data: data)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = image {
                ShareSheet(items: [img])
            }
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
