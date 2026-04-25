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

    // Post-capture navigation
    @State private var rawCapturedImage: CIImage?
    @State private var capturedNormalizedCorners: [CGPoint] = []
    @State private var showCrop = false

    let ciContext: CIContext

    var body: some View {
        ZStack {
            Color.black

            GeometryReader { geo in
                CameraPreviewView(session: cameraSession, ciContext: ciContext)
                    .onAppear { overlaySize = geo.size }
                    .onChange(of: geo.size) { _, s in overlaySize = s }

                // Visual-only quad — not interactive
                if hasDetection {
                    QuadOverlayView(
                        corners: $detectedCorners,
                        viewSize: geo.size,
                        isInteractive: false
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { shutterBar }
        .onAppear {
            cameraSession.start()
            setupFrameProcessing()
        }
        .onDisappear { cameraSession.stop() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification)) { _ in
            cameraSession.stop()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            cameraSession.start()
            setupFrameProcessing()
        }
        .navigationDestination(isPresented: $showCrop) {
            if let img = rawCapturedImage {
                CropAdjustView(
                    rawImage: img,
                    initialNormalizedCorners: capturedNormalizedCorners,
                    ciContext: ciContext
                )
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
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
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
        let normalizedCorners = corners.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }

        cameraSession.capturePhoto { pixelBuffer in
            guard let pixelBuffer else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            DispatchQueue.main.async {
                rawCapturedImage = ciImage
                capturedNormalizedCorners = normalizedCorners
                showCrop = true
            }
        }
    }

    private var fullFrameCorners: [CGPoint] {
        let s = overlaySize
        let inset: CGFloat = 24
        return [
            CGPoint(x: inset, y: inset),
            CGPoint(x: s.width - inset, y: inset),
            CGPoint(x: s.width - inset, y: s.height - inset),
            CGPoint(x: inset, y: s.height - inset)
        ]
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
