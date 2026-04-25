import SwiftUI
import Vision
import CoreImage

struct ScanView: View {
    @StateObject private var cameraSession = CameraSession()
    @State private var detector = RectangleDetector()
    @State private var detectedCorners: [CGPoint] = []
    @State private var hasDetection = false
    @State private var overlaySize: CGSize = .zero
    @State private var detectionThrottle = ThrottleTimer(interval: 0.3)

    // Post-capture state
    @State private var rawCapturedImage: CIImage?
    @State private var correctedCIImage: CIImage?
    @State private var capturedNormalizedCorners: [CGPoint] = []
    @State private var capturedPreviewUIImage: UIImage?

    // Navigation
    @State private var showCrop = false
    @State private var showEdit = false

    let ciContext: CIContext

    var body: some View {
        // GeometryReader ignores safe areas → geo.size = full screen
        GeometryReader { geo in
            Color.black

            CameraPreviewView(session: cameraSession, ciContext: ciContext)
                .onAppear {
                    overlaySize = geo.size
                    setupFrameProcessing()
                }
                .onChange(of: geo.size) { _, s in overlaySize = s }

            // Visual-only detection quad (hidden while preview is showing)
            if hasDetection && capturedPreviewUIImage == nil {
                QuadOverlayView(
                    corners: $detectedCorners,
                    viewSize: geo.size,
                    isInteractive: false
                )
                .allowsHitTesting(false)
            }

            // Shutter bar — only when no preview
            if capturedPreviewUIImage == nil {
                VStack {
                    Spacer()
                    shutterBar
                        .padding(.bottom, geo.safeAreaInsets.bottom)
                }
            }

            // Capture preview overlay
            if let previewImg = capturedPreviewUIImage {
                capturePreviewOverlay(previewImg, safeBottom: geo.safeAreaInsets.bottom)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { cameraSession.stop() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification)) { _ in cameraSession.stop() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            cameraSession.start()
            setupFrameProcessing()
        }
        .navigationDestination(isPresented: $showCrop) {
            if let raw = rawCapturedImage {
                CropAdjustView(
                    rawImage: raw,
                    initialNormalizedCorners: capturedNormalizedCorners,
                    ciContext: ciContext
                )
            }
        }
        .navigationDestination(isPresented: $showEdit) {
            if let img = correctedCIImage {
                EditView(capturedImage: img, ciContext: ciContext)
            }
        }
    }

    // MARK: - Shutter bar

    private var shutterBar: some View {
        HStack {
            Spacer()
            Button(action: capture) {
                ZStack {
                    Circle().fill(DS.Color.accent).frame(width: 60, height: 60)
                    Circle().stroke(Color.white.opacity(0.8), lineWidth: 2.5).frame(width: 68, height: 68)
                }
            }
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Capture preview overlay

    private func capturePreviewOverlay(_ image: UIImage, safeBottom: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .shadow(color: .black.opacity(0.5), radius: 12)

                Spacer(minLength: 20)

                // Action buttons
                HStack(spacing: 12) {
                    // Retake
                    Button {
                        withAnimation { capturedPreviewUIImage = nil }
                    } label: {
                        Label("Retake", systemImage: "arrow.counterclockwise")
                            .font(DS.Font.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Color.surfaceSecondary)
                            .foregroundStyle(DS.Color.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
                    }

                    // Adjust corners
                    Button {
                        withAnimation { capturedPreviewUIImage = nil }
                        showCrop = true
                    } label: {
                        Label("Adjust", systemImage: "crop")
                            .font(DS.Font.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Color.surfaceSecondary)
                            .foregroundStyle(DS.Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
                    }

                    // Continue to edit
                    Button {
                        withAnimation { capturedPreviewUIImage = nil }
                        showEdit = true
                    } label: {
                        Label("Use", systemImage: "checkmark")
                            .font(DS.Font.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Color.accent)
                            .foregroundStyle(DS.Color.background)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(safeBottom, 24))
            }
        }
    }

    // MARK: - Frame processing

    private func setupFrameProcessing() {
        let throttle = detectionThrottle
        cameraSession.onProcessingFrame = { [weak detector] pixelBuffer in
            throttle.call {
                detector?.detect(in: pixelBuffer) { obs in
                    guard let obs else { hasDetection = false; return }
                    detectedCorners = PerspectiveCorrector.vnObservationToViewCorners(
                        obs, viewSize: overlaySize)
                    hasDetection = true
                }
            }
        }
    }

    // MARK: - Capture

    private func capture() {
        let corners = detectedCorners.isEmpty ? fullFrameCorners : detectedCorners
        let size = overlaySize
        let normalized = corners.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
        let ctx = ciContext

        Task {
            // Bridge callback to async/await
            guard let pixelBuffer = await withCheckedContinuation(
                { (cont: CheckedContinuation<CVPixelBuffer?, Never>) in
                    cameraSession.capturePhoto { buf in cont.resume(returning: buf) }
                })
            else { return }

            let raw = CIImage(cvPixelBuffer: pixelBuffer)
            let imgSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                 height: CVPixelBufferGetHeight(pixelBuffer))
            let pixelCorners = PerspectiveCorrector.viewCornersToImagePixels(
                corners: corners, viewSize: size, imageSize: imgSize)
            let corrected = PerspectiveCorrector.correct(image: raw, quad: pixelCorners) ?? raw

            // Render preview off main thread
            let previewImg: UIImage? = await Task.detached {
                guard let cg = ctx.createCGImage(corrected, from: corrected.extent) else { return nil }
                return UIImage(cgImage: cg)
            }.value

            rawCapturedImage = raw
            correctedCIImage = corrected
            capturedNormalizedCorners = normalized
            withAnimation { capturedPreviewUIImage = previewImg }
        }
    }

    private var fullFrameCorners: [CGPoint] {
        let s = overlaySize, i: CGFloat = 24
        return [CGPoint(x: i, y: i), CGPoint(x: s.width-i, y: i),
                CGPoint(x: s.width-i, y: s.height-i), CGPoint(x: i, y: s.height-i)]
    }
}

// MARK: - Throttle

final class ThrottleTimer {
    private let interval: TimeInterval
    private var lastFire: Date = .distantPast
    init(interval: TimeInterval) { self.interval = interval }
    func call(_ action: @escaping () -> Void) {
        let now = Date()
        guard now.timeIntervalSince(lastFire) >= interval else { return }
        lastFire = now
        action()
    }
}
