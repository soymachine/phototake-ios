import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: CameraSession
    var onPreviewViewReady: ((PreviewLayerView) -> Void)?

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.videoPreviewLayer.session = session.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        onPreviewViewReady?(view)
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        // Connection is nil until the session has inputs; apply rotation once it exists.
        if let conn = uiView.videoPreviewLayer.connection,
           conn.isVideoRotationAngleSupported(90),
           conn.videoRotationAngle != 90 {
            conn.videoRotationAngle = 90
        }
    }
}

final class PreviewLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
