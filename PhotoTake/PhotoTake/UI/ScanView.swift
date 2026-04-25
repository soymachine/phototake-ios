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

    let ciContext: CIContext

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            GeometryReader { geo in
                CameraPreviewView(session: cameraSession, ciContext: ciContext)
                    .ignoresSafeArea()
                    .onAppear { overlaySize = geo.size }
                    .onChange(of: geo.size) { _, newSize in overlaySize = newSize }

                if hasDetection || manualMode {
                    QuadOverlayView(corners: $detectedCorners, viewSize: geo.size, animated: !manualMode)
                        .allowsHitTesting(true)
                }
            }

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
            Button(action: toggleManualMode) {
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: manualMode ? "hand.raised.fill" : "hand.raised")
                        .font(.system(size: 22))
                    Text(manualMode ? "MANUAL" : "AUTO")
                        .font(DS.Font.monoSmall)
                }
                .foregroundStyle(manualMode ? DS.Color.accent : DS.Color.textSecondary)
            }

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
        let throttle = detectionThrottle
        cameraSession.onFrame = { [weak detector] pixelBuffer in
            guard !manualMode else { return }
            throttle.call {
                detector?.detect(in: pixelBuffer) { obs in
                    guard let obs else {
                        hasDetection = false
                        return
                    }
                    let viewCorners = PerspectiveCorrector.vnObservationToViewCorners(obs, viewSize: overlaySize)
                    detectedCorners = viewCorners
                    hasDetection = true
                }
            }
        }
    }

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
                corners: corners,
                viewSize: viewSize,
                imageSize: imageSize
            )

            let corrected = PerspectiveCorrector.correct(image: ciImage, quad: pixelCorners)
                ?? ciImage

            DispatchQueue.main.async {
                capturedImage = corrected
                showEdit = true
            }
        }
    }
}

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
