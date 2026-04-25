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
        ctx.coordinator.device = device
        ctx.coordinator.view = view
        return view
    }

    func updateUIView(_ view: MTKView, context ctx: Context) {
        let coordinator = ctx.coordinator
        session.onFrame = { [weak coordinator] pixelBuffer in
            coordinator?.currentPixelBuffer = pixelBuffer
        }
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let ciContext: CIContext
        var device: MTLDevice?
        weak var view: MTKView?
        var currentPixelBuffer: CVPixelBuffer?

        init(ciContext: CIContext) {
            self.ciContext = ciContext
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pixelBuffer = currentPixelBuffer,
                  let commandQueue = device?.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let drawable = view.currentDrawable else { return }

            var ci = CIImage(cvPixelBuffer: pixelBuffer)

            // Scale to fill view
            let drawableSize = view.drawableSize
            let scaleX = drawableSize.width / ci.extent.width
            let scaleY = drawableSize.height / ci.extent.height
            let scale = max(scaleX, scaleY)
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            let offsetX = (ci.extent.width - drawableSize.width) / 2
            let offsetY = (ci.extent.height - drawableSize.height) / 2
            ci = ci.transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            ciContext.render(ci,
                             to: drawable.texture,
                             commandBuffer: commandBuffer,
                             bounds: CGRect(origin: .zero, size: drawableSize),
                             colorSpace: colorSpace)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
