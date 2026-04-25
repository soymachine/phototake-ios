import SwiftUI
import Vision
import CoreImage

struct ScanView: View {
    @StateObject private var cameraSession = CameraSession()
    @State private var detector = RectangleDetector()
    @State private var detectedCorners: [CGPoint] = []
    @State private var hasDetection = false
    @State private var capturedImage: CIImage?
    @State private var showEdit = false
    @State private var overlaySize: CGSize = .zero
    @State private var manualMode = false
    @State private var detectionThrottle = ThrottleTimer(interval: 0.3)
    @State private var latestFrameImage: UIImage?
    @State private var loupeFrameCount = 0

    let ciContext: CIContext

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                CameraPreviewView(session: cameraSession, ciContext: ciContext)
                    .ignoresSafeArea()
                    .onAppear { overlaySize = geo.size }
                    .onChange(of: geo.size) { _, newSize in overlaySize = newSize }

                if hasDetection || manualMode {
                    QuadOverlayView(
                        corners: $detectedCorners,
                        viewSize: geo.size,
                        animated: !manualMode,
                        latestFrame: latestFrameImage
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .onAppear {
            cameraSession.start()
            setupFrameProcessing()
        }
        .onDisappear {
            cameraSession.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            cameraSession.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            cameraSession.start()
            setupFrameProcessing()
        }
        .navigationDestination(isPresented: $showEdit) {
            if let img = capturedImage {
                EditView(capturedImage: img, ciContext: ciContext)
            }
        }
    }

    // MARK: - Bottom bar (compact)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Manual toggle
            Button(action: toggleManualMode) {
                VStack(spacing: 3) {
                    Image(systemName: manualMode ? "hand.raised.fill" : "hand.raised")
                        .font(.system(size: 17))
                    Text(manualMode ? "MANUAL" : "AUTO")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(manualMode ? DS.Color.accent : DS.Color.textSecondary)
                .frame(maxWidth: .infinity)
            }

            // Capture button
            Button(action: capture) {
                ZStack {
                    Circle()
                        .fill(DS.Color.accent)
                        .frame(width: 56, height: 56)
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 2.5)
                        .frame(width: 64, height: 64)
                }
            }
            .disabled(!hasDetection && !manualMode)
            .opacity((hasDetection || manualMode) ? 1 : 0.35)
            .frame(maxWidth: .infinity)

            // Detection indicator
            VStack(spacing: 3) {
                Image(systemName: hasDetection ? "rectangle.dashed" : "viewfinder")
                    .font(.system(size: 17))
                Text(hasDetection ? "FOUND" : "SCAN")
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(hasDetection ? DS.Color.accent : DS.Color.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Frame processing

    private func setupFrameProcessing() {
        let throttle = detectionThrottle
        cameraSession.onProcessingFrame = { [weak detector] pixelBuffer in
            // Detection (throttled)
            guard !manualMode else {
                updateLoupeImage(from: pixelBuffer)
                return
            }
            throttle.call {
                detector?.detect(in: pixelBuffer) { obs in
                    guard let obs else {
                        hasDetection = false
                        return
                    }
                    let viewCorners = PerspectiveCorrector.vnObservationToViewCorners(
                        obs, viewSize: overlaySize)
                    detectedCorners = viewCorners
                    hasDetection = true
                }
            }
            updateLoupeImage(from: pixelBuffer)
        }
    }

    private func updateLoupeImage(from pixelBuffer: CVPixelBuffer) {
        loupeFrameCount += 1
        guard loupeFrameCount % 8 == 0 else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let ui = UIImage(cgImage: cg)
        DispatchQueue.main.async { latestFrameImage = ui }
    }

    // MARK: - Actions

    private func toggleManualMode() {
        manualMode.toggle()
        if manualMode && detectedCorners.isEmpty {
            let s = overlaySize
            let inset: CGFloat = 40
            detectedCorners = [
                CGPoint(x: inset, y: inset),
                CGPoint(x: s.width - inset, y: inset),
                CGPoint(x: s.width - inset, y: s.height - inset),
                CGPoint(x: inset, y: s.height - inset)
            ]
            hasDetection = true
        }
    }

    private func capture() {
        guard !detectedCorners.isEmpty else { return }
        let corners = detectedCorners
        let viewSize = overlaySize

        cameraSession.capturePhoto { pixelBuffer in
            guard let pixelBuffer else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                  height: CVPixelBufferGetHeight(pixelBuffer))
            let pixelCorners = PerspectiveCorrector.viewCornersToImagePixels(
                corners: corners, viewSize: viewSize, imageSize: imageSize)
            let corrected = PerspectiveCorrector.correct(image: ciImage, quad: pixelCorners) ?? ciImage
            DispatchQueue.main.async {
                capturedImage = corrected
                showEdit = true
            }
        }
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
