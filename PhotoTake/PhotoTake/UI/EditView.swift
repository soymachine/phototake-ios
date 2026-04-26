import SwiftUI
import CoreImage

struct EditView: View {
    let capturedImage: CIImage
    let ciContext: CIContext
    @EnvironmentObject var galleryStore: GalleryStore
    @Environment(\.dismiss) var dismiss

    @State private var adjustments: Adjustments
    @State private var previewUIImage: UIImage?
    @State private var showShareSheet = false
    @State private var saveState: SaveState = .idle
    @State private var saveQuality: SaveQuality = .high
    @State private var showGallery = false

    private enum SaveState { case idle, saving, saved }
    private enum SaveQuality: String, CaseIterable {
        case high = "HIGH"
        case medium = "MED"
        var compression: CGFloat { self == .high ? 0.92 : 0.65 }
    }

    init(capturedImage: CIImage, ciContext: CIContext,
         initialAdjustments: Adjustments = .default) {
        self.capturedImage = capturedImage
        self.ciContext = ciContext
        self._adjustments = State(initialValue: initialAdjustments)
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                imagePreview.frame(maxHeight: .infinity)
                controlsPanel
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { shareButton }
        }
        .navigationDestination(isPresented: $showGallery) { GalleryView() }
        .task(id: adjustments) { await updatePreview() }
        .sheet(isPresented: $showShareSheet) {
            if let img = previewUIImage { ShareSheet(items: [img]) }
        }
    }

    // MARK: - Preview

    private var imagePreview: some View {
        GeometryReader { geo in
            Group {
                if let ui = previewUIImage {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView().tint(DS.Color.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(DS.Spacing.md)
    }

    private func updatePreview() async {
        let adj = adjustments
        let src = capturedImage
        let ctx = ciContext
        let img: UIImage? = await Task.detached {
            let processed = AdjustmentPipeline.apply(src, adj: adj)
            guard let cg = ctx.createCGImage(processed, from: processed.extent) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        previewUIImage = img
    }

    // MARK: - Controls panel

    private var controlsPanel: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                saveRow

                HStack(spacing: DS.Spacing.sm) {
                    toggleButton(label: "INVERT", systemImage: "circle.lefthalf.filled",
                                 isOn: $adjustments.invert)
                    toggleButton(label: "B/W", systemImage: "camera.filters",
                                 isOn: $adjustments.blackAndWhite)
                }

                Divider().background(DS.Color.surfaceSecondary)

                SliderRow(label: "Brightness", systemImage: "sun.max",
                          value: $adjustments.brightness, range: -1...1)
                SliderRow(label: "Contrast",
                          systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal",
                          value: $adjustments.contrast, range: 0.5...2.0)
                SliderRow(label: "Saturation", systemImage: "paintpalette",
                          value: $adjustments.saturation, range: 0...2.0)

                Button(action: { adjustments = .default }) {
                    Text("RESET")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
                }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.Color.surface)
        .frame(maxHeight: 280)
    }

    // MARK: - Save row

    private var saveRow: some View {
        Group {
            switch saveState {
            case .idle:
                VStack(spacing: DS.Spacing.xs) {
                    // Quality picker
                    HStack(spacing: 0) {
                        ForEach(SaveQuality.allCases, id: \.self) { q in
                            Button(action: { saveQuality = q }) {
                                Text(q.rawValue)
                                    .font(DS.Font.monoCaption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(saveQuality == q ? DS.Color.accent : DS.Color.surface)
                                    .foregroundStyle(saveQuality == q ? DS.Color.background : DS.Color.textSecondary)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
                    .overlay(RoundedRectangle(cornerRadius: DS.Corner.sm).stroke(DS.Color.surfaceSecondary, lineWidth: 1))

                    // Save button
                    Button(action: saveToGallery) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save").font(DS.Font.mono)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.surfaceSecondary)
                        .foregroundStyle(DS.Color.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
                    }
                }

            case .saving:
                HStack {
                    ProgressView().tint(DS.Color.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))

            case .saved:
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Saved").font(DS.Font.mono)
                    }
                    .foregroundStyle(DS.Color.accent)

                    Spacer()

                    Button(action: { showGallery = true }) {
                        HStack(spacing: 6) {
                            Text("Gallery").font(DS.Font.mono)
                            Image(systemName: "photo.stack")
                        }
                        .foregroundStyle(DS.Color.background)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, 6)
                        .background(DS.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: saveState == .idle)
    }

    private func toggleButton(label: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: systemImage)
                Text(label).font(DS.Font.mono)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(isOn.wrappedValue ? DS.Color.accent : DS.Color.surfaceSecondary)
            .foregroundStyle(isOn.wrappedValue ? DS.Color.background : DS.Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
        }
    }

    // MARK: - Actions

    private var shareButton: some View {
        Button(action: { showShareSheet = true }) {
            Image(systemName: "square.and.arrow.up").foregroundStyle(DS.Color.accent)
        }
        .disabled(previewUIImage == nil)
    }

    private func saveToGallery() {
        saveState = .saving
        let processed = AdjustmentPipeline.apply(capturedImage, adj: adjustments)
        galleryStore.save(image: processed, context: ciContext, quality: saveQuality.compression)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            saveState = .saved
        }
    }
}

