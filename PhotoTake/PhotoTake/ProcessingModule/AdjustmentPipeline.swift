import CoreImage
import CoreImage.CIFilterBuiltins

struct Adjustments: Equatable {
    var brightness: Float = 0      // -1.0 … 1.0
    var contrast: Float = 1        //  0.5 … 2.0
    var saturation: Float = 1      //  0.0 … 2.0
    var invert: Bool = false
    var blackAndWhite: Bool = false

    static let `default` = Adjustments()
}

enum AdjustmentPipeline {
    static func apply(_ image: CIImage, adj: Adjustments) -> CIImage {
        var out = image

        let cc = CIFilter.colorControls()
        cc.inputImage = out
        cc.brightness = adj.brightness
        cc.contrast = adj.contrast
        cc.saturation = adj.blackAndWhite ? 0 : adj.saturation
        out = cc.outputImage ?? out

        if adj.invert {
            let inv = CIFilter.colorInvert()
            inv.inputImage = out
            out = inv.outputImage ?? out
        }

        return out
    }
}
