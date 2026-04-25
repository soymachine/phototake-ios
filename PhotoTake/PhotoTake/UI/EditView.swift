import SwiftUI
import CoreImage

struct EditView: View {
    let capturedImage: CIImage
    let ciContext: CIContext
    @EnvironmentObject var galleryStore: GalleryStore
    @Environment(\.dismiss) var dismiss

    @State private var adjustments = Adjustments.default
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var saveSucceeded: Bool? = nil
    @State private var isSaving = false

    private var processedImage: CIImage {
        AdjustmentPipeline.apply(capturedImage, adj: adjustments)
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Preview
                imagePreview
                    .frame(maxHeight: .infinity)

                // Controls
                controlsPanel
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { dismiss() }
                    .foregroundStyle(DS.Color.accent)
                    .font(DS.Font.mono)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: DS.Spacing.md) {
                    shareButton
                    saveButton
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ShareSheet(items: [img])
            }
        }
    }

    private var imagePreview: some View {
        GeometryReader { geo in
            let rendered = renderPreview()
            if let ui = rendered {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .padding(DS.Spacing.md)
    }

    private var controlsPanel: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                // Toggles
                HStack(spacing: DS.Spacing.md) {
                    toggleButton(
                        label: "INVERT",
                        systemImage: "circle.lefthalf.filled",
                        isOn: $adjustments.invert
                    )
                    toggleButton(
                        label: "B/W",
                        systemImage: "camera.filters",
                        isOn: $adjustments.blackAndWhite
                    )
                }

                Divider().background(DS.Color.surface)

                // Sliders
                SliderRow(label: "Brightness", systemImage: "sun.max",
                          value: $adjustments.brightness, range: -1...1)
                SliderRow(label: "Contrast", systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal",
                          value: $adjustments.contrast, range: 0.5...2.0)
                SliderRow(label: "Saturation", systemImage: "paintpalette",
                          value: $adjustments.saturation, range: 0...2.0)

                // Reset
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
        .frame(maxHeight: 300)
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

    private var shareButton: some View {
        Button(action: {
            shareImage = ExportController.makeShareImage(processedImage, context: ciContext)
            showShareSheet = true
        }) {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(DS.Color.accent)
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
        galleryStore.save(image: processedImage, context: ciContext)
        // Optimistic UI — GalleryStore handles errors via saveError
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            saveSucceeded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                saveSucceeded = nil
            }
        }
    }

    private func renderPreview() -> UIImage? {
        let img = processedImage
        guard let cg = ciContext.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
