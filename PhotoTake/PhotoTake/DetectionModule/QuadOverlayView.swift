import SwiftUI

struct QuadOverlayView: View {
    @Binding var corners: [CGPoint]
    let viewSize: CGSize
    var isInteractive: Bool = true
    var animated: Bool = true
    var latestFrame: UIImage? = nil

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
                        corners[index] = CGPoint(
                            x: max(0, min(viewSize.width, value.location.x)),
                            y: max(0, min(viewSize.height, value.location.y))
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
            // Crosshair
            Path { p in
                p.move(to: CGPoint(x: diameter / 2, y: diameter / 2 - 10))
                p.addLine(to: CGPoint(x: diameter / 2, y: diameter / 2 + 10))
                p.move(to: CGPoint(x: diameter / 2 - 10, y: diameter / 2))
                p.addLine(to: CGPoint(x: diameter / 2 + 10, y: diameter / 2))
            }
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
        .shadow(color: .black.opacity(0.6), radius: 6)
    }
}
