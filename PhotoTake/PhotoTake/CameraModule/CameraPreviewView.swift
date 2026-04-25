import MetalKit
import CoreImage
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: CameraSession
    let ciContext: CIContext

    func makeCoordinator() -> Coordinator {
        Coordinator(ciContext: ciContext)
    }

    func makeUIView(context ctx: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()!
        let view = MTKView(frame: .zero, device: device)
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 30
        view.delegate = ctx.coordinator
        ctx.coordinator.setup(device: device)
        return view
    }

    func updateUIView(_ view: MTKView, context ctx: Context) {
        let coordinator = ctx.coordinator
        // Use onFrame so it doesn't conflict with ScanView's onProcessingFrame
        session.onFrame = { [weak coordinator] pixelBuffer in
            coordinator?.currentPixelBuffer = pixelBuffer
        }
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let ciContext: CIContext
        private var commandQueue: MTLCommandQueue?
        var currentPixelBuffer: CVPixelBuffer?

        init(ciContext: CIContext) {
            self.ciContext = ciContext
        }

        func setup(device: MTLDevice) {
            commandQueue = device.makeCommandQueue()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pixelBuffer = currentPixelBuffer,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let drawable = view.currentDrawable else { return }

            var ci = CIImage(cvPixelBuffer: pixelBuffer)
            let drawableSize = view.drawableSize

            // Scale to fill
            let scaleX = drawableSize.width / ci.extent.width
            let scaleY = drawableSize.height / ci.extent.height
            let scale = max(scaleX, scaleY)
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            let offsetX = (ci.extent.width - drawableSize.width) / 2
            let offsetY = (ci.extent.height - drawableSize.height) / 2
            ci = ci.transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))

            ciContext.render(ci,
                             to: drawable.texture,
                             commandBuffer: commandBuffer,
                             bounds: CGRect(origin: .zero, size: drawableSize),
                             colorSpace: CGColorSpaceCreateDeviceRGB())
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
