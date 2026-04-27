import SwiftUI
import Vision
import CoreImage

// MARK: - Scan mode

enum ScanMode: String, CaseIterable {
    case document = "DOC"
    case photo    = "PHOTO"
    case negative = "NEG"

    var icon: String {
        switch self {
        case .document: return "doc.text.viewfinder"
        case .photo:    return "photo"
        case .negative: return "film"
        }
    }

    var label: String {
        switch self {
        case .document: return "Document"
        case .photo:    return "Photo"
        case .negative: return "Negative"
        }
    }

    var initialAdjustments: Adjustments {
        switch self {
        case .negative: return Adjustments(brightness: 0, contrast: 1.1, saturation: 1,
                                           invert: true, blackAndWhite: false)
        default:        return .default
        }
    }
}

// MARK: - ScanView

struct ScanView: View {
    @StateObject private var cameraSession = CameraSession()
    @EnvironmentObject var proStore: ProStore
    @State private var detector = RectangleDetector()
    @State private var detectedCorners: [CGPoint] = []
    @State private var hasDetection = false
    @State private var overlaySize: CGSize = .zero
    @State private var detectionThrottle = ThrottleTimer(interval: 0.3)
    @State private var scanMode: ScanMode = .document

    // Post-capture state
    @State private var rawCapturedImage: CIImage?
    @State private var correctedCIImage: CIImage?
    @State private var capturedNormalizedCorners: [CGPoint] = []
    @State private var capturedPreviewUIImage: UIImage?

    // Focus indicator
    @State private var focusIndicatorPoint: CGPoint? = nil
    @State private var safeAreaInsets: EdgeInsets = .init()

    // Navigation
    @State private var showCrop     = false
    @State private var showEdit     = false
    @State private var showGallery  = false
    @State private var showPaywall  = false

    let ciContext: CIContext

    var body: some View {
        GeometryReader { geo in
            Color.black

            CameraPreviewView(session: cameraSession, ciContext: ciContext)
                .onAppear {
                    overlaySize = geo.size
                    safeAreaInsets = geo.safeAreaInsets
                    cameraSession.start()
                    setupFrameProcessing()
                }
                .onChange(of: geo.size) { _, s in overlaySize = s }

            // Tap-to-focus layer (below all controls, above camera)
            if capturedPreviewUIImage == nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        focusAt(location, viewSize: geo.size)
                    }
            }

            // Detection quad — visual only
            if hasDetection && capturedPreviewUIImage == nil {
                QuadOverlayView(
                    corners: $detectedCorners,
                    viewSize: geo.size,
                    isInteractive: false
                )
                .allowsHitTesting(false)
            }

            // "DETECTED" badge just below status bar
            if hasDetection && capturedPreviewUIImage == nil {
                detectionBadge
                    .position(x: geo.size.width / 2,
                              y: geo.safeAreaInsets.top + 52)
            }

            // Scan count badge for free users
            if capturedPreviewUIImage == nil && !proStore.isPro {
                scanCountBadge
                    .position(x: geo.size.width / 2,
                              y: geo.safeAreaInsets.top + 16)
            }

            // Focus indicator
            if let fp = focusIndicatorPoint {
                FocusIndicator()
                    .position(fp)
                    .allowsHitTesting(false)
            }

            // Mode selector + shutter bar at bottom
            if capturedPreviewUIImage == nil {
                VStack(spacing: 0) {
                    Spacer()
                    shutterBar(safeBottom: geo.safeAreaInsets.bottom)
                }
            }

            // Post-capture overlay
            if let img = capturedPreviewUIImage {
                capturePreviewOverlay(img, safeBottom: geo.safeAreaInsets.bottom)
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
                EditView(capturedImage: img,
                         ciContext: ciContext,
                         initialAdjustments: scanMode.initialAdjustments)
            }
        }
        .navigationDestination(isPresented: $showGallery) {
            GalleryView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Scan count badge (free users)

    private var scanCountBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text("\(proStore.scansRemaining) scans left")
                .font(DS.Font.monoCaption)
        }
        .foregroundStyle(DS.Color.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .onTapGesture { showPaywall = true }
    }

    // MARK: - Detection badge

    private var detectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.Color.accent)
                .frame(width: 7, height: 7)
            Text("DETECTED")
                .font(DS.Font.monoCaption)
                .foregroundStyle(DS.Color.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Shutter bar

    private func shutterBar(safeBottom: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // Gallery shortcut
            Button { showGallery = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "photo.stack")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)

            // Shutter button
            Button(action: capture) {
                ZStack {
                    Circle()
                        .stroke(DS.Color.accent, lineWidth: 4)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(.white)
                        .frame(width: 68, height: 68)
                }
            }
            .frame(maxWidth: .infinity)

            // Symmetry placeholder
            Color.clear
                .frame(width: 54, height: 54)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, max(safeBottom, 20))
        .background(.ultraThinMaterial)
    }

    // MARK: - Capture preview overlay

    private func capturePreviewOverlay(_ image: UIImage, safeBottom: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 0) {
                // Mode label
                Text(scanMode.label.uppercased())
                    .font(DS.Font.monoCaption)
                    .foregroundStyle(DS.Color.accent)
                    .padding(.top, 24)

                Spacer(minLength: 16)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: DS.Corner.lg))
                    .padding(.horizontal, 20)
                    .shadow(color: DS.Color.accent.opacity(0.15), radius: 24)

                Spacer(minLength: 24)

                // Actions
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        previewButton("Retake", icon: "arrow.counterclockwise", isPrimary: false) {
                            withAnimation { capturedPreviewUIImage = nil }
                        }
                        previewButton("Adjust", icon: "skew", isPrimary: false) {
                            withAnimation { capturedPreviewUIImage = nil }
                            showCrop = true
                        }
                    }
                    previewButton("Use Photo", icon: "checkmark", isPrimary: true) {
                        withAnimation { capturedPreviewUIImage = nil }
                        showEdit = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(safeBottom, 28))
            }
        }
    }

    private func previewButton(_ label: String, icon: String, isPrimary: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).font(DS.Font.mono)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isPrimary ? DS.Color.accent : DS.Color.surfaceSecondary)
            .foregroundStyle(isPrimary ? DS.Color.background : DS.Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md))
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
        guard proStore.canScan else { showPaywall = true; return }

        let corners = detectedCorners.isEmpty ? fullFrameCorners : detectedCorners
        let size = overlaySize
        let normalized = corners.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
        let ctx = ciContext
        let isFree = !proStore.isPro

        Task {
            guard let raw = await withCheckedContinuation(
                { (cont: CheckedContinuation<CIImage?, Never>) in
                    cameraSession.capturePhoto { img in cont.resume(returning: img) }
                })
            else { return }

            let imgSize = CGSize(width: raw.extent.width, height: raw.extent.height)
            let pixelCorners = PerspectiveCorrector.viewCornersToImagePixels(
                corners: corners, viewSize: size, imageSize: imgSize)
            var corrected = PerspectiveCorrector.correct(image: raw, quad: pixelCorners) ?? raw

            // Free tier: cap at 1080p
            if isFree { corrected = corrected.limited(to: 1080) }

            let previewImg: UIImage? = await Task.detached {
                guard let cg = ctx.createCGImage(corrected, from: corrected.extent) else { return nil }
                return UIImage(cgImage: cg)
            }.value

            proStore.recordScan()
            rawCapturedImage = raw
            correctedCIImage = corrected
            capturedNormalizedCorners = normalized
            withAnimation { capturedPreviewUIImage = previewImg }
        }
    }

    private var fullFrameCorners: [CGPoint] {
        let s = overlaySize
        // safeAreaInsets may report 0 inside ignoresSafeArea; clamp to device minimum
        let safeTop    = max(safeAreaInsets.top, 50)
        let safeBottom = max(safeAreaInsets.bottom, 20)
        let topY    = safeTop + 120     // well below Dynamic Island + badges
        let bottomY = s.height - safeBottom - 150  // above shutter bar + home indicator
        let sideX: CGFloat = 32
        return [
            CGPoint(x: sideX,          y: topY),
            CGPoint(x: s.width - sideX, y: topY),
            CGPoint(x: s.width - sideX, y: bottomY),
            CGPoint(x: sideX,          y: bottomY)
        ]
    }

    // MARK: - Focus

    private func focusAt(_ point: CGPoint, viewSize: CGSize) {
        focusIndicatorPoint = point
        cameraSession.focus(at: point, in: viewSize)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { focusIndicatorPoint = nil }
        }
    }
}

// MARK: - Focus indicator

private struct FocusIndicator: View {
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { scale = 1.0 }
                withAnimation(.easeIn(duration: 0.4).delay(1.0)) { opacity = 0.0 }
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
