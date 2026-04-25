import SwiftUI
import CoreImage

struct CropAdjustView: View {
    let rawImage: CIImage
    let initialNormalizedCorners: [CGPoint]
    let ciContext: CIContext

    @State private var corners: [CGPoint] = []
    @State private var displaySize: CGSize = .zero
    @State private var loupeEnabled = false
    @State private var displayUIImage: UIImage?
    @State private var loupeImage: UIImage?
    @State private var correctedImage: CIImage?
    @State private var navigateToEdit = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group {
                    if let img = displayUIImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Color.black
                        ProgressView().tint(DS.Color.accent)
                    }
                }
                .ignoresSafeArea()

                if !corners.isEmpty {
                    QuadOverlayView(
                        corners: $corners,
                        viewSize: geo.size,
                        isInteractive: true,
                        latestFrame: loupeEnabled ? loupeImage : nil
                    )
                }
            }
            .onAppear {
                let size = geo.size
                displaySize = size
                corners = initialNormalizedCorners.map {
                    CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                }
                Task { loupeImage = await prepareLoupeImage(viewSize: size) }
            }
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Adjust")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 20) {
                    Button {
                        loupeEnabled.toggle()
                    } label: {
                        Image(systemName: loupeEnabled
                              ? "magnifyingglass.circle.fill"
                              : "magnifyingglass.circle")
                            .foregroundStyle(DS.Color.accent)
                            .font(.system(size: 22))
                    }
                    Button("Apply") { applyCorrection() }
                        .foregroundStyle(DS.Color.accent)
                        .font(DS.Font.mono)
                }
            }
        }
        // Render display image once on appear
        .task { await prepareDisplayImage() }
        // Render loupe image whenever the view size is established
        .onChange(of: displaySize) { _, size in
            guard size != .zero else { return }
            Task { loupeImage = await prepareLoupeImage(viewSize: size) }
        }
        .navigationDestination(isPresented: $navigateToEdit) {
            if let img = correctedImage {
                EditView(capturedImage: img, ciContext: ciContext)
            }
        }
    }

    // MARK: - Image preparation

    private func prepareDisplayImage() async {
        let ci = rawImage
        let ctx = ciContext
        let img: UIImage? = await Task.detached {
            guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        displayUIImage = img
    }

    private func prepareLoupeImage(viewSize: CGSize) async -> UIImage? {
        let ci = rawImage
        let ctx = ciContext
        return await Task.detached {
            cropFillImage(ci, toSize: viewSize, context: ctx)
        }.value
    }

    // MARK: - Apply

    private func applyCorrection() {
        let imageSize = CGSize(width: rawImage.extent.width, height: rawImage.extent.height)
        let pixelCorners = PerspectiveCorrector.viewCornersToImagePixels(
            corners: corners,
            viewSize: displaySize,
            imageSize: imageSize
        )
        correctedImage = PerspectiveCorrector.correct(image: rawImage, quad: pixelCorners) ?? rawImage
        navigateToEdit = true
    }
}

// MARK: - Free function (nonisolated, usable in Task.detached)

private func cropFillImage(_ image: CIImage, toSize size: CGSize, context: CIContext) -> UIImage? {
    let scale = max(size.width / image.extent.width, size.height / image.extent.height)
    var ci = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let ox = (ci.extent.width - size.width) / 2
    let oy = (ci.extent.height - size.height) / 2
    ci = ci.transformed(by: CGAffineTransform(translationX: -ox, y: -oy))
    guard let cg = context.createCGImage(
        ci, from: CGRect(x: 0, y: 0, width: size.width, height: size.height)
    ) else { return nil }
    return UIImage(cgImage: cg)
}
