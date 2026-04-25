import AVFoundation
import Combine

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)
    var onFrame: ((CVPixelBuffer) -> Void)?

    @Published var isRunning = false
    @Published var error: CameraError?

    func start() {
        sessionQueue.async { [weak self] in
            self?.configure()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    func capturePhoto(completion: @escaping (CVPixelBuffer?) -> Void) {
        // Store completion to be called on next frame
        self.photoCaptureCompletion = completion
    }

    private var photoCaptureCompletion: ((CVPixelBuffer?) -> Void)?

    private func configure() {
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            DispatchQueue.main.async { self.error = .deviceUnavailable }
            return
        }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frames", qos: .userInitiated))
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(output) { session.addOutput(output) }

        // Set portrait orientation
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.isRunning = true }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if let completion = photoCaptureCompletion {
            photoCaptureCompletion = nil
            completion(buf)
            return
        }

        onFrame?(buf)
    }
}

enum CameraError: LocalizedError {
    case deviceUnavailable
    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "Camera not available"
        }
    }
}
