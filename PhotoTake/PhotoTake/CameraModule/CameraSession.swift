import AVFoundation
import CoreImage
import Combine

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)

    // Detection — set by ScanView
    var onProcessingFrame: ((CVPixelBuffer) -> Void)?

    @Published var isRunning = false
    @Published var error: CameraError?
    #if DEBUG
    @Published var debugInfo: String = "–"
    #endif

    private var photoCaptureCompletion: ((CIImage?) -> Void)?
    private var captureDevice: AVCaptureDevice?

    func start() {
        sessionQueue.async { [weak self] in self?.configure() }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    func capturePhoto(completion: @escaping (CIImage?) -> Void) {
        photoCaptureCompletion = completion
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Focus

    func focus(at viewPoint: CGPoint, in viewSize: CGSize) {
        guard let device = captureDevice else { return }
        // Direct normalized coords — AVCaptureVideoPreviewLayer handles visual rotation
        let pt = CGPoint(
            x: max(0, min(1, viewPoint.x / viewSize.width)),
            y: max(0, min(1, viewPoint.y / viewSize.height))
        )
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = pt
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = pt
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: - Configure

    private func configure() {
        guard !session.isRunning else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            DispatchQueue.main.async { self.error = .deviceUnavailable }
            return
        }
        captureDevice = device

        session.beginConfiguration()

        // inputPriority lets us choose the format manually
        session.sessionPreset = .inputPriority
        if session.canAddInput(input) { session.addInput(input) }

        // Select format: maximise photo resolution, require ≥1080p video for sharp preview
        let maxPhotoDims: CMVideoDimensions
        if let fmt = bestPhotoVideoFormat(for: device) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = fmt
                device.unlockForConfiguration()
            } catch {}
            maxPhotoDims = fmt.supportedMaxPhotoDimensions
                .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
                ?? fmt.formatDescription.dimensions
        } else {
            // Fallback: let the session choose
            session.sessionPreset = .photo
            maxPhotoDims = device.activeFormat.supportedMaxPhotoDimensions
                .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
                ?? device.activeFormat.formatDescription.dimensions
        }

        // Video output — Vision rectangle detection only
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frames",
                                                                       qos: .userInitiated))
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                         kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if let conn = videoOutput.connection(with: .video),
           conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }

        // Photo output — full-resolution still capture
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoDimensions = maxPhotoDims
        }

        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.isRunning = true }

        #if DEBUG
        let vd = device.activeFormat.formatDescription.dimensions
        let pd = maxPhotoDims
        let cafOK = device.isFocusModeSupported(.continuousAutoFocus)
        let poiOK = device.isFocusPointOfInterestSupported
        let preset = session.sessionPreset.rawValue.components(separatedBy: ".").last ?? "?"
        DispatchQueue.main.async {
            self.debugInfo = "video \(vd.width)×\(vd.height) | photo \(pd.width)×\(pd.height) | preset:\(preset) | CAF:\(cafOK) POI:\(poiOK) | AF pending…"
        }
        #endif

        // Enable continuous AF after the session is fully running
        sessionQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.enableContinuousAF()
        }
    }

    private func enableContinuousAF() {
        guard let device = captureDevice else { return }
        let locked = (try? device.lockForConfiguration()) != nil
        #if DEBUG
        DispatchQueue.main.async {
            self.debugInfo = (self.debugInfo.replacingOccurrences(of: " | AF pending…", with: ""))
                + " | lock:\(locked) mode:\(device.focusMode.rawValue)"
        }
        #endif
        guard locked else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        #if DEBUG
        DispatchQueue.main.async {
            self.debugInfo += "→\(device.focusMode.rawValue)"
        }
        #endif
        device.unlockForConfiguration()
    }

    // Find format with the highest photo resolution that also provides ≥1080p video
    private func bestPhotoVideoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats
            .filter { fmt in
                guard fmt.mediaType == .video else { return false }
                let d = fmt.formatDescription.dimensions
                guard d.width >= 1920 || d.height >= 1920 else { return false }
                guard fmt.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 })
                else { return false }
                return !fmt.supportedMaxPhotoDimensions.isEmpty
            }
            .max { a, b in
                let aP = a.supportedMaxPhotoDimensions
                    .map { Int($0.width) * Int($0.height) }.max() ?? 0
                let bP = b.supportedMaxPhotoDimensions
                    .map { Int($0.width) * Int($0.height) }.max() ?? 0
                if aP != bP { return aP < bP }
                let aV = Int(a.formatDescription.dimensions.width) *
                         Int(a.formatDescription.dimensions.height)
                let bV = Int(b.formatDescription.dimensions.width) *
                         Int(b.formatDescription.dimensions.height)
                return aV < bV
            }
    }

}

// MARK: - Video delegate

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onProcessingFrame?(buf)
    }
}

// MARK: - Photo delegate

extension CameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer {
            DispatchQueue.main.async { [weak self] in self?.photoCaptureCompletion = nil }
        }
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { [weak self] in self?.photoCaptureCompletion?(nil) }
            return
        }
        var ci = CIImage(data: data)
        if let orientationVal = ci?.properties[kCGImagePropertyOrientation as String] as? UInt32,
           let exifOrientation = CGImagePropertyOrientation(rawValue: orientationVal),
           let oriented = ci?.oriented(exifOrientation) {
            ci = oriented
        }
        DispatchQueue.main.async { [weak self] in self?.photoCaptureCompletion?(ci) }
    }
}

enum CameraError: LocalizedError {
    case deviceUnavailable
    var errorDescription: String? { "Camera not available" }
}
