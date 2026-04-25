# PhotoTake iOS — instrucciones para Claude

## Referencia web
El repo hermano (versión web) es `soymachine/phototake`.
La versión web actual es v3.0 (`index.html`).
Consultar ese repo para comparar comportamiento esperado: detección de rectángulo,
ajustes de imagen, galería, flujo de exportación.

---

## Qué hace la app
Escáner de documentos y negativos fotográficos:
1. Cámara apunta al documento/negativo
2. Detección automática del rectángulo (o ajuste manual de esquinas)
3. Corrección de perspectiva → imagen recortada y plana
4. Opcionales: invertir colores (negativo → positivo), brillo/contraste/saturación, B/N
5. Guardar en Fotos o compartir

---

## Stack técnico — decisiones tomadas
| Necesidad | Solución elegida | Motivo |
|-----------|-----------------|--------|
| Cámara | AVCaptureSession + AVCaptureVideoDataOutput | Control total de frames |
| Preview en vivo | MTKView (Metal) + CIContext | Sin latencia, GPU directo |
| Detección rectángulo | Vision → VNDetectRectanglesRequest | Nativo, batería eficiente |
| Corrección perspectiva | CIPerspectiveCorrection (Core Image) | GPU, una línea de filtro |
| Ajustes de imagen | CIColorControls + CIColorInvert | Reemplaza ctx.filter roto en Safari |
| Exportar | UIActivityViewController + PHPhotoLibrary (.addOnly) | Integración real con Fotos iOS |
| Galería | FileManager (HEIC) + JSON manifest | ~50% menos que JPEG, sin límite localStorage |
| UI | SwiftUI | iOS 17+, sin UIKit salvo bridges puntuales |
| Target mínimo | iOS 17+ | VNDetectRectanglesRequest estable, SwiftUI maduro |

---

## Arquitectura de módulos

```
PhotoTakeApp
├── CameraModule
│   ├── CameraSession.swift          // AVCaptureSession setup, resolución .photo
│   ├── FrameProcessor.swift         // CVPixelBuffer → CIImage pipeline
│   └── CameraPreviewView.swift      // MTKView live preview (UIViewRepresentable)
├── DetectionModule
│   ├── RectangleDetector.swift      // VNDetectRectanglesRequest, background queue
│   └── QuadOverlayView.swift        // SwiftUI overlay, esquinas arrastrables
├── ProcessingModule
│   ├── PerspectiveCorrector.swift   // CIPerspectiveCorrection
│   └── AdjustmentPipeline.swift     // CIColorControls, invert, B/N
├── GalleryModule
│   ├── GalleryStore.swift           // FileManager + JSON manifest, @Published items
│   ├── GalleryView.swift            // SwiftUI grid
│   └── GalleryItem.swift            // Model: id, thumbData, fullResURL, date
├── ExportModule
│   └── ExportController.swift       // UIActivityViewController, PHPhotoLibrary
└── UI
    ├── ContentView.swift            // Root tab/nav
    ├── ScanView.swift               // Cámara + quad overlay
    ├── EditView.swift               // Sliders, toggles modo
    └── DesignSystem.swift           // Tipografía, colores, spacing (Swiss/Mono)
```

---

## Pasos de implementación

### Paso 1 — Setup del proyecto
- Nuevo proyecto Xcode, SwiftUI lifecycle, target iOS 17+
- Info.plist: `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription`
- Estructura de carpetas según arquitectura de módulos anterior

### Paso 2 — CameraSession
```swift
// CameraSession.swift
import AVFoundation

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    var onFrame: ((CVPixelBuffer) -> Void)?

    func start() {
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: .global(qos: .userInitiated))
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_32BGRA]
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() { session.stopRunning() }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buf)
    }
}
```

### Paso 3 — Live preview con Metal
```swift
// CameraPreviewView.swift — versión corregida (el brief original omitía el commandBuffer)
import MetalKit, CoreImage

struct CameraPreviewView: UIViewRepresentable {
    let session: CameraSession
    private let device = MTLCreateSystemDefaultDevice()!
    private lazy var context = CIContext(mtlDevice: device)

    func makeUIView(context ctx: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.framebufferOnly = false          // necesario para CIContext.render
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 30
        return view
    }

    func updateUIView(_ view: MTKView, context ctx: Context) {
        session.onFrame = { [weak view] pixelBuffer in
            guard let view,
                  let commandQueue = view.device?.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let drawable = view.currentDrawable else { return }
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            self.context.render(ci,
                                to: drawable.texture,
                                commandBuffer: commandBuffer,
                                bounds: ci.extent,
                                colorSpace: colorSpace)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
```

### Paso 4 — Detección de rectángulo
```swift
// RectangleDetector.swift
import Vision

final class RectangleDetector {
    private let request: VNDetectRectanglesRequest = {
        let r = VNDetectRectanglesRequest()
        r.minimumConfidence    = 0.8
        r.minimumAspectRatio   = 0.3
        r.maximumObservations  = 1
        return r
    }()

    func detect(in pixelBuffer: CVPixelBuffer,
                completion: @escaping (VNRectangleObservation?) -> Void) {
        // Ejecutar en background; callback siempre llega al main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: .up)
            try? handler.perform([self.request])
            let result = self.request.results?.first
            DispatchQueue.main.async { completion(result) }
        }
    }
}
```

### Paso 5 — Quad overlay arrastrables (SwiftUI)
```swift
// QuadOverlayView.swift
struct QuadOverlayView: View {
    @Binding var corners: [CGPoint]   // 4 puntos en coordenadas de vista
    let viewSize: CGSize

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: corners[0])
                corners[1...].forEach { p.addLine(to: $0) }
                p.closeSubpath()
            }
            .stroke(Color.yellow, lineWidth: 2)
            .fill(Color.yellow.opacity(0.15))

            ForEach(corners.indices, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .position(corners[i])
                    .gesture(DragGesture()
                        .onChanged { corners[i] = $0.location })
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
    }
}
```

### Paso 6 — Corrección de perspectiva
```swift
// PerspectiveCorrector.swift
import CoreImage

// quad: [TL, TR, BR, BL] en coordenadas de píxel de la imagen
func correct(image: CIImage, quad: [CGPoint]) -> CIImage? {
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(image,                        forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: quad[0]),   forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: quad[1]),   forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: quad[3]),   forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: quad[2]),   forKey: "inputBottomRight")
    return filter.outputImage
}

// Conversión: coordenadas normalizadas Vision → píxeles imagen
func vnToPixel(_ pt: CGPoint, imageSize: CGSize) -> CGPoint {
    CGPoint(x: pt.x * imageSize.width,
            y: (1 - pt.y) * imageSize.height)   // flip Y: Vision origin=bottom, CIImage origin=bottom (mismo), UIKit origin=top
}
```

### Paso 7 — Pipeline de ajustes
```swift
// AdjustmentPipeline.swift
import CoreImage.CIFilterBuiltins

struct Adjustments {
    var brightness: Float = 0    // -1.0 … 1.0
    var contrast:   Float = 1    //  0.5 … 2.0
    var saturation: Float = 1    //  0.0 … 2.0
    var invert:     Bool  = false
    var bw:         Bool  = false
}

func apply(_ image: CIImage, adj: Adjustments) -> CIImage {
    var out = image
    let cc = CIFilter.colorControls()
    cc.inputImage  = out
    cc.brightness  = adj.brightness
    cc.contrast    = adj.contrast
    cc.saturation  = adj.bw ? 0 : adj.saturation
    out = cc.outputImage ?? out
    if adj.invert {
        let inv = CIFilter.colorInvert()
        inv.inputImage = out
        out = inv.outputImage ?? out
    }
    return out
}
```

### Paso 8 — Exportar
```swift
// ExportController.swift
import Photos, UIKit

func saveToPhotos(_ image: CIImage,
                  context: CIContext,
                  completion: @escaping (Bool) -> Void) {
    guard let cgImage = context.createCGImage(image, from: image.extent) else {
        completion(false); return
    }
    let uiImage = UIImage(cgImage: cgImage)
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
            completion(false); return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
        }, completionHandler: { ok, _ in completion(ok) })
    }
}

func share(_ image: CIImage, context: CIContext, from vc: UIViewController) {
    guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
    let uiImage = UIImage(cgImage: cgImage)
    let sheet = UIActivityViewController(activityItems: [uiImage],
                                         applicationActivities: nil)
    vc.present(sheet, animated: true)
}
```

### Paso 9 — Galería
```swift
// GalleryStore.swift
final class GalleryStore: ObservableObject {
    @Published var items: [GalleryItem] = []
    @Published var error: Error?
    private let dir: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("gallery", isDirectory: true)

    func save(image: CIImage, context: CIContext) {
        do {
            try FileManager.default.createDirectory(at: dir,
                                                    withIntermediateDirectories: true)
            let id  = UUID().uuidString
            let url = dir.appendingPathComponent("\(id).heic")
            guard let data = context.heifRepresentation(of: image,
                                                         format: .RGBA8,
                                                         colorSpace: CGColorSpaceCreateDeviceRGB())
            else { throw GalleryError.encodingFailed }
            try data.write(to: url)
            let thumb = makeThumbnail(image: image, context: context, maxPx: 400)
            items.insert(GalleryItem(id: id, thumbData: thumb,
                                     fullResURL: url, date: .now), at: 0)
            try persist()
        } catch {
            self.error = error
        }
    }

    private func persist() throws {
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let data = try JSONEncoder().encode(items)
        try data.write(to: manifestURL)
    }
}

enum GalleryError: Error { case encodingFailed }
```

---

## Gotchas críticos

### Sistemas de coordenadas
- **Vision**: normalizadas 0–1, origen Y=0 en la parte *inferior*
- **Core Image / CIPerspectiveCorrection**: píxeles, origen Y=0 en la parte *inferior*
- **UIKit / SwiftUI**: puntos, origen Y=0 en la parte *superior*
- Siempre convertir explícitamente en cada frontera. Ver `vnToPixel()` en Paso 6.

### CIContext — crear una sola vez
Crear un `CIContext` por frame causa memory pressure severo. Crear uno (Metal-backed) en el root y pasarlo por dependencia.

```swift
// En ContentView o App level:
let ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
```

### VNDetectRectanglesRequest — siempre en background
Vision es síncrono. Nunca llamar desde el main thread. Despachar resultado de vuelta a main antes de actualizar UI. Ver Paso 4.

### CameraSession — ciclo de vida
Llamar `session.stop()` en `onDisappear` de `ScanView` y en `UIApplication.willResignActiveNotification`. No liberar la sesión provoca consumo de batería y posible kill del proceso.

```swift
// ScanView.swift
.onDisappear { cameraSession.stop() }
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
    cameraSession.stop()
}
```

### MTKView — framebufferOnly
`framebufferOnly` debe ser `false` para que Core Image pueda escribir directamente en la textura drawable. Ver Paso 3.

### PHPhotoLibrary — permiso .addOnly
Usar `.addOnly` (iOS 14+) evita pedir acceso completo a la biblioteca. Siempre llamar `requestAuthorization` antes de `performChanges`.

### HEIC export
`CIContext.heifRepresentation` disponible desde iOS 11. Para targets más bajos (si algún día baja el target), envolver en `if #available(iOS 11, *)`.

---

## Estimación de esfuerzo
| Fase | Días (1 dev iOS con experiencia) |
|------|----------------------------------|
| Setup + cámara + Metal preview | 2 |
| Vision detección + overlay | 2 |
| Corrección de perspectiva | 1 |
| Pipeline ajustes + Edit UI | 2 |
| Export + permisos Fotos | 1 |
| Galería persistencia | 2 |
| Polish, edge cases, testing | 3 |
| **Total** | **~13 días** |

Sin experiencia previa en AVFoundation/Vision: multiplicar por 1.5–2×.

---

## Rama de trabajo
Desarrollar y hacer push **siempre en `main`**. No usar ramas de feature salvo indicación explícita.

## Versión
Formato `vX.Y`. Incrementar en cada commit a `main` (patch: X.Y → X.Y+1).
Versión de arranque: **v1.0**
