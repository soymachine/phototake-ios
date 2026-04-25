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
    @State private var shareImage: UIImage?
    @State private var saveSucceeded: Bool? = nil
    @State private var isSaving = false

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
            ToolbarItem(placement: .topBarTrailing) { saveButton }
        }
        .task(id: adjustments) { await updatePreview() }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage { ShareSheet(items: [img]) }
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
        Button(action: {
            let processed = AdjustmentPipeline.apply(capturedImage, adj: adjustments)
            shareImage = ExportController.makeShareImage(processed, context: ciContext)
            showShareSheet = true
        }) {
            Image(systemName: "square.and.arrow.up").foregroundStyle(DS.Color.accent)
        }
    }

    private var saveButton: some View {
        Button(action: saveToGallery) {
            if isSaving {
                ProgressView().tint(DS.Color.accent)
            } else {
                Image(systemName: saveSucceeded == true ? "checkmark" : "square.and.arrow.down")
                    .foregroundStyle(DS.Color.accent)
            }
        }
        .disabled(isSaving)
    }

    private func saveToGallery() {
        isSaving = true
        let processed = AdjustmentPipeline.apply(capturedImage, adj: adjustments)
        galleryStore.save(image: processed, context: ciContext)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            isSaving = false
            saveSucceeded = true
            try? await Task.sleep(for: .milliseconds(1500))
            saveSucceeded = nil
        }
    }
}
