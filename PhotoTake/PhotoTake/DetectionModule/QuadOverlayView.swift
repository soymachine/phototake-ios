import SwiftUI

struct QuadOverlayView: View {
    @Binding var corners: [CGPoint]
    let viewSize: CGSize
    var isInteractive: Bool = true
    var animated: Bool = true
    var latestFrame: UIImage? = nil
    var dragBounds: CGRect? = nil

    @State private var draggingIndex: Int? = nil

    var body: some View {
        ZStack {
            quadPath.fill(Color.yellow.opacity(0.10))
            quadPath.stroke(Color.yellow, lineWidth: 2)

            if isInteractive {
                ForEach(corners.indices, id: \.self) { i in
                    handle(for: i)
                }
                if let idx = draggingIndex, corners.indices.contains(idx),
                   let frame = latestFrame {
                    LoupeView(image: frame,
                              focalPoint: corners[idx],
                              viewSize: viewSize)
                        .position(loupePosition(for: corners[idx]))
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .zIndex(10)
                }
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .animation(animated ? .easeOut(duration: 0.15) : nil, value: corners)
        .animation(.easeOut(duration: 0.15), value: draggingIndex)
    }

    private func handle(for index: Int) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
            .position(corners[index])
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let b = dragBounds ?? CGRect(origin: .zero, size: viewSize)
                        corners[index] = CGPoint(
                            x: max(b.minX, min(b.maxX, value.location.x)),
                            y: max(b.minY, min(b.maxY, value.location.y))
                        )
                        draggingIndex = index
                    }
                    .onEnded { _ in draggingIndex = nil }
            )
    }

    private var quadPath: Path {
        guard corners.count == 4 else { return Path() }
        return Path { p in
            p.move(to: corners[0])
            p.addLine(to: corners[1])
            p.addLine(to: corners[2])
            p.addLine(to: corners[3])
            p.closeSubpath()
        }
    }

    private func loupePosition(for point: CGPoint) -> CGPoint {
        let d: CGFloat = 96
        let gap: CGFloat = 22
        return CGPoint(
            x: max(d / 2, min(viewSize.width - d / 2, point.x)),
            y: max(d / 2 + gap, point.y - 28 - gap)
        )
    }
}

// MARK: - Loupe

struct LoupeView: View {
    let image: UIImage
    let focalPoint: CGPoint
    let viewSize: CGSize

    private let diameter: CGFloat = 96
    private let zoom: CGFloat = 2.0

    var body: some View {
        ZStack {
            Color.black
            Image(uiImage: image)
                .resizable()
                .frame(width: viewSize.width * zoom,
                       height: viewSize.height * zoom)
                // Shift so that focalPoint lands at the center (diameter/2, diameter/2) of the loupe.
                // The image (viewSize*zoom) is centered in the ZStack by default; its center maps to
                // viewSize/2 in source coords. Offset = zoom*(viewSize/2 - focalPoint).
                .offset(x: zoom * (viewSize.width  / 2 - focalPoint.x),
                        y: zoom * (viewSize.height / 2 - focalPoint.y))
            // Crosshair — Rectangle views are always centered in the ZStack,
            // unlike Path which has its own coordinate system and gets clipped.
            Color.white.opacity(0.4).frame(width: 28, height: 3)   // horizontal shadow
            Color.white.opacity(0.4).frame(width: 3, height: 28)   // vertical shadow
            Color.yellow.frame(width: 28, height: 1.5)             // horizontal
            Color.yellow.frame(width: 1.5, height: 28)             // vertical
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
        .shadow(color: .black.opacity(0.6), radius: 6)
    }
}
