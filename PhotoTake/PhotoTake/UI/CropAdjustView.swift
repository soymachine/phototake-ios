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
                // Raw image background
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

                // Editable corner overlay
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
            }
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Adjust")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 20) {
                    // Loupe toggle
                    Button {
                        loupeEnabled.toggle()
                    } label: {
                        Image(systemName: loupeEnabled
                              ? "magnifyingglass.circle.fill"
                              : "magnifyingglass.circle")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 22))
                    }

                    // Apply correction
                    Button("Apply") { applyCorrection() }
                        .foregroundStyle(DS.Color.accent)
                        .font(DS.Font.mono)
                }
            }
        }
        .task { await prepareImages() }
        .navigationDestination(isPresented: $navigateToEdit) {
            if let img = correctedImage {
                EditView(capturedImage: img, ciContext: ciContext)
            }
        }
    }

    // MARK: - Image preparation

    private func prepareImages() async {
        let ci = rawImage
        let ctx = ciContext

        // Render raw image for display (background thread)
        let mainImg: UIImage? = await Task.detached {
            guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: cg)
        }.value

        await MainActor.run { displayUIImage = mainImg }

        // Wait until displaySize is known
        var waited = 0
        while displaySize == .zero && waited < 20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        guard displaySize != .zero else { return }

        let size = displaySize
        let loupe: UIImage? = await Task.detached {
            makeLoupeImage(rawImage: ci, viewSize: size, context: ctx)
        }.value
        await MainActor.run { loupeImage = loupe }
    }

    // Creates a UIImage at exactly viewSize matching the scaledToFill display
    private func makeLoupeImage(rawImage: CIImage, viewSize: CGSize, context: CIContext) -> UIImage? {
        let iw = rawImage.extent.width
        let ih = rawImage.extent.height
        let scale = max(viewSize.width / iw, viewSize.height / ih)

        var ci = rawImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ox = (ci.extent.width - viewSize.width) / 2
        let oy = (ci.extent.height - viewSize.height) / 2
        ci = ci.transformed(by: CGAffineTransform(translationX: -ox, y: -oy))

        guard let cg = context.createCGImage(
            ci,
            from: CGRect(x: 0, y: 0, width: viewSize.width, height: viewSize.height)
        ) else { return nil }
        return UIImage(cgImage: cg)
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
