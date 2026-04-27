import AVFoundation
import CoreImage
import Combine

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)

    // Preview (MTKView) — set by CameraPreviewView
    var onFrame: ((CVPixelBuffer) -> Void)?
    // Detection + loupe — set by ScanView
    var onProcessingFrame: ((CVPixelBuffer) -> Void)?

    @Published var isRunning = false
    @Published var error: CameraError?

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
            var settings = AVCapturePhotoSettings()
            // Request maximum sensor resolution
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Focus

    func focus(at viewPoint: CGPoint, in viewSize: CGSize) {
        guard let device = captureDevice else { return }
        // Map portrait view coords → landscape sensor coords (videoRotationAngle = 90)
        let devicePoint = CGPoint(
            x: 1.0 - viewPoint.y / viewSize.height,
            y: viewPoint.x / viewSize.width
        )
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    private func configure() {
        guard !session.isRunning else { return }

        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            DispatchQueue.main.async { self.error = .deviceUnavailable }
            return
        }

        captureDevice = device

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        // Video output — live preview and rectangle detection
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frames", qos: .userInitiated))
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        // Photo output — full-resolution still capture
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            // Pick the largest dimension the active format supports
            if let maxDims = device.activeFormat.supportedMaxPhotoDimensions
                .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
                photoOutput.maxPhotoDimensions = maxDims
            }
        }

        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.isRunning = true }
    }
}

// MARK: - Video delegate (preview + detection)

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buf)
        onProcessingFrame?(buf)
    }
}

// MARK: - Photo delegate (full-res still)

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

        // Apply EXIF orientation so the CIImage is upright (portrait)
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
