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
    @State private var lastPixelBuffer: CVPixelBuffer?
    @State private var frameSize: CGSize = .zero
    @State private var manualMode = false

    let ciContext: CIContext

    private let detectionThrottle = ThrottleTimer(interval: 0.3)

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // Camera preview
            GeometryReader { geo in
                CameraPreviewView(session: cameraSession, ciContext: ciContext)
                    .ignoresSafeArea()
                    .onAppear { overlaySize = geo.size }
                    .onChange(of: geo.size) { overlaySize = $1 }

                // Quad overlay
                if hasDetection || manualMode {
                    QuadOverlayView(corners: $detectedCorners, viewSize: geo.size, animated: !manualMode)
                        .allowsHitTesting(true)
                }
            }

            // Bottom controls
            VStack {
                Spacer()
                bottomBar
            }
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

    private var bottomBar: some View {
        HStack(spacing: DS.Spacing.xl) {
            // Manual mode toggle
            Button(action: toggleManualMode) {
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: manualMode ? "hand.raised.fill" : "hand.raised")
                        .font(.system(size: 22))
                    Text(manualMode ? "MANUAL" : "AUTO")
                        .font(DS.Font.monoSmall)
                }
                .foregroundStyle(manualMode ? DS.Color.accent : DS.Color.textSecondary)
            }

            // Capture button
            Button(action: capture) {
                ZStack {
                    Circle()
                        .fill(DS.Color.accent)
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(DS.Color.textPrimary, lineWidth: 3)
                        .frame(width: 82, height: 82)
                }
            }
            .disabled(!hasDetection && !manualMode)
            .opacity((hasDetection || manualMode) ? 1 : 0.4)

            // Flash placeholder / detection indicator
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: hasDetection ? "rectangle.dashed" : "viewfinder")
                    .font(.system(size: 22))
                Text(hasDetection ? "FOUND" : "SCAN")
                    .font(DS.Font.monoSmall)
            }
            .foregroundStyle(hasDetection ? DS.Color.accent : DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.lg)
        .background(.ultraThinMaterial)
    }

    private func setupFrameProcessing() {
        cameraSession.onFrame = { [weak detector] pixelBuffer in
            self.lastPixelBuffer = pixelBuffer

            // Store frame dimensions
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            self.frameSize = CGSize(width: w, height: h)

            guard !self.manualMode else { return }

            self.detectionThrottle.call {
                detector?.detect(in: pixelBuffer) { obs in
                    guard let obs else {
                        self.hasDetection = false
                        return
                    }
                    let viewCorners = PerspectiveCorrector.vnObservationToViewCorners(obs, viewSize: self.overlaySize)
                    self.detectedCorners = viewCorners
                    self.hasDetection = true
                }
            }
        }
    }

    private func toggleManualMode() {
        manualMode.toggle()
        if manualMode && detectedCorners.isEmpty {
            // Default full-frame quad
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

        cameraSession.capturePhoto { [weak self] pixelBuffer in
            guard let self, let pixelBuffer else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                  height: CVPixelBufferGetHeight(pixelBuffer))

            let pixelCorners = PerspectiveCorrector.viewCornersToImagePixels(
                corners: self.detectedCorners,
                viewSize: self.overlaySize,
                imageSize: imageSize
            )

            let corrected = PerspectiveCorrector.correct(image: ciImage, quad: pixelCorners)
                ?? ciImage

            DispatchQueue.main.async {
                self.capturedImage = corrected
                self.showEdit = true
            }
        }
    }
}

// Simple throttle to avoid running detection every frame
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
