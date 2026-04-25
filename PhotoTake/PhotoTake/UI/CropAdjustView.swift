import SwiftUI
import CoreImage

struct CropAdjustView: View {
    let rawImage: CIImage
    let initialNormalizedCorners: [CGPoint]
    let ciContext: CIContext

    @State private var corners: [CGPoint] = []
    @State private var displaySize: CGSize = .zero
    @State private var loupeEnabled = true          // on by default
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
                    let topMargin = geo.safeAreaInsets.top + 60
                    let bottomMargin = geo.safeAreaInsets.bottom + 30
                    let hMargin: CGFloat = 20
                    QuadOverlayView(
                        corners: $corners,
                        viewSize: geo.size,
                        isInteractive: true,
                        latestFrame: loupeEnabled ? loupeImage : nil,
                        dragBounds: CGRect(
                            x: hMargin,
                            y: topMargin,
                            width: geo.size.width - hMargin * 2,
                            height: geo.size.height - topMargin - bottomMargin
                        )
                    )
                }
            }
            .onAppear {
                let size = geo.size
                displaySize = size
                let topMargin = geo.safeAreaInsets.top + 60
                let bottomMargin = geo.safeAreaInsets.bottom + 30
                let hMargin: CGFloat = 20
                let b = CGRect(x: hMargin, y: topMargin,
                               width: size.width - hMargin * 2,
                               height: size.height - topMargin - bottomMargin)
                corners = initialNormalizedCorners.map {
                    let pt = CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                    return CGPoint(x: max(b.minX, min(b.maxX, pt.x)),
                                   y: max(b.minY, min(b.maxY, pt.y)))
                }
                Task { await prepareImages(viewSize: size) }
            }
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Adjust")
        .toolbarBackground(DS.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        .navigationDestination(isPresented: $navigateToEdit) {
            if let img = correctedImage {
                EditView(capturedImage: img, ciContext: ciContext)
            }
        }
    }

    // MARK: - Image preparation

    private func prepareImages(viewSize: CGSize) async {
        let ci = rawImage
        let ctx = ciContext

        // Render full-res display image off main thread
        let displayImg: UIImage? = await Task.detached {
            guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: cg)
        }.value

        displayUIImage = displayImg

        // Build loupe image: UIKit crop-fill so it matches .scaledToFill() exactly
        guard let src = displayImg, viewSize != .zero else { return }
        loupeImage = await Task.detached { scaleFillImage(src, toSize: viewSize) }.value
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

// MARK: - UIKit crop-fill (nonisolated, safe for Task.detached)

private func scaleFillImage(_ image: UIImage, toSize size: CGSize) -> UIImage {
    let scaleX = size.width  / image.size.width
    let scaleY = size.height / image.size.height
    let scale  = max(scaleX, scaleY)
    let scaledW = image.size.width  * scale
    let scaledH = image.size.height * scale
    let ox = (scaledW - size.width)  / 2
    let oy = (scaledH - size.height) / 2
    return UIGraphicsImageRenderer(size: size).image { _ in
        image.draw(in: CGRect(x: -ox, y: -oy, width: scaledW, height: scaledH))
    }
}
