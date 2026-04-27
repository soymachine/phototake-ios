import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: CameraSession

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.videoPreviewLayer.session = session.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        if let conn = view.videoPreviewLayer.connection,
           conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {}
}

final class PreviewLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
